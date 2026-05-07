import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_type.dart';

class CallSession {
  const CallSession({
    required this.callId,
    required this.peerId,
    required this.direction,
    this.callType = CallType.voice,
    required this.createdAt,
  });

  final String callId;
  final String peerId;
  final CallDirection direction;
  final CallType callType;
  final DateTime createdAt;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'callId': callId,
      'peerId': peerId,
      'direction': direction.name,
      'callType': callType.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }
}
