import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/models/call_session.dart';

class CallState {
  const CallState({
    required this.phase,
    this.session,
    this.reason,
    required this.updatedAt,
  });

  factory CallState.idle() {
    return CallState(
      phase: CallPhase.idle,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  final CallPhase phase;
  final CallSession? session;
  final String? reason;
  final DateTime updatedAt;

  CallState copyWith({
    CallPhase? phase,
    CallSession? session,
    String? reason,
    DateTime? updatedAt,
    bool clearReason = false,
  }) {
    return CallState(
      phase: phase ?? this.phase,
      session: session ?? this.session,
      reason: clearReason ? null : (reason ?? this.reason),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'phase': phase.name,
      'session': session?.toMap(),
      'reason': reason,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
