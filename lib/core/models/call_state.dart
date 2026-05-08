import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/models/call_session.dart';

class CallState {
  const CallState({
    required this.phase,
    this.session,
    this.reason,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.isVideoEnabled,
    this.isReconnecting = false,
    this.reconnectAttempts = 0,
    this.networkScore,
    this.isAudioPriority = false,
    required this.updatedAt,
  });

  factory CallState.idle() {
    return CallState(
      phase: CallPhase.idle,
      isMuted: false,
      isSpeakerOn: false,
      isVideoEnabled: false,
      isReconnecting: false,
      reconnectAttempts: 0,
      networkScore: null,
      isAudioPriority: false,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  final CallPhase phase;
  final CallSession? session;
  final String? reason;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isReconnecting;
  final int reconnectAttempts;
  final int? networkScore;
  final bool isAudioPriority;
  final DateTime updatedAt;

  CallState copyWith({
    CallPhase? phase,
    CallSession? session,
    String? reason,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isReconnecting,
    int? reconnectAttempts,
    int? networkScore,
    bool clearNetworkScore = false,
    bool? isAudioPriority,
    DateTime? updatedAt,
    bool clearReason = false,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      session: session ?? this.session,
      reason: clearReason ? null : (reason ?? this.reason),
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isReconnecting: isReconnecting ?? this.isReconnecting,
      reconnectAttempts: reconnectAttempts ?? this.reconnectAttempts,
      networkScore: clearNetworkScore ? null : (networkScore ?? this.networkScore),
      isAudioPriority: isAudioPriority ?? this.isAudioPriority,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'phase': phase.name,
      'session': session?.toMap(),
      'reason': reason,
      'isMuted': isMuted,
      'isSpeakerOn': isSpeakerOn,
      'isVideoEnabled': isVideoEnabled,
      'isReconnecting': isReconnecting,
      'reconnectAttempts': reconnectAttempts,
      'networkScore': networkScore,
      'isAudioPriority': isAudioPriority,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
