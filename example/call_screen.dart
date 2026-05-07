import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

import 'incoming_call_screen.dart';

class CallScreen extends StatelessWidget {
  const CallScreen({
    super.key,
    required this.state,
    required this.onAccept,
    required this.onReject,
    required this.onEnd,
    required this.onToggleMute,
    required this.onToggleSpeaker,
  });

  final CallState state;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;
  final Future<void> Function() onEnd;
  final Future<void> Function() onToggleMute;
  final Future<void> Function() onToggleSpeaker;

  @override
  Widget build(BuildContext context) {
    if (state.phase == CallPhase.ringing) {
      return IncomingCallScreen(
        peerId: state.session?.peerId ?? 'Unknown',
        onAccept: onAccept,
        onReject: onReject,
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Active Call')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  state.phase == CallPhase.connected
                      ? Icons.call
                      : Icons.phone_forwarded,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  state.phase == CallPhase.connected
                      ? 'Connected to ${state.session?.peerId ?? 'Unknown'}'
                      : 'Calling ${state.session?.peerId ?? 'Unknown'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Muted: ${state.isMuted ? 'on' : 'off'}\nSpeaker: ${state.isSpeakerOn ? 'on' : 'off'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: state.phase == CallPhase.connected
                          ? () => onToggleMute()
                          : null,
                      icon: Icon(
                        state.isMuted ? Icons.mic_off : Icons.mic,
                      ),
                      label: Text(state.isMuted ? 'Unmute' : 'Mute'),
                    ),
                    OutlinedButton.icon(
                      onPressed: state.phase == CallPhase.connected
                          ? () => onToggleSpeaker()
                          : null,
                      icon: Icon(
                        state.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      ),
                      label: Text(
                        state.isSpeakerOn ? 'Speaker Off' : 'Speaker On',
                      ),
                    ),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red,
                      ),
                      onPressed: () => onEnd(),
                      icon: const Icon(Icons.call_end),
                      label: const Text('End Call'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
