import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../models/user_presence.dart';
import '../models/room_media_post.dart';
import '../models/media_post.dart';
import '../models/place.dart';
import 'supabase_gate.dart';
import 'auth_service.dart';

const int ROOM_MEDIA_LIMIT = 30;

/// Supabase-backed chat repository with realtime support
/// 
/// Requires Supabase tables:
/// - public.messages (id, room_id, user_id, user_name, user_avatar, text, created_at)
/// - public.chat_rooms (id, place_id, created_at)
/// 
/// Realtime must be enabled on public.messages table in Supabase Dashboard.
class SupabaseChatRepository {
  static final SupabaseChatRepository _instance = SupabaseChatRepository._internal();
  factory SupabaseChatRepository() => _instance;
  SupabaseChatRepository._internal();

  // In-memory cache by roomId (for offline resilience)
  final Map<String, List<ChatMessage>> _messagesCache = {};
  
  // Stream controllers by roomId
  final Map<String, StreamController<List<ChatMessage>>> _streamControllers = {};
  final Map<String, StreamController<List<RoomMediaPost>>> _mediaControllers = {};
  
  // Realtime subscriptions by roomId
  final Map<String, RealtimeChannel> _realtimeChannels = {};
  final Map<String, RealtimeChannel> _mediaChannels = {};
  
  // Presence channels by roomId
  final Map<String, RealtimeChannel> _presenceChannels = {};
  
  // Presence count stream controllers by roomId
  final Map<String, StreamController<int>> _presenceCountControllers = {};
  // Presence roster stream controllers by roomId
  final Map<String, StreamController<List<PresenceProfile>>>
      _presenceRosterControllers = {};

  /// Ensure chat room exists in database
  /// If placeId is not available, uses roomId as place_id (fallback)
  /// This will not throw if room already exists (upsert handles it)
  Future<void> ensureRoomExists(String roomId, String? placeId) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot ensure room exists (Supabase disabled)');
      }
      return;
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Upsert chat room - will not throw if room already exists
      // Use onConflict to handle existing rooms gracefully
      await supabase.from('chat_rooms').upsert({
        'id': roomId,
        'place_id': placeId?.isNotEmpty == true ? placeId : roomId, // Fallback to roomId if placeId is null/empty
      }, onConflict: 'id');
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Room ensured: $roomId (place_id: ${placeId ?? roomId})');
      }
    } catch (e) {
      // Silently continue - room might already exist or creation might fail
      // This should not break the chat flow
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Room ensure completed (may already exist): $roomId');
      }
    }
  }

  /// Ensure chat room exists for a placeId (uuid)
  Future<void> ensureRoom(String placeId) async {
    final roomId = 'place_$placeId';
    await ensureRoomExists(roomId, placeId);
  }

  /// Ensure room only if place is social-enabled
  /// Returns true if room was ensured, false if skipped
  Future<bool> ensureRoomForPlace(Place place) async {
    if (!place.socialEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Skipped ensureRoom (social disabled) placeId=${place.id}');
      }
      return false;
    }
    if (kDebugMode) {
      debugPrint('STREAM: ensureRoom SKIPPED (feed mode)');
    }
    return false;
  }

  String? _placeIdFromRoomId(String roomId) {
    if (roomId.startsWith('place_')) {
      return roomId.substring('place_'.length);
    }
    return null;
  }

  /// Get messages for a room (sync, fetches from Supabase)
  Future<List<ChatMessage>> getMessages(String roomId, {int limit = 50}) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot get messages (Supabase disabled)');
      }
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUserId = AuthService.instance.currentUser?.id;
      
      // Fetch last 50 messages ordered by created_at ascending
      // Filter to only today's messages for activity-based features
      final todayStart = DateTime.now();
      final today = DateTime(todayStart.year, todayStart.month, todayStart.day);
      final todayStartIso = today.toIso8601String();
      
      final response = await supabase
          .from('messages')
          .select()
          .eq('room_id', roomId)
          .gte('created_at', todayStartIso) // Only messages from today onwards
          .order('created_at', ascending: true)
          .limit(limit);

      var messages = (response as List)
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>, currentUserId: currentUserId))
          .toList();

      messages = await _attachMessageReactions(messages, currentUserId);

      // Update cache
      _messagesCache[roomId] = messages;

      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Loaded ${messages.length} messages for room $roomId');
      }

      return messages;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to get messages: $e');
      }
      // Return cached messages if available, otherwise empty list
      return _messagesCache[roomId] ?? [];
    }
  }

  Future<List<ChatMessage>> _attachMessageReactions(
    List<ChatMessage> messages,
    String? currentUserId,
  ) async {
    if (!SupabaseGate.isEnabled) return messages;
    if (messages.isEmpty) return messages;
    final supabase = SupabaseGate.client;
    final messageIds = messages.map((message) => message.id).toList();

    Map<String, String> currentReactions = {};
    Map<String, Map<String, int>> countsByMessage = {};

    try {
      if (currentUserId != null) {
        final userReactions = await supabase
            .from('room_media_reactions')
            .select('message_id,reaction')
            .eq('user_id', currentUserId)
            .inFilter('message_id', messageIds);
        for (final row in userReactions as List) {
          final messageId = row['message_id'] as String?;
          final reaction = row['reaction'] as String?;
          if (messageId == null || reaction == null) continue;
          currentReactions[messageId] = reaction;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Failed to load user message reactions: $e');
      }
    }

    try {
      final allReactions = await supabase
          .from('room_media_reactions')
          .select('message_id,reaction')
          .inFilter('message_id', messageIds);
      for (final row in allReactions as List) {
        final messageId = row['message_id'] as String?;
        final reaction = row['reaction'] as String?;
        if (messageId == null || reaction == null) continue;
        final perMessage = countsByMessage.putIfAbsent(messageId, () => {});
        perMessage[reaction] = (perMessage[reaction] ?? 0) + 1;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Failed to load message reaction counts: $e');
      }
    }

    return messages.map((message) {
      final counts = countsByMessage[message.id] ?? const {};
      final total = counts.values.fold<int>(0, (sum, value) => sum + value);
      return ChatMessage(
        id: message.id,
        roomId: message.roomId,
        userId: message.userId,
        userName: message.userName,
        userAvatar: message.userAvatar,
        text: message.text,
        mediaUrl: message.mediaUrl,
        createdAt: message.createdAt,
        isMine: message.isMine,
        reactionsCount: total,
        currentUserReaction: currentReactions[message.id],
        reactionCounts: counts,
      );
    }).toList();
  }

  Future<List<ChatMessage>> attachMessageReactions(
    List<ChatMessage> messages,
  ) async {
    final currentUserId = AuthService.instance.currentUser?.id;
    return _attachMessageReactions(messages, currentUserId);
  }

  Future<bool> reactToMessage({
    required String messageId,
    required String reaction,
  }) async {
    if (!SupabaseGate.isEnabled) return false;
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) return false;
    try {
      final supabase = SupabaseGate.client;
      final existingRows = await supabase
          .from('room_media_reactions')
          .select('reaction')
          .eq('message_id', messageId)
          .eq('user_id', currentUser.id);
      final rows = existingRows as List;
      final existingEmoji = rows.isNotEmpty
          ? rows.first['reaction'] as String?
          : null;

      if (existingEmoji == reaction) {
        await supabase
            .from('room_media_reactions')
            .delete()
            .eq('message_id', messageId)
            .eq('user_id', currentUser.id);
        return true;
      }

      final data = {
        'message_id': messageId,
        'user_id': currentUser.id,
        'reaction': reaction,
      };
      await supabase
          .from('room_media_reactions')
          .upsert(data, onConflict: 'message_id,user_id');
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to react to message: $e');
      }
      return false;
    }
  }

  /// Watch messages for a room (reactive stream with realtime updates)
  /// 
  /// - Fetches last 50 messages (asc) on first subscription
  /// - Subscribes to realtime INSERT on public.messages filtered by room_id
  /// - On insert: appends in correct order and emits
  /// - Avoids duplicates by message id
  /// - Keeps a broadcast stream per roomId (caches controllers)
  Stream<List<ChatMessage>> watchMessages(String roomId, {int limit = 50}) {
    // Create stream controller if it doesn't exist (cache per roomId)
    if (!_streamControllers.containsKey(roomId)) {
      _streamControllers[roomId] = StreamController<List<ChatMessage>>.broadcast();
      
      // Load initial messages (limit, ascending order)
      getMessages(roomId, limit: limit).then((messages) {
        if (!_streamControllers[roomId]!.isClosed) {
          _streamControllers[roomId]!.add(messages);
        }
      }).catchError((e) {
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to load initial messages: $e');
        }
        // Emit empty list on error
        if (!_streamControllers[roomId]!.isClosed) {
          _streamControllers[roomId]!.add([]);
        }
      });

      // Subscribe to realtime updates if Supabase is enabled
      if (SupabaseGate.isEnabled) {
        _subscribeToRealtime(roomId);
      }
    }
    
    return _streamControllers[roomId]!.stream;
  }

  /// Subscribe to realtime updates for a room
  /// 
  /// Subscribes to INSERT events on public.messages filtered by room_id.
  /// On insert: appends message in correct order (by created_at) and emits.
  /// Avoids duplicates by checking message id.
  void _subscribeToRealtime(String roomId) {
    if (!SupabaseGate.isEnabled) return;
    if (_realtimeChannels.containsKey(roomId)) return; // Already subscribed

    try {
      final supabase = SupabaseGate.client;
      final currentUserId = AuthService.instance.currentUser?.id;

      // Create realtime channel for this room
      final channel = supabase.channel('messages:$roomId');
      
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (payload) {
          if (kDebugMode) {
            debugPrint('📨 SupabaseChatRepository: New message received for room $roomId');
          }

          try {
            // payload.newRecord is already Map<String, dynamic> from Supabase
            final newMessage = ChatMessage.fromJson(
              Map<String, dynamic>.from(payload.newRecord),
              currentUserId: currentUserId,
            );

            // Get current messages from cache
            final messages = List<ChatMessage>.from(_messagesCache[roomId] ?? []);
            
            // Avoid duplicates by checking message id
            final existingIds = messages.map((m) => m.id).toSet();
            if (existingIds.contains(newMessage.id)) {
              if (kDebugMode) {
                debugPrint('⚠️ SupabaseChatRepository: Duplicate message ignored (id: ${newMessage.id})');
              }
              return;
            }

            // Only append if message is from today (for daily window)
            // Previous days are automatically ignored
            if (!newMessage.isToday) {
              // Message from previous day - ignore for activity tracking
              if (kDebugMode) {
                debugPrint('ℹ️ SupabaseChatRepository: Ignoring message from previous day (daily window)');
              }
              return;
            }

            // Append new message
            messages.add(newMessage);
            
            // Sort by created_at to maintain correct order (ascending)
            messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
            
            // Update cache
            _messagesCache[roomId] = messages;

            // Emit updated list via stream
            if (!_streamControllers[roomId]!.isClosed) {
              _streamControllers[roomId]!.add(List.unmodifiable(messages));
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ SupabaseChatRepository: Failed to process realtime message: $e');
            }
          }
        },
      ).subscribe();

      _realtimeChannels[roomId] = channel;

      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Subscribed to realtime for room $roomId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to subscribe to realtime: $e');
      }
    }
  }

  /// Watch media posts for a room (reactive stream with realtime updates)
  Stream<List<RoomMediaPost>> watchRoomMediaPosts(String roomId,
      {int limit = ROOM_MEDIA_LIMIT}) {
    if (!_mediaControllers.containsKey(roomId)) {
      _mediaControllers[roomId] =
          StreamController<List<RoomMediaPost>>.broadcast();

      fetchRoomMediaPosts(roomId, limit: limit).then((posts) {
        if (!_mediaControllers[roomId]!.isClosed) {
          _mediaControllers[roomId]!.add(posts);
        }
      }).catchError((e) {
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to load media posts: $e');
        }
        if (!_mediaControllers[roomId]!.isClosed) {
          _mediaControllers[roomId]!.add([]);
        }
      });

      if (SupabaseGate.isEnabled) {
        _subscribeToMediaRealtime(roomId, limit: limit);
      }
    }

    return _mediaControllers[roomId]!.stream;
  }

  void _subscribeToMediaRealtime(String roomId, {required int limit}) {
    if (!SupabaseGate.isEnabled) return;
    if (_mediaChannels.containsKey(roomId)) return;

    try {
      final supabase = SupabaseGate.client;
      final channel = supabase.channel('room_media_posts:$roomId');
      channel.onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'room_media_posts',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'room_id',
          value: roomId,
        ),
        callback: (_) async {
          if (kDebugMode) {
            debugPrint('📹 SupabaseChatRepository: New media post in $roomId');
          }
          final posts = await fetchRoomMediaPosts(roomId, limit: limit);
          if (_mediaControllers[roomId] != null &&
              !_mediaControllers[roomId]!.isClosed) {
            _mediaControllers[roomId]!.add(posts);
          }
        },
      );
      channel.subscribe();
      _mediaChannels[roomId] = channel;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Media realtime failed: $e');
      }
    }
  }

  /// Upload image to Supabase Storage and get public URL
  /// 
  /// Uploads to bucket "chat_media" under path: roomId/timestamp_filename
  /// Returns public URL for the uploaded file.
  Future<String> uploadImage(String roomId, List<int> imageBytes, String filename) async {
    if (!SupabaseGate.isEnabled) {
      throw Exception('Supabase ist nicht konfiguriert');
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Generate unique filename: timestamp_filename
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = '$roomId/${timestamp}_$filename';
      
      // Upload to Supabase Storage bucket "chat_media"
      await supabase.storage
          .from('chat_media')
          .uploadBinary(
            path,
            Uint8List.fromList(imageBytes),
            fileOptions: const FileOptions(
              upsert: false,
              contentType: 'image/jpeg',
            ),
          );
      
      // Get public URL
      final publicUrl = supabase.storage
          .from('chat_media')
          .getPublicUrl(path);
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Image uploaded to $path');
      }
      
      return publicUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to upload image: $e');
      }
      rethrow;
    }
  }

  /// Send a text message to a room (convenience method)
  /// 
  /// Creates a ChatMessage and sends it via sendMessage.
  /// Ensures user_id is the Supabase auth user id (uuid) when SupabaseGate is enabled.
  Future<void> sendTextMessage(String roomId, String userId, String text) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot send message (Supabase disabled)');
      }
      throw Exception('Supabase ist nicht konfiguriert');
    }

    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be logged in to send messages');
      }

      await ensureRoomExists(roomId, _placeIdFromRoomId(roomId));

      // Create message object
      final message = ChatMessage(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        roomId: roomId,
        userId: userId,
        userName: currentUser.name,
        userAvatar: currentUser.photoUrl,
        text: text,
        createdAt: DateTime.now(),
        isMine: true,
      );

      await sendMessage(roomId, message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to send text message: $e');
      }
      rethrow;
    }
  }

  /// Send a message with media (image/video) to a room
  /// 
  /// Creates a ChatMessage with mediaUrl and sends it via sendMessage.
  /// Ensures user_id is the Supabase auth user id (uuid) when SupabaseGate is enabled.
  Future<void> sendMediaMessage(
    String roomId,
    String userId,
    String mediaUrl,
    {String text = ''}
  ) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot send message (Supabase disabled)');
      }
      throw Exception('Supabase ist nicht konfiguriert');
    }

    try {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be logged in to send messages');
      }

      await ensureRoomExists(roomId, _placeIdFromRoomId(roomId));

      // Create message object with mediaUrl
      final message = ChatMessage(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
        roomId: roomId,
        userId: userId,
        userName: currentUser.name,
        userAvatar: currentUser.photoUrl,
        text: text,
        mediaUrl: mediaUrl,
        createdAt: DateTime.now(),
        isMine: true,
      );

      await sendMessage(roomId, message);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to send media message: $e');
      }
      rethrow;
    }
  }

  /// Send a message to a room
  /// 
  /// Ensures user_id is the Supabase auth user id (uuid) when SupabaseGate is enabled.
  /// Inserts into messages table with: room_id, user_id, user_name, user_avatar, text, created_at
  Future<void> sendMessage(String roomId, ChatMessage message) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot send message (Supabase disabled)');
      }
      throw Exception('Supabase ist nicht konfiguriert');
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Get current authenticated user - must be logged in
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be logged in to send messages');
      }

      // Ensure user_id is the Supabase auth user id (uuid)
      // Use the current user's id from AuthService (which comes from Supabase session)
      final userId = currentUser.id;
      
      // Prepare message data for Supabase insert
      // Fields: room_id, user_id, user_name, user_avatar, text, media_url, created_at
      final messageData = {
        'room_id': roomId,
        'user_id': userId, // Use authenticated user's UUID
        'user_name': message.userName,
        'user_avatar': message.userAvatar,
        'text': message.text,
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty)
          'media_url': message.mediaUrl,
        'created_at': message.createdAt.toIso8601String(),
      };
      
      // Insert message into Supabase
      await supabase.from('messages').insert(messageData);
      
      // Update lastActiveAt in chat_rooms table
      // This tracks activity (messages and media posts)
      final now = DateTime.now().toIso8601String();
      try {
        await supabase
            .from('chat_rooms')
            .update({'last_active_at': now})
            .eq('id', roomId);
      } catch (e) {
        // Silently continue if update fails (room might not exist yet or column missing)
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to update lastActiveAt: $e');
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Message sent to room $roomId (user_id: $userId)');
      }
      
      // Note: Realtime subscription will handle the update automatically
      // We don't need to optimistically update cache here to avoid duplicates
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to send message: $e');
      }
      rethrow;
    }
  }

  /// Unsubscribe from realtime updates for a room
  void _unsubscribeFromRealtime(String roomId) {
    final channel = _realtimeChannels.remove(roomId);
    if (channel != null) {
      try {
        if (SupabaseGate.isEnabled) {
          final supabase = SupabaseGate.client;
          supabase.removeChannel(channel);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to unsubscribe: $e');
        }
      }
    }
  }

  /// Dispose resources for a room
  void disposeRoom(String roomId) {
    _unsubscribeFromRealtime(roomId);
    final controller = _streamControllers.remove(roomId);
    if (controller != null && !controller.isClosed) {
      controller.close();
    }
    _messagesCache.remove(roomId);
  }

  /// Join presence for a room
  /// 
  /// Tracks user presence in the room using Supabase Realtime presence.
  /// User must be logged in.
  Future<void> joinRoomPresence(String roomId, {required String userId, required String userName}) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot join presence (Supabase disabled)');
      }
      return;
    }

    // Reuse existing channel if it exists (might be from watching)
    RealtimeChannel? channel = _presenceChannels[roomId];
    
    if (channel != null) {
      // Channel exists, just track on it
      try {
        await channel.track({
          'user_id': userId,
          'user_name': userName,
          'user_avatar': AuthService.instance.currentUser?.photoUrl,
        });
        if (kDebugMode) {
          debugPrint('✅ SupabaseChatRepository: Tracked presence on existing channel for room $roomId');
        }
        return;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to track on existing channel: $e');
        }
        // If channel wasn't subscribed yet, subscribe then track
        channel.subscribe((status, [err]) async {
          if (status == RealtimeSubscribeStatus.subscribed) {
            try {
              await channel!.track({
                'user_id': userId,
                'user_name': userName,
                'user_avatar': AuthService.instance.currentUser?.photoUrl,
              });
            } catch (_) {}
          }
        });
        return;
      }
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Create presence channel for this room
      final presenceChannel = supabase.channel('presence:$roomId');
      channel = presenceChannel;
      
      // Subscribe to presence changes
      presenceChannel.onPresenceSync((payload) {
        _updatePresenceCount(roomId, presenceChannel);
        _emitPresenceRoster(roomId, presenceChannel);
      });
      
      presenceChannel.onPresenceJoin((payload, [ref]) {
        if (kDebugMode) {
          debugPrint('👤 SupabaseChatRepository: User joined presence in room $roomId');
        }
        _updatePresenceCount(roomId, presenceChannel);
        _emitPresenceRoster(roomId, presenceChannel);
      });
      
      presenceChannel.onPresenceLeave((payload, [ref]) {
        if (kDebugMode) {
          debugPrint('👋 SupabaseChatRepository: User left presence in room $roomId');
        }
        _updatePresenceCount(roomId, presenceChannel);
        _emitPresenceRoster(roomId, presenceChannel);
      });
      
      presenceChannel.subscribe((status, [err]) async {
        if (status == RealtimeSubscribeStatus.subscribed) {
          try {
            await presenceChannel.track({
              'user_id': userId,
              'user_name': userName,
              'user_avatar': AuthService.instance.currentUser?.photoUrl,
            });
            if (kDebugMode) {
              debugPrint('✅ SupabaseChatRepository: Joined presence for room $roomId');
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ SupabaseChatRepository: Failed to track after subscribe: $e');
            }
          }
        }
      });
      
      _presenceChannels[roomId] = channel;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to join presence: $e');
      }
    }
  }

  /// Leave presence for a room
  /// 
  /// Only untracks if user was actually joined (tracked).
  /// If channel was only for watching, just removes it.
  Future<void> leaveRoomPresence(String roomId) async {
    if (!SupabaseGate.isEnabled) return;
    
    final channel = _presenceChannels.remove(roomId);
    if (channel != null) {
      try {
        // Try to untrack (only works if we were tracking)
        // If we were only watching, this will fail silently, which is fine
        try {
          await channel.untrack();
        } catch (e) {
          // Channel might not have been tracked (was watching-only)
          if (kDebugMode) {
            debugPrint('ℹ️ SupabaseChatRepository: Channel was watching-only, no untrack needed');
          }
        }
        
        final supabase = SupabaseGate.client;
        supabase.removeChannel(channel);
        
        if (kDebugMode) {
          debugPrint('✅ SupabaseChatRepository: Left presence for room $roomId');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to leave presence: $e');
        }
      }
    }
    
    // Note: Don't close presence count stream controller here
    // It might still be used by other watchers (e.g., StreamScreen)
    // Controller will be closed when dispose() is called
  }

  /// Watch presence count for a room
  /// 
  /// Returns a stream of the current number of users in the room.
  /// Can be used to watch presence without joining (e.g., in StreamScreen).
  /// If a channel already exists (from joinRoomPresence), reuses it.
  Stream<int> watchPresenceCount(String roomId) {
    // Create stream controller if it doesn't exist (cache per roomId)
    if (!_presenceCountControllers.containsKey(roomId)) {
      _presenceCountControllers[roomId] = StreamController<int>.broadcast();
      
      // If channel exists (from joinRoomPresence), emit current count
      final existingChannel = _presenceChannels[roomId];
      if (existingChannel != null) {
        _updatePresenceCount(roomId, existingChannel);
        _emitPresenceRoster(roomId, existingChannel);
      } else if (SupabaseGate.isEnabled) {
        // Create a watching-only channel (subscribe but don't track)
        _createWatchingChannel(roomId);
      } else {
        // Emit 0 if Supabase disabled
        _presenceCountControllers[roomId]!.add(0);
      }
    }
    
    return _presenceCountControllers[roomId]!.stream;
  }

  /// Create a watching-only channel (subscribe to presence but don't track)
  void _createWatchingChannel(String roomId) {
    if (!SupabaseGate.isEnabled) return;
    // Skip if already exists (either from join or previous watch)
    if (_presenceChannels.containsKey(roomId)) return;

    try {
      final supabase = SupabaseGate.client;
      
      // Create presence channel for watching only (no track)
      final channel = supabase.channel('presence:$roomId');
      
      // Subscribe to presence changes (but don't track - we're just watching)
      channel.onPresenceSync((payload) {
        _updatePresenceCount(roomId, channel);
        _emitPresenceRoster(roomId, channel);
      });
      
      channel.onPresenceJoin((payload, [ref]) {
        if (kDebugMode) {
          debugPrint('👤 SupabaseChatRepository: User joined presence in room $roomId (watching)');
        }
        _updatePresenceCount(roomId, channel);
        _emitPresenceRoster(roomId, channel);
      });
      
      channel.onPresenceLeave((payload, [ref]) {
        if (kDebugMode) {
          debugPrint('👋 SupabaseChatRepository: User left presence in room $roomId (watching)');
        }
        _updatePresenceCount(roomId, channel);
        _emitPresenceRoster(roomId, channel);
      });
      
      channel.subscribe();
      
      // Store channel for watching (but mark it differently - we'll check if it's tracked)
      _presenceChannels[roomId] = channel;
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Created watching channel for room $roomId');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to create watching channel: $e');
      }
      // Emit 0 on error
      final controller = _presenceCountControllers[roomId];
      if (controller != null && !controller.isClosed) {
        controller.add(0);
      }
    }
  }

  /// Update presence count from channel state
  void _updatePresenceCount(String roomId, RealtimeChannel channel) {
    final presenceState = channel.presenceState();
    final count = presenceState.length;
    
    if (kDebugMode) {
      debugPrint('📊 SupabaseChatRepository: Presence count for room $roomId: $count');
    }
    
    final controller = _presenceCountControllers[roomId];
    if (controller != null && !controller.isClosed) {
      controller.add(count);
    }
  }

  /// Watch presence roster for a room (list of online users).
  Stream<List<PresenceProfile>> watchPresenceRoster(String roomId) {
    if (!_presenceRosterControllers.containsKey(roomId)) {
      _presenceRosterControllers[roomId] =
          StreamController<List<PresenceProfile>>.broadcast();

      final existingChannel = _presenceChannels[roomId];
      if (existingChannel != null) {
        _emitPresenceRoster(roomId, existingChannel);
      } else if (SupabaseGate.isEnabled) {
        _createWatchingChannel(roomId);
      } else {
        _presenceRosterControllers[roomId]!.add(const []);
      }
    }
    return _presenceRosterControllers[roomId]!.stream;
  }

  void _emitPresenceRoster(String roomId, RealtimeChannel channel) {
    final controller = _presenceRosterControllers[roomId];
    if (controller == null || controller.isClosed) return;

    final dynamic state = channel.presenceState();
    final profiles = <PresenceProfile>[];
    if (state is Map) {
      for (final entry in state.entries) {
        final entries = entry.value;
        if (entries is Iterable) {
          for (final presence in entries) {
            final payload = (presence as dynamic).payload ?? presence;
            if (payload is Map) {
              final userId =
                  (payload['user_id'] as String?)?.trim().isNotEmpty == true
                      ? payload['user_id'] as String
                      : entry.key.toString();
              final userName =
                  (payload['user_name'] as String?)?.trim().isNotEmpty == true
                      ? payload['user_name'] as String
                      : 'User';
              final userAvatar = payload['user_avatar'] as String?;
              profiles.add(
                PresenceProfile(
                  userId: userId,
                  userName: userName,
                  userAvatar: userAvatar,
                ),
              );
            }
          }
        }
      }
    } else if (state is List) {
      for (final presence in state) {
        final payload = (presence as dynamic).payload ?? presence;
        if (payload is Map) {
          final userId =
              (payload['user_id'] as String?)?.trim().isNotEmpty == true
                  ? payload['user_id'] as String
                  : payload['user_name'] as String? ?? 'user';
          final userName =
              (payload['user_name'] as String?)?.trim().isNotEmpty == true
                  ? payload['user_name'] as String
                  : 'User';
          final userAvatar = payload['user_avatar'] as String?;
          profiles.add(
            PresenceProfile(
              userId: userId,
              userName: userName,
              userAvatar: userAvatar,
            ),
          );
        }
      }
    }

    controller.add(profiles);
  }

  /// Get today's activity scores for users in a room
  /// 
  /// Returns a map of userId -> UserPresence with today's message/media counts.
  /// Only counts messages from today (daily window).
  /// Previous days are automatically ignored.
  Future<Map<String, UserPresence>> getTodayActivityScores(String roomId) async {
    if (!SupabaseGate.isEnabled) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final todayStart = DailyWindow.todayStart;
      final todayStartIso = todayStart.toIso8601String();
      
      // Fetch all messages from today for this room
      final response = await supabase
          .from('messages')
          .select()
          .eq('room_id', roomId)
          .gte('created_at', todayStartIso); // Only today's messages
      
      final messages = (response as List)
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .where((msg) => msg.isToday) // Double-check: only today
          .toList();
      
      // Count messages and media per user
      final userActivity = <String, _UserActivity>{};
      
      for (final message in messages) {
        if (!userActivity.containsKey(message.userId)) {
          userActivity[message.userId] = _UserActivity(
            userId: message.userId,
            userName: message.userName,
            userAvatar: message.userAvatar,
            roomId: roomId,
            lastSeenAt: message.createdAt,
          );
        }
        
        final activity = userActivity[message.userId]!;
        if (message.mediaUrl != null && message.mediaUrl!.isNotEmpty) {
          activity.mediaCount++;
        } else {
          activity.messageCount++;
        }
        
        // Update lastSeenAt to most recent
        if (message.createdAt.isAfter(activity.lastSeenAt)) {
          activity.lastSeenAt = message.createdAt;
        }
      }
      
      // Convert to UserPresence map
      return {
        for (final entry in userActivity.entries)
          entry.key: UserPresence(
            userId: entry.value.userId,
            userName: entry.value.userName,
            userAvatar: entry.value.userAvatar,
            roomId: entry.value.roomId,
            lastSeenAt: entry.value.lastSeenAt,
            messageCountToday: entry.value.messageCount,
            mediaCountToday: entry.value.mediaCount,
            isActiveToday: entry.value.messageCount > 0 || entry.value.mediaCount > 0,
          ),
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to get today activity scores: $e');
      }
      return {};
    }
  }

  /// Create a media post in room_media_posts table (chat room media)
  /// 
  /// Media posts are separate from text messages.
  /// This updates lastActiveAt in chat_rooms table.
  /// 
  /// Note: userId parameter is ignored. The method always uses auth.currentUser.id (UUID)
  /// to ensure the stored user_id is the authenticated user's UUID, not a text string.
  Future<void> createRoomMediaPost({
    required String roomId,
    required String userId, // Parameter kept for API compatibility, but ignored
    required String mediaUrl,
    required String mediaType, // 'image' or 'video'
  }) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot create media post (Supabase disabled)');
      }
      throw Exception('Supabase ist nicht konfiguriert');
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Get current authenticated user - must be logged in
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be logged in to post media');
      }

      await ensureRoomExists(roomId, _placeIdFromRoomId(roomId));

      // Ensure user_id is the Supabase auth user id (UUID), not the userId parameter
      // This guarantees the stored user_id is always a UUID from auth.currentUser.id
      final authUserId = currentUser.id; // UUID from Supabase auth
      
      // Prepare media post data for Supabase insert
      final mediaPostData = {
        'room_id': roomId,
        'user_id': authUserId,
        'media_url': mediaUrl,
        'media_type': mediaType,
        'created_at': DateTime.now().toIso8601String(),
      };
      
      // Insert media post into Supabase
      await supabase.from('room_media_posts').insert(mediaPostData);
      
      // Update lastActiveAt in chat_rooms table
      final now = DateTime.now().toIso8601String();
      try {
        await supabase
            .from('chat_rooms')
            .update({'last_active_at': now})
            .eq('id', roomId);
      } catch (e) {
        // Silently continue if update fails (room might not exist yet or column missing)
        if (kDebugMode) {
          debugPrint('⚠️ SupabaseChatRepository: Failed to update lastActiveAt: $e');
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Media post created in room $roomId (user_id: $authUserId)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to create media post: $e');
      }
      rethrow;
    }
  }

  /// Get latest media post for a room
  /// 
  /// Returns the most recent media post (image/video) for the given room.
  /// Returns null if no media posts exist.
  Future<RoomMediaPost?> getLatestMediaPost(String roomId) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot get media post (Supabase disabled)');
      }
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      
      final response = await supabase
          .from('room_media_posts')
          .select()
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response == null) {
        return null;
      }
      
      return RoomMediaPost.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to get latest media post: $e');
      }
      return null;
    }
  }

  /// Get all media posts for a room (today only)
  /// 
  /// Returns a list of media posts created today, sorted by created_at descending.
  Future<List<RoomMediaPost>> getMediaPostsForRoom(String roomId) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot get media posts (Supabase disabled)');
      }
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Calculate today's start (00:00:00)
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayStartIso = todayStart.toIso8601String();
      
      final response = await supabase
          .from('room_media_posts')
          .select()
          .eq('room_id', roomId)
          .gte('created_at', todayStartIso) // Only today's posts
          .order('created_at', ascending: false);
      
      final posts = (response as List)
          .map((json) => RoomMediaPost.fromJson(json as Map<String, dynamic>))
          .where((post) => post.isToday) // Double-check: only today
          .toList();
      
      return posts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to get media posts: $e');
      }
      return [];
    }
  }

  /// Fetch media posts for a room (newest first), including current user reaction.
  Future<List<RoomMediaPost>> fetchRoomMediaPosts(String roomId,
      {int limit = ROOM_MEDIA_LIMIT}) async {
    if (!SupabaseGate.isEnabled) {
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseChatRepository: select room_media_posts room=$roomId limit=$limit',
        );
      }

      final response = await supabase
          .from('room_media_posts')
          .select('*')
          .eq('room_id', roomId)
          .order('created_at', ascending: false)
          .limit(limit);

      final rows = response as List;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseChatRepository: select room_media_posts count=${rows.length}',
        );
      }

      final posts = rows
          .map((row) => RoomMediaPost.fromJson(Map<String, dynamic>.from(row)))
          .toList();

      if (posts.isEmpty) {
        return posts;
      }

      final postIds = posts.map((post) => post.id).toList();
      final reactionMap = <String, String>{};
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        final reactionsResponse = await supabase
            .from('room_media_reactions')
            .select('media_post_id,reaction')
            .eq('user_id', currentUser.id)
            .inFilter('media_post_id', postIds);

        final reactionRows = reactionsResponse as List;
        for (final row in reactionRows) {
          final postId = row['media_post_id'] as String?;
          final reaction = row['reaction'] as String?;
          if (postId == null || reaction == null) continue;
          reactionMap[postId] = reaction;
        }
      }

      final countsResponse = await supabase
          .from('room_media_reactions')
          .select('media_post_id,reaction')
          .inFilter('media_post_id', postIds);

      final countsRows = countsResponse as List;
      final countsMap = <String, Map<String, int>>{
        for (final postId in postIds) postId: {},
      };
      for (final row in countsRows) {
        final postId = row['media_post_id'] as String?;
        final reaction = row['reaction'] as String?;
        if (postId == null || reaction == null) continue;
        final perPost = countsMap.putIfAbsent(postId, () => {});
        perPost[reaction] = (perPost[reaction] ?? 0) + 1;
      }

      return posts
          .map(
            (post) => RoomMediaPost(
              id: post.id,
              roomId: post.roomId,
              userId: post.userId,
              mediaUrl: post.mediaUrl,
              mediaType: post.mediaType,
              createdAt: post.createdAt,
              reactionsCount: countsMap[post.id]?.values.fold<int>(
                    0,
                    (sum, value) => sum + value,
                  ) ??
                  0,
              currentUserReaction: reactionMap[post.id],
              reactionCounts: countsMap[post.id] ?? const {},
            ),
          )
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: fetch media posts failed: $e');
      }
      return [];
    }
  }

  /// Fetch trending media posts for stage rotation (stream-only)
  /// 
  /// Returns up to 20 media posts from the last 60 minutes, sorted by:
  /// 1. reactions_count DESC (highest first)
  /// 2. created_at DESC (most recent first)
  /// 
  /// Note: This queries the room_media_posts table.
  Future<List<MediaPost>> fetchTrendingMedia(String roomId) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot fetch trending media (Supabase disabled)');
      }
      return [];
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Calculate 60 minutes ago
      final now = DateTime.now();
      final sixtyMinutesAgo = now.subtract(const Duration(minutes: 60));
      final sixtyMinutesAgoIso = sixtyMinutesAgo.toIso8601String();
      
      // Fetch media posts from last 60 minutes
      // Order by reactions_count DESC, then created_at DESC
      // Note: reactions_count must exist in the database schema
      final response = await supabase
          .from('room_media_posts')
          .select()
          .eq('room_id', roomId)
          .gte('created_at', sixtyMinutesAgoIso) // Last 60 minutes
          .order('reactions_count', ascending: false) // Highest reactions first
          .order('created_at', ascending: false) // Most recent first
          .limit(20);
      
      final posts = (response as List)
          .map((json) => MediaPost.fromJson(json as Map<String, dynamic>))
          .toList();

      // Fetch current user's reactions for all posts
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null && posts.isNotEmpty) {
        final postIds = posts.map((p) => p.id).toList();
        
        // Fetch all user reactions for these posts
        // Use OR filter for multiple post IDs
        final orFilter = postIds.map((id) => 'media_post_id.eq.$id').join(',');
        final userReactions = await supabase
            .from('room_media_reactions')
            .select('media_post_id, reaction')
            .eq('user_id', currentUser.id)
            .or(orFilter);

        // Create a map of postId -> reaction emoji
        final reactionMap = <String, String>{};
        for (final reaction in userReactions as List) {
          final postId = reaction['media_post_id'] as String;
          final emoji = reaction['reaction'] as String;
          reactionMap[postId] = emoji;
        }

        // Update posts with current user's reaction
        for (int i = 0; i < posts.length; i++) {
          final post = posts[i];
          final userReaction = reactionMap[post.id];
          if (userReaction != null) {
            posts[i] = MediaPost(
              id: post.id,
              roomId: post.roomId,
              mediaUrl: post.mediaUrl,
              createdAt: post.createdAt,
              reactionsCount: post.reactionsCount,
              currentUserReaction: userReaction,
            );
          }
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Fetched ${posts.length} trending media posts for room $roomId');
      }
      
      return posts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch trending media: $e');
      }
      return [];
    }
  }

  /// Create a media post in room_media_posts table (stream-only)
  /// 
  /// Media posts are for stream display only.
  /// The user_id is always set to auth.currentUser.id (UUID) to ensure it's a UUID, not text.
  Future<void> createMediaPost({
    required String roomId,
    required String mediaUrl,
  }) async {
    if (!SupabaseGate.isEnabled) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Cannot create media post (Supabase disabled)');
      }
      throw Exception('Supabase ist nicht konfiguriert');
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Get current authenticated user - must be logged in
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        throw Exception('User must be logged in to post media');
      }

      // Ensure user_id is the Supabase auth user id (UUID)
      // This guarantees the stored user_id is always a UUID from auth.currentUser.id
      final authUserId = currentUser.id; // UUID from Supabase auth
      
      // Prepare media post data for Supabase insert
      final mediaPostData = {
        'room_id': roomId,
        'user_id': authUserId, // UUID from auth
        'media_url': mediaUrl,
        'created_at': DateTime.now().toIso8601String(),
        'reactions_count': 0, // Initialize with 0 reactions
      };
      
      // Insert media post into Supabase
      await supabase.from('room_media_posts').insert(mediaPostData);
      
      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Media post created in room $roomId (user_id: $authUserId)');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to create media post: $e');
      }
      rethrow;
    }
  }

  /// Fetch current user's reaction for a media post
  /// Returns the reaction emoji if user has reacted, null otherwise
  Future<String?> fetchUserReactionForMedia(String mediaPostId) async {
    if (!SupabaseGate.isEnabled) {
      return null;
    }

    try {
      final supabase = SupabaseGate.client;
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        return null;
      }

      final response = await supabase
          .from('room_media_reactions')
          .select('reaction')
          .eq('media_post_id', mediaPostId)
          .eq('user_id', currentUser.id)
          .limit(1);

      final rows = response as List;
      if (rows.isEmpty) return null;
      final reaction = rows.first['reaction'] as String?;
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseChatRepository: current user reaction for $mediaPostId = $reaction',
        );
      }
      return reaction;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Failed to fetch user reaction: $e');
      }
      return null;
    }
  }

  /// React to a media post
  /// 
  /// Reads existing reactions defensively (list).
  /// Toggles off if the same emoji is selected again, otherwise upserts.
  /// 
  /// Returns true on success, false on failure.
  Future<bool> reactToMedia({
    required String mediaPostId,
    required String reaction, // e.g., '🔥', '❤️', '😂', '👀'
  }) async {
    if (!SupabaseGate.isEnabled) {
      return false;
    }

    try {
      final supabase = SupabaseGate.client;
      
      // Get current authenticated user - must be logged in
      final currentUser = AuthService.instance.currentUser;
      if (currentUser == null) {
        return false;
      }

      final authUserId = currentUser.id;
      
      // Check if user already has a reaction for this media post
      final existingResponse = await supabase
          .from('room_media_reactions')
          .select('reaction')
          .eq('media_post_id', mediaPostId)
          .eq('user_id', authUserId)
          .limit(2);

      final existingRows = (existingResponse as List);
      final existingEmoji =
          existingRows.isNotEmpty ? existingRows.first['reaction'] as String? : null;

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseChatRepository: current user reaction for $mediaPostId = $existingEmoji',
        );
      }

      // If there are duplicate rows, clean them up to enforce single reaction per user/post
      if (existingRows.length > 1) {
        await supabase
            .from('room_media_reactions')
            .delete()
            .eq('media_post_id', mediaPostId)
            .eq('user_id', authUserId);
      }

      // If user taps the same emoji again, remove reaction
      if (existingEmoji == reaction) {
        // Delete reaction
        await supabase
            .from('room_media_reactions')
            .delete()
            .eq('media_post_id', mediaPostId)
            .eq('user_id', authUserId);

        final counts = await _fetchReactionCounts(mediaPostId);
        if (kDebugMode) {
          debugPrint(
            '🟣 SupabaseChatRepository: aggregated reaction counts for $mediaPostId = $counts',
          );
        }

        return true;
      }

      // Upsert reaction (insert or update if exists with different emoji)
      final reactionData = {
        'media_post_id': mediaPostId,
        'user_id': authUserId,
        'reaction': reaction,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final upsertResponse = await supabase
          .from('room_media_reactions')
          .upsert(reactionData, onConflict: 'media_post_id,user_id')
          .select();

      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseChatRepository: upsert reaction result for $mediaPostId = ${(upsertResponse as List).length}',
        );
      }

      final counts = await _fetchReactionCounts(mediaPostId);
      if (kDebugMode) {
        debugPrint(
          '🟣 SupabaseChatRepository: aggregated reaction counts for $mediaPostId = $counts',
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to react to media: $e');
      }
      return false;
    }
  }

  Future<Map<String, int>> _fetchReactionCounts(String mediaPostId) async {
    if (!SupabaseGate.isEnabled) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('room_media_reactions')
          .select('reaction')
          .eq('media_post_id', mediaPostId);

      final counts = <String, int>{};
      for (final row in response as List) {
        final emoji = row['reaction'] as String?;
        if (emoji == null || emoji.isEmpty) continue;
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
      return counts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ SupabaseChatRepository: Failed to count reactions: $e');
      }
      return {};
    }
  }

  /// Fetch message counts for multiple rooms (aggregated).
  /// Returns a map of roomId -> message count.
  Future<Map<String, int>> fetchMessageCounts(List<String> roomIds) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('messages')
          .select('room_id, message_count:count()')
          .inFilter('room_id', roomIds);

      final counts = <String, int>{};
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row);
        final roomId = map['room_id'] as String?;
        if (roomId == null) continue;
        final count = (map['message_count'] as num?)?.toInt() ?? 0;
        counts[roomId] = count;
      }

      if (kDebugMode) {
        debugPrint(
          '✅ SupabaseChatRepository: fetched ${roomIds.length} roomIds, returned ${counts.length} counts',
        );
      }

      return counts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch message counts: $e');
      }
      return {};
    }
  }

  /// Fetch presence counts for multiple rooms.
  /// Falls back to empty map if no presence table is available.
  Future<Map<String, int>> fetchPresenceCounts(List<String> roomIds) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }
    if (kDebugMode) {
      debugPrint(
        '⚠️ SupabaseChatRepository: Presence table not available; returning empty counts',
      );
    }
    return {};
  }

  /// Fetch message counts for multiple rooms
  /// Returns a map of roomId -> message count
  Future<Map<String, int>> fetchMessageCountsForRooms(List<String> roomIds) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final Map<String, int> counts = {};

      // Initialize all roomIds with 0
      for (final roomId in roomIds) {
        counts[roomId] = 0;
      }

      // Query message counts grouped by room_id
      // Use OR filter: room_id.eq.room1,room_id.eq.room2,...
      final orFilter = roomIds.map((id) => 'room_id.eq.$id').join(',');
      final response = await supabase
          .from('messages')
          .select('room_id')
          .or(orFilter);

      // Count occurrences of each room_id
      for (final row in response) {
        final rowMap = Map<String, dynamic>.from(row);
        final roomId = rowMap['room_id'] as String?;
        if (roomId != null && counts.containsKey(roomId)) {
          counts[roomId] = (counts[roomId] ?? 0) + 1;
        }
      }

      if (kDebugMode) {
        debugPrint('✅ SupabaseChatRepository: Fetched message counts for ${counts.length} rooms');
      }

      return counts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch message counts: $e');
      }
      // Return empty map on error
      return {};
    }
  }

  /// Fetch message counts for multiple rooms since a given time
  /// Returns a map of roomId -> message count
  Future<Map<String, int>> fetchMessageCountsForRoomsSince(
    List<String> roomIds,
    DateTime since,
  ) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final Map<String, int> counts = {};

      for (final roomId in roomIds) {
        counts[roomId] = 0;
      }

      final orFilter = roomIds.map((id) => 'room_id.eq.$id').join(',');
      final response = await supabase
          .from('messages')
          .select('room_id,created_at')
          .or(orFilter)
          .gte('created_at', since.toIso8601String());

      for (final row in response) {
        final rowMap = Map<String, dynamic>.from(row);
        final roomId = rowMap['room_id'] as String?;
        if (roomId != null && counts.containsKey(roomId)) {
          counts[roomId] = (counts[roomId] ?? 0) + 1;
        }
      }

      return counts;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch counts since: $e');
      }
      return {};
    }
  }

  /// Fetch message count + last message timestamp per room.
  Future<Map<String, RoomMessageStats>> fetchRoomMessageStats(
    List<String> roomIds,
  ) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('messages')
          .select('room_id, message_count:count(), last_message_at:max(created_at)')
          .inFilter('room_id', roomIds);

      final stats = <String, RoomMessageStats>{};
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row);
        final roomId = map['room_id'] as String?;
        if (roomId == null) continue;
        final count = (map['message_count'] as num?)?.toInt() ?? 0;
        final lastMessageRaw = map['last_message_at'] as String?;
        stats[roomId] = RoomMessageStats(
          messageCount: count,
          lastMessageAt:
              lastMessageRaw == null ? null : DateTime.parse(lastMessageRaw),
        );
      }

      if (kDebugMode) {
        debugPrint(
          '✅ SupabaseChatRepository: Fetched message stats for ${stats.length} rooms',
        );
      }

      return stats;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch message stats: $e');
      }
      return {};
    }
  }

  /// Fetch activity stats for rooms within a time window.
  Future<Map<String, RoomActivityStats>> fetchRoomActivityStats(
    List<String> roomIds,
    DateTime since,
  ) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final sinceIso = since.toIso8601String();

      final messageResponse = await supabase
          .from('messages')
          .select('room_id, message_count:count(), last_message_at:max(created_at)')
          .inFilter('room_id', roomIds)
          .gte('created_at', sinceIso);

      final mediaResponse = await supabase
          .from('room_media_posts')
          .select('room_id, media_count:count(), last_media_at:max(created_at)')
          .inFilter('room_id', roomIds)
          .gte('created_at', sinceIso);

      final stats = <String, RoomActivityStats>{};
      for (final row in messageResponse as List) {
        final map = Map<String, dynamic>.from(row);
        final roomId = map['room_id'] as String?;
        if (roomId == null) continue;
        final count = (map['message_count'] as num?)?.toInt() ?? 0;
        final lastRaw = map['last_message_at'] as String?;
        final existing = stats[roomId];
        stats[roomId] = (existing ?? const RoomActivityStats()).copyWith(
          messageCountWindow: count,
          lastMessageAt: lastRaw == null ? null : DateTime.parse(lastRaw),
        );
      }

      for (final row in mediaResponse as List) {
        final map = Map<String, dynamic>.from(row);
        final roomId = map['room_id'] as String?;
        if (roomId == null) continue;
        final count = (map['media_count'] as num?)?.toInt() ?? 0;
        final lastRaw = map['last_media_at'] as String?;
        final existing = stats[roomId];
        stats[roomId] = (existing ?? const RoomActivityStats()).copyWith(
          mediaCountWindow: count,
          lastMediaAt: lastRaw == null ? null : DateTime.parse(lastRaw),
        );
      }

      return stats.map((roomId, value) => MapEntry(roomId, value.withComputed()));
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch activity stats: $e');
      }
      return {};
    }
  }

  /// Fetch latest media_url per room from room_media_posts.
  Future<Map<String, String?>> fetchRoomLatestMedia(List<String> roomIds) async {
    if (!SupabaseGate.isEnabled || roomIds.isEmpty) {
      return {};
    }

    try {
      final supabase = SupabaseGate.client;
      final response = await supabase
          .from('room_media_posts')
          .select('room_id, media_url, created_at')
          .inFilter('room_id', roomIds)
          .order('created_at', ascending: false);

      final latestByRoom = <String, String?>{};
      for (final row in response as List) {
        final map = Map<String, dynamic>.from(row);
        final roomId = map['room_id'] as String?;
        if (roomId == null) continue;
        if (latestByRoom.containsKey(roomId)) continue;
        latestByRoom[roomId] = map['media_url'] as String?;
      }

      return latestByRoom;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ SupabaseChatRepository: Failed to fetch latest media: $e');
      }
      return {};
    }
  }

  /// Dispose all resources
  void dispose() {
    // Leave all presence channels
    for (final roomId in _presenceChannels.keys.toList()) {
      leaveRoomPresence(roomId);
    }
    
    for (final roomId in _realtimeChannels.keys.toList()) {
      _unsubscribeFromRealtime(roomId);
    }
    for (final controller in _streamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    for (final controller in _presenceCountControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    for (final controller in _presenceRosterControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _streamControllers.clear();
    _messagesCache.clear();
  }
}

/// Internal helper class for tracking user activity
class _UserActivity {
  final String userId;
  final String userName;
  final String? userAvatar;
  final String roomId;
  DateTime lastSeenAt;
  int messageCount = 0;
  int mediaCount = 0;

  _UserActivity({
    required this.userId,
    required this.userName,
    this.userAvatar,
    required this.roomId,
    required this.lastSeenAt,
  });
}

class RoomMessageStats {
  final int messageCount;
  final DateTime? lastMessageAt;

  const RoomMessageStats({
    required this.messageCount,
    required this.lastMessageAt,
  });
}

class RoomActivityStats {
  final DateTime? lastMessageAt;
  final DateTime? lastMediaAt;
  final int messageCountWindow;
  final int mediaCountWindow;
  final DateTime? lastActivityAt;
  final int activityCount;

  const RoomActivityStats({
    this.lastMessageAt,
    this.lastMediaAt,
    this.messageCountWindow = 0,
    this.mediaCountWindow = 0,
    this.lastActivityAt,
    this.activityCount = 0,
  });

  RoomActivityStats copyWith({
    DateTime? lastMessageAt,
    DateTime? lastMediaAt,
    int? messageCountWindow,
    int? mediaCountWindow,
  }) {
    return RoomActivityStats(
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      lastMediaAt: lastMediaAt ?? this.lastMediaAt,
      messageCountWindow: messageCountWindow ?? this.messageCountWindow,
      mediaCountWindow: mediaCountWindow ?? this.mediaCountWindow,
      lastActivityAt: lastActivityAt,
      activityCount: activityCount,
    );
  }

  RoomActivityStats withComputed() {
    final last = _maxDate(lastMessageAt, lastMediaAt);
    final count = messageCountWindow + mediaCountWindow;
    return RoomActivityStats(
      lastMessageAt: lastMessageAt,
      lastMediaAt: lastMediaAt,
      messageCountWindow: messageCountWindow,
      mediaCountWindow: mediaCountWindow,
      lastActivityAt: last,
      activityCount: count,
    );
  }

  static DateTime? _maxDate(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }
}

