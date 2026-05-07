import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

import 'incoming_call_screen.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({
    super.key,
    required this.controller,
    required this.onAccept,
    required this.onReject,
    required this.onEnd,
  });

  final VoiceCallController controller;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final state = controller.callState;

    if (state.phase == CallPhase.ringing) {
      return IncomingCallScreen(
        peerId: state.session?.peerId ?? 'Unknown',
        onAccept: onAccept,
        onReject: onReject,
      );
    }

    // Reuse SDK-provided in-call UI and controls (mute/speaker/end).
    return VoiceCallScreen(
      controller: controller,
      onAccept: onAccept,
      onReject: onReject,
      onEnd: onEnd,
    );
  }
}
