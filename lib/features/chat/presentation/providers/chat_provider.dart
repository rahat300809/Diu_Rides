import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:diu_ride/features/auth/presentation/providers/auth_provider.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/repositories/chat_repository.dart';
import 'package:diu_ride/features/chat/data/repositories/shared_sync_chat_repository.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return SharedSyncChatRepository();
});

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isConnected;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isConnected = true,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isConnected,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isConnected: isConnected ?? this.isConnected,
    );
  }
}

class ChatNotifier extends StateNotifier<ChatState> {
  final ChatRepository _repository;
  final Ref _ref;
  final String _rideId;

  ChatNotifier(this._repository, this._ref, this._rideId) : super(const ChatState()) {
    Future.microtask(() {
      loadMessages();
      _subscribe();
    });
  }

  void loadMessages() async {
    state = state.copyWith(isLoading: true);
    final msgs = await _repository.getMessages(_rideId);
    final currentUserId = _ref.read(authNotifierProvider).user?.id ?? 'current_user';
    final adjusted = msgs.map((m) => m.senderId == currentUserId ? ChatMessage(
      id: m.id,
      rideId: m.rideId,
      senderId: m.senderId,
      senderName: m.senderName,
      text: m.text,
      timestamp: m.timestamp,
      isMe: true,
      isRead: m.isRead,
      isLocationShare: m.isLocationShare,
      sharedLat: m.sharedLat,
      sharedLng: m.sharedLng,
    ) : ChatMessage(
      id: m.id,
      rideId: m.rideId,
      senderId: m.senderId,
      senderName: m.senderName,
      text: m.text,
      timestamp: m.timestamp,
      isMe: false,
      isRead: m.isRead,
      isLocationShare: m.isLocationShare,
      sharedLat: m.sharedLat,
      sharedLng: m.sharedLng,
    )).toList();

    state = state.copyWith(isLoading: false, messages: adjusted);
  }

  void _subscribe() {
    _repository.subscribeToMessages(_rideId).listen((newMsg) {
      final currentUserId = _ref.read(authNotifierProvider).user?.id ?? 'current_user';
      final formatted = ChatMessage(
        id: newMsg.id,
        rideId: newMsg.rideId,
        senderId: newMsg.senderId,
        senderName: newMsg.senderName,
        text: newMsg.text,
        timestamp: newMsg.timestamp,
        isMe: newMsg.senderId == currentUserId,
        isRead: newMsg.isRead,
        isLocationShare: newMsg.isLocationShare,
        sharedLat: newMsg.sharedLat,
        sharedLng: newMsg.sharedLng,
      );

      if (!state.messages.any((m) => m.id == formatted.id)) {
        state = state.copyWith(messages: [...state.messages, formatted]);
      }
    });
  }

  Future<void> sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final user = _ref.read(authNotifierProvider).user;
    final msg = await _repository.sendMessage(
      rideId: _rideId,
      text: text.trim(),
      senderId: user?.id ?? 'usr_peer',
      senderName: user?.name ?? 'DIU Student',
    );

    final formatted = ChatMessage(
      id: msg.id,
      rideId: msg.rideId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      text: msg.text,
      timestamp: msg.timestamp,
      isMe: true,
      isRead: msg.isRead,
      isLocationShare: msg.isLocationShare,
      sharedLat: msg.sharedLat,
      sharedLng: msg.sharedLng,
    );

    if (!state.messages.any((m) => m.id == formatted.id)) {
      state = state.copyWith(messages: [...state.messages, formatted]);
    }
  }

  Future<void> shareLocation(double lat, double lng) async {
    final user = _ref.read(authNotifierProvider).user;
    final msg = await _repository.sendMessage(
      rideId: _rideId,
      text: '📍 Shared current campus coordinates (Gate 1 Canopy)',
      isLocationShare: true,
      sharedLat: lat,
      sharedLng: lng,
      senderId: user?.id ?? 'usr_peer',
      senderName: user?.name ?? 'DIU Student',
    );

    final formatted = ChatMessage(
      id: msg.id,
      rideId: msg.rideId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      text: msg.text,
      timestamp: msg.timestamp,
      isMe: true,
      isLocationShare: true,
      sharedLat: lat,
      sharedLng: lng,
    );

    if (!state.messages.any((m) => m.id == formatted.id)) {
      state = state.copyWith(messages: [...state.messages, formatted]);
    }
  }
}

final chatNotifierProvider = StateNotifierProvider.family<ChatNotifier, ChatState, String>((ref, rideId) {
  final repo = ref.watch(chatRepositoryProvider);
  return ChatNotifier(repo, ref, rideId);
});
