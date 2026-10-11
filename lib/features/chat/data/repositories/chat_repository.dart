import 'package:diu_ride/features/chat/data/models/chat_message.dart';

abstract class ChatRepository {
  Future<List<ChatMessage>> getMessages(String rideId);
  Future<ChatMessage> sendMessage({
    required String rideId,
    required String text,
    bool isLocationShare = false,
    double? sharedLat,
    double? sharedLng,
    String? senderId,
    String? senderName,
  });
  Stream<ChatMessage> subscribeToMessages(String rideId);
}
