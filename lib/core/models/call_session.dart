import 'package:sdk_connect/core/enums/call_direction.dart';

class CallSession {
  const CallSession({
    required this.callId,
    required this.peerId,
    required this.direction,
    required this.createdAt,
  });

  final String callId;
  final String peerId;
  final CallDirection direction;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'callId': callId,
      'peerId': peerId,
      'direction': direction.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
