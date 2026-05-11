import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({
    super.key,
    required this.sdk,
    required this.createCallId,
    this.peerId = 'peer-b',
  });

  final SDKConnect sdk;
  final String Function() createCallId;
  final String peerId;

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  Future<void> _startVideoCall() async {
    try {
      await widget.sdk.startCall(
        callId: widget.createCallId(),
        peerId: widget.peerId,
        callType: SDKConnectCallType.video,
      );
    } on CallLifecycleException {
      _showMessage('P2P only: max 2 participants per room.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to start video call.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      stream: widget.sdk.runtimeStates,
      initialData: widget.sdk.runtimeState,
      builder: (context, snapshot) {
        final runtime = snapshot.data ?? widget.sdk.runtimeState;
        final state = runtime.connectionState;
        final canStart = state == SDKConnectConnectionState.idle ||
            state == SDKConnectConnectionState.disconnected ||
            state == SDKConnectConnectionState.failed;

        if (canStart) {
          return Scaffold(
            appBar: AppBar(title: const Text('Video Feature')),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.videocam, size: 52),
                      const SizedBox(height: 12),
                      Text(
                        'Video call with SDKConnect widget',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Peer: ${widget.peerId}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _startVideoCall,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Video Call'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return RemoteVideoCallWidget(sdk: widget.sdk, title: 'Video Feature');
      },
    );
  }
}
