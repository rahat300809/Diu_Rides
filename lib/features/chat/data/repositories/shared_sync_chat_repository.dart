import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:diu_ride/core/config/app_config.dart';
import 'package:diu_ride/core/network/websocket_client.dart';
import 'package:diu_ride/core/storage/preferences_service.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/models/campus_conversation_model.dart';
import 'package:diu_ride/features/chat/data/repositories/chat_repository.dart';
import 'package:diu_ride/features/chat/data/repositories/mock_chat_repository.dart';

class SharedSyncChatRepository implements ChatRepository {
  final PreferencesService? preferences;
  final WebSocketClient? wsClient;
  final MockChatRepository _localFallback = MockChatRepository();
  final _streamController = StreamController<ChatMessage>.broadcast();
  final Map<String, List<ChatMessage>> _cache = {};
  Timer? _pollingTimer;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 4),
    receiveTimeout: const Duration(seconds: 4),
  ));

  SharedSyncChatRepository({this.preferences, this.wsClient}) {
    _startPolling();
    _listenWebSocket();
  }

  void _listenWebSocket() {
    wsClient?.messages.listen((msg) {
      final event = msg['event'] ?? msg['type'];
      final data = msg['data'];
      if (event == 'chat_message' && data is Map) {
        try {
          final chatMsg = ChatMessage.fromJson(
            Map<String, dynamic>.from(data),
            _currentUserId,
          );
          final list = _cache.putIfAbsent(chatMsg.rideId, () => []);
          if (!list.any((m) => m.id == chatMsg.id)) {
            list.add(chatMsg);
            _streamController.add(chatMsg);
          }
        } catch (_) {}
      }
    });
  }

  String get _currentUserId {
    final cached = preferences?.getUserJson();
    if (cached != null) {
      try {
        final decoded = jsonDecode(cached) as Map<String, dynamic>;
        return decoded['id']?.toString() ?? 'usr_current';
      } catch (_) {}
    }
    return 'usr_current';
  }

  String get _apiBase {
    if (kIsWeb) {
      final origin = Uri.base.origin;
      return '$origin/ride/api';
    }
    return AppConfig.current.apiBaseUrl;
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      for (final rideId in _cache.keys.toList()) {
        try {
          final res = await _dio.get('$_apiBase/messages?ride_id=$rideId');
          if (res.statusCode == 200 && res.data is List) {
            final serverMsgs = (res.data as List)
                .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map), _currentUserId))
                .toList();

            final currentKnown = _cache[rideId] ?? [];
            for (final msg in serverMsgs) {
              if (!currentKnown.any((existing) => existing.id == msg.id)) {
                currentKnown.add(msg);
                _streamController.add(msg);
              }
            }
          }
        } catch (_) {}
      }
    });
  }

  @override
  Future<List<ChatMessage>> getMessages(String rideId) async {
    try {
      final response = await _dio.get('$_apiBase/messages?ride_id=$rideId');
      if (response.statusCode == 200 && response.data is List) {
        final list = (response.data as List)
            .map((item) => ChatMessage.fromJson(Map<String, dynamic>.from(item as Map), _currentUserId))
            .toList();

        _cache[rideId] = list;
        return list;
      }
    } catch (e) {
      debugPrint('Get messages error (fallback to local): $e');
    }

    final local = await _localFallback.getMessages(rideId);
    _cache[rideId] = local;
    return local;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String rideId,
    required String text,
    bool isLocationShare = false,
    double? sharedLat,
    double? sharedLng,
    String? senderId,
    String? senderName,
    String? receiverId,
  }) async {
    final msg = ChatMessage(
      id: 'msg_${const Uuid().v4().substring(0, 8)}',
      rideId: rideId,
      senderId: senderId ?? 'usr_current',
      senderName: senderName ?? 'Me',
      receiverId: receiverId,
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
      isLocationShare: isLocationShare,
      sharedLat: sharedLat,
      sharedLng: sharedLng,
    );

    // 1. Post to central server
    try {
      await _dio.post(
        '$_apiBase/messages',
        data: msg.toJson(),
      );
      debugPrint('Message saved to central backend: ${msg.id}');
      wsClient?.send('chat_message', msg.toJson());
    } catch (e) {
      debugPrint('Note: Central message post error: $e');
    }

    // 2. Add to cache and broadcast immediately
    _cache.putIfAbsent(rideId, () => []).add(msg);
    _streamController.add(msg);

    return msg;
  }

  @override
  Stream<ChatMessage> subscribeToMessages(String rideId) {
    _cache.putIfAbsent(rideId, () => []);
    return _streamController.stream.where((m) => m.rideId == rideId);
  }

  @override
  Future<List<CampusConversationModel>> getConversations({String? userId}) async {
    try {
      final uid = userId ?? _currentUserId;
      final response = await _dio.get('$_apiBase/conversations?user_id=$uid');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .map((item) => CampusConversationModel.fromJson(Map<String, dynamic>.from(item as Map)))
            .toList();
      }
    } catch (e) {
      debugPrint('SharedSyncChatRepository: getConversations failed, trying fallback: $e');
    }
    return _localFallback.getConversations(userId: userId);
  }

  void dispose() {
    _pollingTimer?.cancel();
    _streamController.close();
  }
}
