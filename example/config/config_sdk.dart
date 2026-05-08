import 'package:sdk_connect/sdk_connect.dart';

class ConfigSdk {
  const ConfigSdk();

  static const String localUserId = 'demo-user-a';

  static const String roomUrl = String.fromEnvironment(
    'SDK_CONNECT_ROOM_URL',
    defaultValue: '',
  );
  static const String token = String.fromEnvironment(
    'SDK_CONNECT_ACCESS_TOKEN',
    defaultValue: '',
  );

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
    required SDKConnectCallType callType,
  }) {
    signaling.send(
      SDKConnectSignal(
        type: SDKConnectSignalType.invite,
        callId: callId,
        fromUserId: peerId,
        toUserId: localUserId,
        callType: callType,
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
