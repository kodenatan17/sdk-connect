import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

class VideoCallScreen extends StatelessWidget {
  const VideoCallScreen({
    super.key,
    required this.state,
    required this.onEnd,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleCamera,
  });

  final CallState state;
  final Future<void> Function() onEnd;
  final Future<void> Function() onToggleMute;
  final Future<void> Function() onToggleSpeaker;
  final Future<void> Function() onToggleCamera;

  @override
  Widget build(BuildContext context) {
    final isConnected = state.phase == CallPhase.connected;
    return Scaffold(
      appBar: AppBar(title: const Text('Video Call')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(isConnected ? Icons.videocam : Icons.video_call, size: 56),
                const SizedBox(height: 16),
                Text(
                  isConnected
                      ? 'Video connected to ${state.session?.peerId ?? 'Unknown'}'
                      : 'Starting video with ${state.session?.peerId ?? 'Unknown'}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Muted: ${state.isMuted ? 'on' : 'off'}\nSpeaker: ${state.isSpeakerOn ? 'on' : 'off'}\nCamera: ${state.isVideoEnabled ? 'on' : 'off'}',
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
                      onPressed: isConnected ? () => onToggleMute() : null,
                      icon: Icon(state.isMuted ? Icons.mic_off : Icons.mic),
                      label: Text(state.isMuted ? 'Unmute' : 'Mute'),
                    ),
                    OutlinedButton.icon(
                      onPressed: isConnected ? () => onToggleSpeaker() : null,
                      icon: Icon(
                        state.isSpeakerOn ? Icons.volume_up : Icons.hearing,
                      ),
                      label: Text(
                        state.isSpeakerOn ? 'Speaker Off' : 'Speaker On',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: isConnected ? () => onToggleCamera() : null,
                      icon: Icon(
                        state.isVideoEnabled
                            ? Icons.videocam_off
                            : Icons.videocam,
                      ),
                      label: Text(
                        state.isVideoEnabled ? 'Camera Off' : 'Camera On',
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
