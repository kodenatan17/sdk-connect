/// SDK configuration constants and credential providers for the example app.
///
/// All SDK-specific setup is centralised here. Screens and bootstrap code
/// consume this class — no config is duplicated elsewhere.
class SdkConfig {
  SdkConfig._();

  static const String localUserId = 'demo-user-a';
  static const String defaultPeerId = 'peer-b';

  static const String _roomUrl = String.fromEnvironment(
    'SDK_CONNECT_ROOM_URL',
    defaultValue: '',
  );

  static const String _token = String.fromEnvironment(
    'SDK_CONNECT_ACCESS_TOKEN',
    defaultValue: '',
  );

  static String requireValidRoomUrl() {
    final value = _roomUrl.trim();
    if (value.isEmpty) {
      throw StateError('Missing SDK_CONNECT_ROOM_URL env variable.');
    }
    return value;
  }

  static String requireValidToken() {
    final value = _token.trim();
    if (value.isEmpty) {
      throw StateError('Missing SDK_CONNECT_ACCESS_TOKEN env variable.');
    }
    return value;
  }
}
