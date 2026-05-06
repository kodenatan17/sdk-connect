abstract class MediaEngine {
  Future<void> connect({
    required String roomUrl,
    required String token,
  });

  Future<void> disconnect();

  bool get isConnected;
}
