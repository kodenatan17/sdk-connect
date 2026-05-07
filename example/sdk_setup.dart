import 'package:sdk_connect/sdk_connect.dart';

class SdkSetup {
  const SdkSetup();

  static const String roomUrl =
      String.fromEnvironment('SDK_CONNECT_ROOM_URL', defaultValue: '');
  static const String token =
      String.fromEnvironment('SDK_CONNECT_ACCESS_TOKEN', defaultValue: '');

  Future<SdkConnectScope> initialize() async {
    // Uses SDK abstraction only; no direct LiveKit object in the app layer.
    return SdkConnectScope.liveKit();
  }

  void simulateIncomingForDemo({
    required SdkConnectScope scope,
    required String callId,
    required String peerId,
  }) {
    scope.callEngine.onIncoming(callId: callId, peerId: peerId);
  }

  String requireValidToken() {
    final value = token.trim();
    if (value.isEmpty) {
      throw StateError('Missing SDK_CONNECT_ACCESS_TOKEN');
    }
    return value;
  }

  String requireValidRoomUrl() {
    final value = roomUrl.trim();
    if (value.isEmpty) {
      throw StateError('Missing SDK_CONNECT_ROOM_URL');
    }
    return value;
  }
}
