enum MediaEngineEventType {
  disconnected,
  p2pLimitExceeded,
  reconnecting,
  reconnected,
  iceRestarting,
  iceRecovered,
  networkQualityChanged,
}

class MediaNetworkQuality {
  const MediaNetworkQuality({
    required this.score,
    this.rttMs,
    this.packetLoss,
    this.jitterMs,
    this.bitrateKbps,
  }) : assert(score >= 0 && score <= 100, 'score must be in range 0..100');

  final int score;
  final int? rttMs;
  final double? packetLoss;
  final int? jitterMs;
  final int? bitrateKbps;
}

class MediaConnectionProfile {
  const MediaConnectionProfile({
    this.preferAudio = false,
    this.maxBitrateKbps,
    this.maxVideoHeight,
    this.maxVideoFps,
  });

  static const MediaConnectionProfile balanced = MediaConnectionProfile();

  final bool preferAudio;
  final int? maxBitrateKbps;
  final int? maxVideoHeight;
  final int? maxVideoFps;
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
    this.networkQuality,
  });

  final MediaEngineEventType type;
  final String? reason;
  final MediaNetworkQuality? networkQuality;
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

  Future<void> restartIce();

  Future<void> updateToken(String token);

  Future<void> setConnectionProfile(MediaConnectionProfile profile);

  Future<void> dispose();

  bool get isConnected;
  bool get isMuted;
  bool get isSpeakerOn;
  bool get isVideoEnabled;
}
