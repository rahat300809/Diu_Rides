import 'dart:async';
import 'package:uuid/uuid.dart';
import 'package:diu_ride/features/chat/data/models/chat_message.dart';
import 'package:diu_ride/features/chat/data/repositories/chat_repository.dart';

class MockChatRepository implements ChatRepository {
  final Map<String, List<ChatMessage>> _messages = {};
  final _streamController = StreamController<ChatMessage>.broadcast();

  MockChatRepository() {
    _seedMessages();
  }

  void _seedMessages() {
    final now = DateTime.now();
    _messages['ride_active_01'] = [
      ChatMessage(
        id: 'msg_01',
        rideId: 'ride_active_01',
        senderId: 'driver_tanvir_01',
        senderName: 'Tanvir Ahmed',
        text: 'Assalamu Alaikum! I am starting from Academic Bldg 4 in 5 minutes.',
        timestamp: now.subtract(const Duration(minutes: 6)),
        isMe: false,
      ),
      ChatMessage(
        id: 'msg_02',
        rideId: 'ride_active_01',
        senderId: 'usr_diu_tanvir_201',
        senderName: 'Me',
        text: 'Walaikum Assalam bhai. I am waiting at the Gate 1 canopy.',
        timestamp: now.subtract(const Duration(minutes: 4)),
        isMe: true,
      ),
      ChatMessage(
        id: 'msg_03',
        rideId: 'ride_active_01',
        senderId: 'driver_tanvir_01',
        senderName: 'Tanvir Ahmed',
        text: 'Great, see you there! Silver Axio, hazards on.',
        timestamp: now.subtract(const Duration(minutes: 2)),
        isMe: false,
      ),
    ];
  }

  @override
  Future<List<ChatMessage>> getMessages(String rideId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _messages[rideId] ?? [];
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
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final msg = ChatMessage(
      id: 'msg_${const Uuid().v4().substring(0, 8)}',
      rideId: rideId,
      senderId: senderId ?? 'usr_diu_tanvir_201',
      senderName: senderName ?? 'Me',
      text: text,
      timestamp: DateTime.now(),
      isMe: true,
      isLocationShare: isLocationShare,
      sharedLat: sharedLat,
      sharedLng: sharedLng,
    );

    if (!_messages.containsKey(rideId)) {
      _messages[rideId] = [];
    }
    _messages[rideId]!.add(msg);
    _streamController.add(msg);

    // Simulated driver peer response after 2.5 seconds
    if (!isLocationShare) {
      Timer(const Duration(milliseconds: 2500), () {
        final reply = ChatMessage(
          id: 'msg_${const Uuid().v4().substring(0, 8)}',
          rideId: rideId,
          senderId: 'driver_tanvir_01',
          senderName: 'Tanvir Ahmed',
          text: 'Got it! Almost near Birulia bridge, see you in 3 mins.',
          timestamp: DateTime.now(),
          isMe: false,
        );
        _messages[rideId]?.add(reply);
        _streamController.add(reply);
      });
    }

    return msg;
  }

  @override
  Stream<ChatMessage> subscribeToMessages(String rideId) {
    return _streamController.stream.where((m) => m.rideId == rideId);
  }
}
