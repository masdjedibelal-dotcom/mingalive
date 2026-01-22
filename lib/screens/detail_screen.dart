import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';
import '../models/place.dart';
import '../models/chat_message.dart';
import '../widgets/place_image.dart';
import '../widgets/add_to_collab_sheet.dart';
import '../services/auth_service.dart';
import '../services/chat_repository.dart';
import '../services/supabase_chat_repository.dart';
import '../services/supabase_gate.dart';
import '../data/place_repository.dart';
import 'main_shell.dart';
import 'creator_profile_screen.dart';

/// Detail view for a single place with image, rating, and live chat preview
/// 
/// Can accept either a Place object directly or a placeId to load from Supabase.
/// If placeId is provided, Place will be loaded via FutureBuilder.
class DetailScreen extends StatefulWidget {
  final Place? place;
  final String? placeId;
  final bool openChatOnLoad;
  final void Function(String placeId) openPlaceChat;

  const DetailScreen({
    super.key,
    this.place,
    this.placeId,
    required this.openPlaceChat,
    this.openChatOnLoad = false,
  }) : assert(
          place != null || placeId != null,
          'Either place or placeId must be provided',
        );

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _chatScrollController = ScrollController(); // Separate controller for chat list
  final GlobalKey _chatSectionKey = GlobalKey();
  final PlaceRepository _placeRepository = PlaceRepository();
  bool _isFavorite = false;
  bool _isFavoriteLoading = false;
  String? _favoritePlaceId;
  
  // Use Supabase repository if enabled, otherwise fallback to local repository
  late final dynamic _chatRepository;
  StreamSubscription<List<ChatMessage>>? _messagesSubscription;
      StreamSubscription<int>? _presenceCountSubscription;
      List<ChatMessage> _messages = [];
      int _liveCount = 0; // Presence-based live count
      bool _hasScrolledToChat = false;
      bool _isLoadingMessages = true; // Start with loading state
      bool _hasReceivedFirstBatch = false;

      // Current place (either from widget or loaded)
      Place? _currentPlace;
  
  @override
  void initState() {
    super.initState();
    
    // Set current place from widget if available
    if (widget.place != null) {
      _currentPlace = widget.place;
    }
    
    // Choose repository based on Supabase availability
    if (SupabaseGate.isEnabled) {
      _chatRepository = SupabaseChatRepository();
    } else {
      _chatRepository = ChatRepository();
    }
    
    // Only initialize chat if we have a place
    if (_currentPlace != null) {
      _initializeChat();
      _loadFavoriteStatus(_currentPlace!);
    }
  }


  /// Initialize chat for a specific place
  void _initializeChatForPlace(Place place) {
    _currentPlace = place;
    _initializeChat();
    _loadFavoriteStatus(place);
  }

  /// Show dialog to add place to favorite list
  Future<void> _showAddToFavoritesDialog() async {
    final place = _currentPlace;
    if (place == null) return;
    await showAddToCollabSheet(context: context, place: place);
  }

  Future<void> _loadFavoriteStatus(Place place) async {
    final currentUser = AuthService.instance.currentUser;
    if (!SupabaseGate.isEnabled || currentUser == null) {
      if (mounted) {
        setState(() {
          _isFavorite = false;
          _favoritePlaceId = place.id;
        });
      }
      return;
    }
    if (_favoritePlaceId == place.id) {
      return;
    }
    setState(() {
      _isFavoriteLoading = true;
      _favoritePlaceId = place.id;
    });
    final isFavorite = await _placeRepository.isFavorite(
      placeId: place.id,
      userId: currentUser.id,
    );
    if (!mounted) return;
    setState(() {
      _isFavorite = isFavorite;
      _isFavoriteLoading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    final place = _currentPlace;
    if (place == null) return;
    final currentUser = AuthService.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Bitte einloggen, um Orte zu speichern.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (!SupabaseGate.isEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Favoriten sind nur mit Supabase verfügbar.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _isFavoriteLoading = true;
    });

    try {
      if (_isFavorite) {
        await _placeRepository.removeFavorite(
                                    placeId: place.id,
          userId: currentUser.id,
        );
      } else {
        await _placeRepository.addFavorite(
          placeId: place.id,
          userId: currentUser.id,
        );
      }
      if (!mounted) return;
      setState(() {
        _isFavorite = !_isFavorite;
      });
    } catch (_) {
      if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Konnte Favorit nicht speichern.'),
          duration: Duration(seconds: 2),
                                      ),
                                    );
    } finally {
      if (!mounted) return;
      setState(() {
        _isFavoriteLoading = false;
      });
    }
  }

  Future<void> _initializeChat() async {
    final place = _currentPlace;
    if (place == null) return;
    
    final roomId = place.chatRoomId;
    
    // If using Supabase, ensure room exists
    if (SupabaseGate.isEnabled) {
      try {
        final supabaseRepo = _chatRepository as SupabaseChatRepository;
        // Ensure room exists (use place.id as placeId)
        await supabaseRepo.ensureRoomExists(roomId, place.id);
      } catch (e) {
        // Continue even if room creation fails
        if (kDebugMode) {
          debugPrint('⚠️ DetailScreen: Failed to ensure room: $e');
        }
      }
    }
    
    // Subscribe to messages stream for this room
    _messagesSubscription = _chatRepository.watchMessages(roomId).listen((messages) {
      if (mounted) {
        final previousCount = _messages.length;
        final isFirstBatch = !_hasReceivedFirstBatch;
        
        setState(() {
          _messages = messages;
          // Mark first batch as received when we get messages
          if (isFirstBatch && messages.isNotEmpty) {
            _hasReceivedFirstBatch = true;
            _isLoadingMessages = false;
          } else if (isFirstBatch && messages.isEmpty) {
            // If first batch is empty, still mark as received to hide loading
            _hasReceivedFirstBatch = true;
            _isLoadingMessages = false;
          }
        });
        
        // Auto-scroll logic
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          
          // If this is the first batch and openChatOnLoad is true, scroll to chat section
          if (isFirstBatch && widget.openChatOnLoad) {
            _scrollToChatAndFocus();
            
            // Also scroll chat list to bottom after messages are loaded
            if (_chatScrollController.hasClients) {
              _chatScrollController.animateTo(
                _chatScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          } else {
            // Auto-scroll chat list to bottom if:
            // 1. First batch arrived (initial load) - always scroll
            // 2. New message arrived AND user is already near bottom (within 120px)
            final shouldAutoScroll = isFirstBatch || 
                (messages.length > previousCount && _isNearBottom());
            
            if (shouldAutoScroll && _chatScrollController.hasClients) {
              _chatScrollController.animateTo(
                _chatScrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
          }
        });
      }
    });

    // If openChatOnLoad is true, scroll to chat after first frame
    if (widget.openChatOnLoad) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToChatAndFocus();
      });
    }
    
    // Join presence if Supabase is enabled and user is logged in
    if (SupabaseGate.isEnabled) {
      final currentUser = AuthService.instance.currentUser;
      if (currentUser != null) {
        final supabaseRepo = _chatRepository as SupabaseChatRepository;
        // Join presence (user actively participates)
        supabaseRepo.joinRoomPresence(
          roomId,
          userId: currentUser.id,
          userName: currentUser.name,
        );
      }
      
      // Subscribe to presence count updates (works even if not joined)
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      _presenceCountSubscription = supabaseRepo.watchPresenceCount(roomId).listen((count) {
        if (mounted) {
          setState(() {
            _liveCount = count;
          });
        }
      });
    } else {
      // Fallback to mock liveCount from place
      if (_currentPlace != null) {
        _liveCount = _currentPlace!.liveCount;
      }
    }
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _presenceCountSubscription?.cancel();
    
    // Leave presence if Supabase is enabled and user was logged in
    if (SupabaseGate.isEnabled && _chatRepository is SupabaseChatRepository && _currentPlace != null) {
      final supabaseRepo = _chatRepository as SupabaseChatRepository;
      final currentUser = AuthService.instance.currentUser;
      // Only leave if user was actually joined (logged in)
      if (currentUser != null) {
        supabaseRepo.leaveRoomPresence(_currentPlace!.chatRoomId);
      }
      supabaseRepo.disposeRoom(_currentPlace!.chatRoomId);
    }
    
    _scrollController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  /// Check if user is near the bottom of the chat list (within 120px)
  bool _isNearBottom() {
    if (!_chatScrollController.hasClients) return false;
    final position = _chatScrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;
    return (maxScroll - currentScroll) < 120;
  }

  void _scrollToChatAndFocus() {
    if (_hasScrolledToChat) return;
    _hasScrolledToChat = true;

    // Wait for the chat section to be rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final chatContext = _chatSectionKey.currentContext;
      if (chatContext != null) {
        // Use Scrollable.ensureVisible for reliable scrolling
        Scrollable.ensureVisible(
          chatContext,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
          alignment: 0.1, // Position chat section near top of viewport
        ).then((_) {
          if (!mounted) return;
          // Chat preview is read-only, no focus needed
        });
      }
    });
  }


  @override
  Widget build(BuildContext context) {
    // If placeId is provided, load place via FutureBuilder
    if (widget.placeId != null && widget.place == null) {
      return Scaffold(
        backgroundColor: MingaTheme.background,
        body: FutureBuilder<Place?>(
          future: _placeRepository.fetchById(widget.placeId!),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(
                child: CircularProgressIndicator(
                  color: MingaTheme.accentGreen,
                ),
              );
            }
            
            if (snapshot.hasError || snapshot.data == null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: MingaTheme.textSubtle,
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Ort nicht gefunden',
                      style: MingaTheme.titleSmall,
                    ),
                    SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text('Zurück'),
                    ),
                  ],
                ),
              );
            }
            
            // Rebuild with loaded place
            final loadedPlace = snapshot.data!;
            // Initialize chat if not already initialized
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _currentPlace?.id != loadedPlace.id) {
                // Update current place reference and initialize chat
                _initializeChatForPlace(loadedPlace);
              }
            });
            return _buildDetailContent(loadedPlace);
          },
        ),
      );
    }
    
    // Use provided place directly
    if (_currentPlace != null) {
      return _buildDetailContent(_currentPlace!);
    }
    
    // Fallback (should not happen due to assert)
    return Scaffold(
      backgroundColor: MingaTheme.background,
      body: Center(
        child: Text('Kein Ort verfügbar'),
      ),
    );
  }

  Widget _buildDetailContent(Place place) {
    return Scaffold(
      backgroundColor: MingaTheme.background,
      body: Stack(
        children: [
          // Scrollbarer Inhalt
          CustomScrollView(
            controller: _scrollController,
            slivers: [
                  // Header-Bild
                  SliverAppBar(
                    expandedHeight: 300,
                    pinned: false,
                    backgroundColor: MingaTheme.background,
                    leading: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: MingaTheme.darkOverlay,
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: Icon(Icons.arrow_back,
                            color: MingaTheme.textPrimary),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    actions: [
                      // Save place button
                      Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: MingaTheme.darkOverlay,
                          shape: BoxShape.circle,
                          border: Border.all(color: MingaTheme.borderStrong),
                        ),
                        child: IconButton(
                          onPressed: _isFavoriteLoading ? null : _toggleFavorite,
                          icon: Icon(
                            _isFavorite ? Icons.favorite : Icons.favorite_border,
                            color: MingaTheme.textPrimary,
                            size: 16,
                          ),
                          tooltip: _isFavorite ? 'Gespeichert' : 'Speichern',
                        ),
                      ),
                      // Add to collab button
                      Container(
                        margin: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: MingaTheme.darkOverlay,
                          shape: BoxShape.circle,
                          border: Border.all(color: MingaTheme.borderStrong),
                        ),
                        child: IconButton(
                          onPressed: _showAddToFavoritesDialog,
                          icon: Icon(Icons.add,
                              color: MingaTheme.textPrimary, size: 16),
                          tooltip: 'Zu Collab hinzufügen',
                        ),
                      ),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: PlaceImage(
                        imageUrl: place.imageUrl,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              // Name und Bewertung
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderTitle(place),
                      if (place.isLive) ...[
                        SizedBox(height: 12),
                        _buildHeaderBadges(place),
                      ],
                      // Info card with extended fields (address, status, opening hours)
                      if (place.address != null || place.status != null || place.openingHoursJson != null) ...[
                        SizedBox(height: 24),
                        _buildInfoCard(place),
                      ],
                      // Actions section (Website, Instagram, Route, Call)
                      if (place.websiteUrlOrWebsite != null || place.instagramUrlOrInstagram != null || place.mapsUrl != null || place.phone != null) ...[
                        SizedBox(height: 24),
                        _buildActionsSection(place),
                      ],
                    ],
                  ),
                ),
              ),
              // Live-Chat Bereich
              SliverToBoxAdapter(
                child: Padding(
                  key: _chatSectionKey,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Live-Chat', style: MingaTheme.titleSmall),
                      SizedBox(height: 16),
                      GlassSurface(
                        radius: MingaTheme.cardRadius,
                        blurSigma: 18,
                        overlayColor: MingaTheme.glassOverlayXSoft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 400),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: MingaTheme.accentGreenSoft,
                                        borderRadius: BorderRadius.circular(
                                          MingaTheme.chipRadius,
                                        ),
                                        border: Border.all(
                                          color: MingaTheme.accentGreen,
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'LIVE',
                                            style: MingaTheme.label.copyWith(
                                              color: MingaTheme.accentGreen,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    if (_liveCount > 0)
                                      Text(
                                        '• $_liveCount online',
                                        style: MingaTheme.textMuted,
                                      ),
                                    SizedBox(width: 8),
                                    Text(
                                      '• ${_messages.length} ${_messages.length == 1 ? 'Nachricht' : 'Nachrichten'}',
                                      style: MingaTheme.textMuted,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _isLoadingMessages &&
                                        !_hasReceivedFirstBatch
                                    ? Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Center(
                                          child: CircularProgressIndicator(
                                            color: MingaTheme.accentGreen,
                                          ),
                                        ),
                                      )
                                    : _messages.isEmpty
                                        ? Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Center(
                                              child: Text(
                                                "Noch keine Nachrichten",
                                                style: MingaTheme.textMuted,
                                              ),
                                            ),
                                          )
                                        : ListView.builder(
                                            controller: _chatScrollController,
                                            shrinkWrap: true,
                                            padding: const EdgeInsets.fromLTRB(
                                              16,
                                              16,
                                              16,
                                              16,
                                            ),
                                            itemCount: _messages.length > 10
                                                ? 10
                                                : _messages.length,
                                            itemBuilder: (context, index) {
                                              final reversedIndex =
                                                  _messages.length - 1 - index;
                                              final chatMessage =
                                                  _messages[reversedIndex];
                                              return _buildChatMessage(
                                                userId: chatMessage.userId,
                                                username: chatMessage.userName,
                                                message: chatMessage.text,
                                                photoUrl: chatMessage.userAvatar,
                                                isFromCurrentUser:
                                                    chatMessage.isMine,
                                              );
                                            },
                                          ),
                              ),
                              if (place.socialEnabled)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: TextButton(
                                      onPressed: () =>
                                          MainShell.of(context)
                                              ?.openPlaceChat(place.id),
                                      style: TextButton.styleFrom(
                                        foregroundColor: MingaTheme.accentGreen,
                                      ),
                                      child: Text('Chat öffnen'),
                                    ),
                                  ),
                                )
                              else
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    16,
                                  ),
                                  child: Text(
                                    'Live-Chat nur für stark frequentierte Spots verfügbar.',
                                    style: MingaTheme.bodySmall,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Build info card with extended fields (address, status, opening hours, buttons)
  Widget _buildInfoCard(Place place) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      radius: MingaTheme.cardRadius,
      blurSigma: 18,
      overlayColor: MingaTheme.glassOverlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Address row (tappable if lat/lng available)
          if (place.address != null && place.address!.isNotEmpty) ...[
            GestureDetector(
              onTap: place.mapsUrl != null
                  ? () => _openMapsUrl(place.mapsUrl!)
                  : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on,
                    size: 20,
                    color: place.lat != null && place.lng != null
                        ? MingaTheme.accentGreen
                        : MingaTheme.textSubtle,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      place.address!,
                      style: MingaTheme.textMuted.copyWith(
                        fontSize: 14,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (place.lat != null && place.lng != null)
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: MingaTheme.accentGreenBorderStrong,
                    ),
                ],
              ),
            ),
            SizedBox(height: 16),
          ],
          // Status row
          if (place.status != null && place.status!.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: place.status!.toLowerCase() == 'open' || place.status!.toLowerCase() == 'geöffnet'
                        ? MingaTheme.successGreen
                        : MingaTheme.dangerRed,
                    shape: BoxShape.circle,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  place.status!.toLowerCase() == 'open' || place.status!.toLowerCase() == 'geöffnet'
                      ? 'Geöffnet'
                      : place.status!,
                  style: MingaTheme.textMuted.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
          ],
          // Opening Hours (collapsible)
          if (place.openingHoursJson != null && place.openingHoursJson!.isNotEmpty) ...[
            _buildOpeningHours(place.openingHoursJson!),
            SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderMeta(Place place) {
    final parts = <String>[];
    if (parts.isEmpty) {
      return SizedBox.shrink();
    }
    return Text(
      parts.join(' • '),
      style: MingaTheme.textMuted,
    );
  }

  Widget _buildHeaderTitle(Place place) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          place.name,
          style: MingaTheme.displayLarge,
        ),
        SizedBox(height: 8),
        _buildHeaderMeta(place),
      ],
    );
  }

  Widget _buildHeaderBadges(Place place) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _buildBadge(
          label: place.liveCount > 0
              ? 'LIVE · ${place.liveCount}'
              : 'LIVE',
          color: MingaTheme.successGreen,
          icon: Icons.wifi_tethering,
        ),
        if (place.status != null && place.status!.trim().isNotEmpty)
          _buildBadge(
            label: place.status!.toLowerCase() == 'open' ||
                    place.status!.toLowerCase() == 'geöffnet'
                ? 'Geöffnet'
                : place.status!.trim(),
            color: place.status!.toLowerCase() == 'open' ||
                    place.status!.toLowerCase() == 'geöffnet'
                ? MingaTheme.successGreen
                : MingaTheme.dangerRed,
            icon: Icons.access_time,
            isMuted: true,
          ),
      ],
    );
  }

  Widget _buildBadge({
    required String label,
    required Color color,
    required IconData icon,
    bool isMuted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMuted ? MingaTheme.glassOverlay : color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(MingaTheme.chipRadius),
        border: Border.all(
          color: isMuted ? MingaTheme.borderStrong : color.withOpacity(0.7),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: isMuted ? MingaTheme.textSecondary : color,
          ),
          SizedBox(width: 6),
          Text(
            label,
            style: MingaTheme.label.copyWith(
              color: isMuted ? MingaTheme.textSecondary : color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  /// Build opening hours from Map (collapsible section)
  Widget _buildOpeningHours(Map<String, dynamic> openingHoursJson) {
    // Check if weekday_text exists (Google Places format)
    final weekdayText = openingHoursJson['weekday_text'] as List?;
    
    if (weekdayText == null || weekdayText.isEmpty) {
      // If no weekday_text, try to render other format or hide
      return SizedBox.shrink();
    }
    
    return _OpeningHoursSection(weekdayText: weekdayText);
  }

  /// Open website URL
  Future<void> _openWebsite(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konnte Website nicht öffnen: $url'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Call phone number
  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konnte Telefonnummer nicht anrufen: $phone'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Build actions section with chips/buttons for Website, Instagram, Route, Call
  Widget _buildActionsSection(Place place) {
    final actions = <Widget>[];
    
    // Website chip
    if (place.websiteUrlOrWebsite != null && place.websiteUrlOrWebsite!.isNotEmpty) {
      actions.add(
        _buildActionChip(
          icon: Icons.language,
          label: 'Website',
          onTap: () => _openWebsite(place.websiteUrlOrWebsite!),
        ),
      );
    }
    
    // Instagram chip
    if (place.instagramUrlOrInstagram != null && place.instagramUrlOrInstagram!.isNotEmpty) {
      actions.add(
        _buildActionChip(
          icon: Icons.camera_alt,
          label: 'Instagram',
          onTap: () => _openInstagram(place.instagramUrlOrInstagram!),
        ),
      );
    }
    
    // Route chip (Google Maps)
    if (place.mapsUrl != null) {
      actions.add(
        _buildActionChip(
          icon: Icons.directions,
          label: 'Route',
          onTap: () => _openMapsUrl(place.mapsUrl!),
        ),
      );
    }
    
    // Call chip
    if (place.phone != null && place.phone!.isNotEmpty) {
      actions.add(
        _buildActionChip(
          icon: Icons.phone,
          label: 'Anrufen',
          onTap: () => _callPhone(place.phone!),
        ),
      );
    }
    
    if (actions.isEmpty) {
      return SizedBox.shrink();
    }
    
    return GlassCard(
      padding: const EdgeInsets.all(20),
      radius: 20,
      blurSigma: 18,
      overlayColor: MingaTheme.glassOverlay,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Infos',
            style: MingaTheme.titleMedium,
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: actions,
          ),
        ],
      ),
    );
  }
  
  /// Build a single action chip
  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: MingaTheme.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(MingaTheme.radiusMd),
        onTap: onTap,
        child: GlassSurface(
          radius: MingaTheme.radiusMd,
          blurSigma: 16,
          overlayColor: MingaTheme.glassOverlay,
          borderColor: MingaTheme.accentGreenBorder,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassSurface(
                  radius: 10,
                  blurSigma: 12,
                  overlayColor: MingaTheme.accentGreenSoft,
                  borderColor: MingaTheme.accentGreenBorder,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      icon,
                      size: 16,
                      color: MingaTheme.accentGreen,
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  label,
                  style: MingaTheme.body.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Open maps with URL
  Future<void> _openMapsUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konnte Karte nicht öffnen'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
  
  /// Open Instagram URL
  Future<void> _openInstagram(String instagram) async {
    // Handle both Instagram handle (@username) and full URL
    String url;
    if (instagram.startsWith('http')) {
      url = instagram;
    } else if (instagram.startsWith('@')) {
      url = 'https://www.instagram.com/${instagram.substring(1)}/';
    } else {
      url = 'https://www.instagram.com/$instagram/';
    }
    
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Konnte Instagram nicht öffnen: $instagram'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }


  Widget _buildChatMessage({
    required String userId,
    required String username,
    required String message,
    String? photoUrl,
    bool isFromCurrentUser = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isFromCurrentUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isFromCurrentUser) ...[
            // Avatar for other users
            GestureDetector(
              onTap: () => _openCreatorProfile(userId),
              child: _buildAvatar(photoUrl, username),
            ),
            SizedBox(width: 12),
          ],
          // Nachricht
          Flexible(
            child: GlassSurface(
              radius: 16,
              blurSigma: 16,
              overlayColor: isFromCurrentUser
                  ? MingaTheme.accentGreenSoft
                  : MingaTheme.glassOverlay,
              borderColor: MingaTheme.borderSubtle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => _openCreatorProfile(userId),
                      child: Text(
                        username,
                        style: MingaTheme.label.copyWith(
                          color: isFromCurrentUser
                              ? MingaTheme.accentGreen
                              : MingaTheme.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      message,
                      style: MingaTheme.body.copyWith(
                        color: MingaTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (isFromCurrentUser) ...[
            SizedBox(width: 12),
            // Avatar for current user
            _buildAvatar(photoUrl, username),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(String? photoUrl, String username) {
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultAvatar(username);
          },
        ),
      );
    }
    return _buildDefaultAvatar(username);
  }

  Widget _buildDefaultAvatar(String username) {
    // Extract avatar emoji or use default
    final avatarEmojis = ['👤', '🍜', '🌟', '🔥', '💚', '👍', '🍺', '☕', '🎨'];
    final avatarIndex = username.hashCode % avatarEmojis.length;
    final avatar = avatarEmojis[avatarIndex.abs()];

    return GlassSurface(
      radius: 999,
      blurSigma: 16,
      overlayColor: MingaTheme.glassOverlay,
      child: SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: Text(
            avatar,
            style: MingaTheme.body.copyWith(fontSize: 20),
          ),
        ),
      ),
    );
  }

  void _openCreatorProfile(String userId) {
    if (userId.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreatorProfileScreen(userId: userId),
      ),
    );
  }
}

/// Collapsible opening hours section
class _OpeningHoursSection extends StatefulWidget {
  final List<dynamic> weekdayText;

  const _OpeningHoursSection({required this.weekdayText});

  @override
  State<_OpeningHoursSection> createState() => _OpeningHoursSectionState();
}

class _OpeningHoursSectionState extends State<_OpeningHoursSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
          },
          child: Row(
            children: [
              Icon(
                Icons.access_time,
                size: 18,
                color: MingaTheme.textSubtle,
              ),
              SizedBox(width: 8),
              Text(
                'Öffnungszeiten',
                style: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(
                _isExpanded ? Icons.expand_less : Icons.expand_more,
                size: 20,
                color: MingaTheme.textSubtle,
              ),
            ],
          ),
        ),
        if (_isExpanded) ...[
          SizedBox(height: 8),
          ...widget.weekdayText.map((text) {
            return Padding(
              padding: const EdgeInsets.only(left: 26, bottom: 4),
              child: Text(
                text.toString(),
                style: MingaTheme.bodySmall.copyWith(
                  color: MingaTheme.textSecondary,
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
