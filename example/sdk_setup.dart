import 'package:sdk_connect/sdk_connect.dart';

class SdkSetup {
  const SdkSetup();

  static const String localUserId = 'demo-user-a';

  static const String roomUrl =
      String.fromEnvironment('SDK_CONNECT_ROOM_URL', defaultValue: '');
  static const String token =
      String.fromEnvironment('SDK_CONNECT_ACCESS_TOKEN', defaultValue: '');

  Future<SdkConnectScope> initialize() async {
    // Uses SDK abstraction only; no direct LiveKit object in the app layer.
    return SdkConnectScope.liveKit();
  }

  InMemoryVoiceCallSignalingTransport createDemoSignaling() {
    return InMemoryVoiceCallSignalingTransport();
  }

  VoiceCallTokenProvider createTokenProvider() {
    return (_) async => VoiceCallCredentials(
          roomUrl: requireValidRoomUrl(),
          token: requireValidToken(),
        );
  }

  VoiceCallSignalValidator createSignalValidator() {
    const allowedPeers = <String>{'peer-a', 'peer-b'};
    return (signal) async {
      return signal.toUserId == localUserId &&
          allowedPeers.contains(signal.fromUserId);
    };
  }

  void simulateIncomingForDemo({
    required VoiceCallSignalingTransport signaling,
    required String localUserId,
    required String callId,
    required String peerId,
  }) {
    signaling.send(
      VoiceCallSignal(
        type: VoiceCallSignalType.invite,
        callId: callId,
        fromUserId: peerId,
        toUserId: localUserId,
      ),
    );
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
