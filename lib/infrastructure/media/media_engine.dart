abstract class MediaEngine {
  Future<void> connect({
    required String roomUrl,
    required String token,
  });

  Future<void> disconnect();

  Future<void> setMuted(bool muted);

  Future<void> setSpeakerOn(bool speakerOn);

  bool get isConnected;
  bool get isMuted;
  bool get isSpeakerOn;
}
