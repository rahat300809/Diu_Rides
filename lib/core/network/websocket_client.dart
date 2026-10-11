import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:diu_ride/core/config/app_config.dart';

enum WebSocketConnectionStatus { connecting, connected, disconnected }

class WebSocketClient {
  WebSocketChannel? _channel;
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  final _statusController = StreamController<WebSocketConnectionStatus>.broadcast();
  Timer? _reconnectTimer;
  Timer? _pingTimer;
  bool _isDisposed = false;
  bool _useFallback = false;

  Stream<Map<String, dynamic>> get messages => _messageController.stream;
  Stream<WebSocketConnectionStatus> get status => _statusController.stream;
  bool get isConnected => _channel != null;

  void connect({String? customUrl}) {
    if (AppConfig.current.useMockData) {
      _statusController.add(WebSocketConnectionStatus.connected);
      return;
    }

    final url = customUrl ??
        (_useFallback ? AppConfig.fallbackWsUrl : AppConfig.current.wsBaseUrl);

    try {
      _statusController.add(WebSocketConnectionStatus.connecting);
      debugPrint('[WebSocket] Connecting to $url');
      _channel = WebSocketChannel.connect(Uri.parse(url));
      _statusController.add(WebSocketConnectionStatus.connected);

      _startPing();

      _channel?.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data.toString()) as Map<String, dynamic>;
            _messageController.add(decoded);
          } catch (e) {
            debugPrint('WebSocket parse error: $e');
          }
        },
        onError: (err) {
          debugPrint('WebSocket error on $url: $err');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('WebSocket connection closed on $url');
          _handleDisconnect();
        },
      );
    } catch (e) {
      debugPrint('WebSocket connection failed on $url: $e');
      _handleDisconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_channel != null && !_isDisposed) {
        try {
          _channel?.sink.add(jsonEncode({'event': 'ping', 'timestamp': DateTime.now().toIso8601String()}));
        } catch (_) {}
      }
    });
  }

  void _handleDisconnect() {
    _statusController.add(WebSocketConnectionStatus.disconnected);
    _pingTimer?.cancel();
    _channel = null;

    if (!_isDisposed) {
      _reconnectTimer?.cancel();
      // Alternate fallback if not on web
      if (!kIsWeb) {
        _useFallback = !_useFallback;
      }
      _reconnectTimer = Timer(const Duration(seconds: 4), () {
        connect();
      });
    }
  }

  void send(String event, Map<String, dynamic> data) {
    final payload = jsonEncode({'event': event, 'data': data});
    if (_channel != null) {
      try {
        _channel?.sink.add(payload);
        return;
      } catch (e) {
        debugPrint('WebSocket send failed: $e');
      }
    }
    debugPrint('[WS Offline send buffer] Event: $event Payload: $payload');
  }

  void dispose() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (_) {}
    _messageController.close();
    _statusController.close();
  }
}
