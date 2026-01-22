import 'dart:async';
import '../models/chat_message.dart';

/// In-memory chat repository with stream support
class ChatRepository {
  static final ChatRepository _instance = ChatRepository._internal();
  factory ChatRepository() => _instance;
  ChatRepository._internal();

  // In-memory storage by roomId
  final Map<String, List<ChatMessage>> _messagesByRoom = {};
  
  // Stream controllers by roomId
  final Map<String, StreamController<List<ChatMessage>>> _streamControllers = {};

  /// Seed mock messages for a room if not already seeded
  void _seedRoomIfNeeded(String roomId) {
    if (_messagesByRoom.containsKey(roomId)) {
      return; // Already seeded
    }

    final mockMessages = <ChatMessage>[
      ChatMessage(
        id: '${roomId}_msg_1',
        roomId: roomId,
        userId: 'user_mock_1',
        userName: 'MünchenFan',
        userAvatar: null,
        text: 'Wartezeit ca. 10 Minuten, aber es lohnt sich!',
        createdAt: DateTime.now().subtract(const Duration(minutes: 15)),
        isMine: false,
      ),
      ChatMessage(
        id: '${roomId}_msg_2',
        roomId: roomId,
        userId: 'user_mock_2',
        userName: 'FoodieMax',
        userAvatar: null,
        text: 'Stimmung ist top hier! 🎉',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
        isMine: false,
      ),
      ChatMessage(
        id: '${roomId}_msg_3',
        roomId: roomId,
        userId: 'user_mock_3',
        userName: 'Sarah_M',
        userAvatar: null,
        text: 'Kann jemand die Speisekarte empfehlen?',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        isMine: false,
      ),
    ];

    _messagesByRoom[roomId] = mockMessages;
    
    // Initialize stream controller for this room
    if (!_streamControllers.containsKey(roomId)) {
      _streamControllers[roomId] = StreamController<List<ChatMessage>>.broadcast();
      _streamControllers[roomId]!.add(mockMessages);
    }
  }

  /// Get messages for a room (sync)
  List<ChatMessage> getMessages(String roomId) {
    _seedRoomIfNeeded(roomId);
    return List.unmodifiable(_messagesByRoom[roomId] ?? []);
  }

  /// Send a message to a room
  void sendMessage(String roomId, ChatMessage message) {
    _seedRoomIfNeeded(roomId);
    
    final messages = _messagesByRoom[roomId] ?? [];
    messages.add(message);
    _messagesByRoom[roomId] = messages;
    
    // Notify stream listeners
    final controller = _streamControllers[roomId];
    if (controller != null && !controller.isClosed) {
      controller.add(List.unmodifiable(messages));
    } else {
      // Create new controller if needed
      _streamControllers[roomId] = StreamController<List<ChatMessage>>.broadcast();
      _streamControllers[roomId]!.add(List.unmodifiable(messages));
    }
  }

  /// Watch messages for a room (reactive stream)
  Stream<List<ChatMessage>> watchMessages(String roomId) {
    _seedRoomIfNeeded(roomId);
    
    // Create stream controller if it doesn't exist
    if (!_streamControllers.containsKey(roomId)) {
      _streamControllers[roomId] = StreamController<List<ChatMessage>>.broadcast();
      _streamControllers[roomId]!.add(List.unmodifiable(_messagesByRoom[roomId] ?? []));
    }
    
    return _streamControllers[roomId]!.stream;
  }

  /// Dispose stream controllers (call this when done with repository)
  void dispose() {
    for (final controller in _streamControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _streamControllers.clear();
    _messagesByRoom.clear();
  }
}


