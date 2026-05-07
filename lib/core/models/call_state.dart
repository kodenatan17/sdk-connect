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
    required this.updatedAt,
  });

  factory CallState.idle() {
    return CallState(
      phase: CallPhase.idle,
      isMuted: false,
      isSpeakerOn: false,
      isVideoEnabled: false,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  final CallPhase phase;
  final CallSession? session;
  final String? reason;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final DateTime updatedAt;

  CallState copyWith({
    CallPhase? phase,
    CallSession? session,
    String? reason,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
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
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
