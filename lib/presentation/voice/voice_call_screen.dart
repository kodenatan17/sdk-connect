import 'package:flutter/material.dart';
import 'package:sdk_connect/presentation/voice/voice_call_controller.dart';

class VoiceCallScreen extends StatelessWidget {
  const VoiceCallScreen({
    super.key,
    required this.controller,
    this.onAccept,
    this.onReject,
    this.onEnd,
  });

  final VoiceCallController controller;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onReject;
  final Future<void> Function()? onEnd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final ui = controller.uiState;
        return Scaffold(
          appBar: AppBar(title: const Text('Voice Call')),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      ui.title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      ui.subtitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    _IncomingActions(
                      showAccept: ui.showAccept,
                      showReject: ui.showReject,
                      onAccept: onAccept,
                      onReject: onReject,
                    ),
                    _InCallControls(
                      enabled: ui.controlsEnabled,
                      showEnd: ui.showEnd,
                      isMuted: ui.isMuted,
                      isSpeakerOn: ui.isSpeakerOn,
                      onMute: controller.toggleMute,
                      onSpeaker: controller.toggleSpeaker,
                      onEnd: onEnd,
                    ),
                    if (!ui.showAccept && !ui.showReject && !ui.showEnd)
                      const Text('Waiting...'),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _IncomingActions extends StatelessWidget {
  const _IncomingActions({
    required this.showAccept,
    required this.showReject,
    required this.onAccept,
    required this.onReject,
  });

  final bool showAccept;
  final bool showReject;
  final Future<void> Function()? onAccept;
  final Future<void> Function()? onReject;

  @override
  Widget build(BuildContext context) {
    if (!showAccept && !showReject) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (showReject)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: onReject == null ? null : () => onReject!.call(),
            icon: const Icon(Icons.call_end),
            label: const Text('Reject'),
          ),
        if (showAccept) ...<Widget>[
          const SizedBox(width: 12),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: onAccept == null ? null : () => onAccept!.call(),
            icon: const Icon(Icons.call),
            label: const Text('Accept'),
          ),
        ],
      ],
    );
  }
}

class _InCallControls extends StatelessWidget {
  const _InCallControls({
    required this.enabled,
    required this.showEnd,
    required this.isMuted,
    required this.isSpeakerOn,
    required this.onMute,
    required this.onSpeaker,
    required this.onEnd,
  });

  final bool enabled;
  final bool showEnd;
  final bool isMuted;
  final bool isSpeakerOn;
  final Future<void> Function() onMute;
  final Future<void> Function() onSpeaker;
  final Future<void> Function()? onEnd;

  @override
  Widget build(BuildContext context) {
    if (!showEnd) {
      return const SizedBox.shrink();
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton.filledTonal(
          tooltip: 'Mute',
          onPressed: enabled ? () => onMute() : null,
          icon: Icon(isMuted ? Icons.mic_off : Icons.mic),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          tooltip: 'Speaker',
          onPressed: enabled ? () => onSpeaker() : null,
          icon: Icon(isSpeakerOn ? Icons.volume_up : Icons.hearing),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          tooltip: 'End',
          style: IconButton.styleFrom(backgroundColor: Colors.red),
          onPressed: onEnd == null ? null : () => onEnd!.call(),
          icon: const Icon(Icons.call_end),
        ),
      ],
    );
  }
}