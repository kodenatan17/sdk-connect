import 'package:sdk_connect/sdk_connect.dart';
import 'package:sdk_connect/di/sdk_connect_scope.dart';

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

  InMemorySDKConnectSignalingTransport createDemoSignaling() {
    return InMemorySDKConnectSignalingTransport();
  }

  SDKConnectTokenProvider createTokenProvider() {
    return (_) async => SDKConnectCredentials(
          roomUrl: requireValidRoomUrl(),
          token: requireValidToken(),
        );
  }

  SDKConnectSignalValidator createSignalValidator() {
    const allowedPeers = <String>{'peer-a', 'peer-b'};
    return (signal) async {
      return signal.toUserId == localUserId &&
          allowedPeers.contains(signal.fromUserId);
    };
  }

  void simulateIncomingForDemo({
    required SDKConnectSignalingTransport signaling,
    required String localUserId,
    required String callId,
    required String peerId,
  }) {
    signaling.send(
      SDKConnectSignal(
        type: SDKConnectSignalType.invite,
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
