enum MediaEngineEventType {
  disconnected,
  p2pLimitExceeded,
}

class P2PLimitExceededException implements Exception {
  const P2PLimitExceededException([this.message = 'P2P only: group call is not supported.']);

  final String message;

  @override
  String toString() => 'P2PLimitExceededException: $message';
}

class MediaEngineEvent {
  const MediaEngineEvent({
    required this.type,
    this.reason,
  });

  final MediaEngineEventType type;
  final String? reason;
}

abstract class MediaEngine {
  Stream<MediaEngineEvent> get events;

  Future<void> connect({
    required String roomUrl,
    required String token,
  });

  Future<void> disconnect();

  Future<void> setMuted(bool muted);

  Future<void> setSpeakerOn(bool speakerOn);

  Future<void> setCameraOn(bool enabled);

  Future<void> dispose();

  bool get isConnected;
  bool get isMuted;
  bool get isSpeakerOn;
  bool get isVideoEnabled;
}
