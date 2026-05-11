import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({
    super.key,
    required this.sdk,
    required this.createCallId,
    this.peerId = 'peer-b',
  });

  final SDKConnect sdk;
  final String Function() createCallId;
  final String peerId;

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen> {
  Future<void> _startVoiceCall() async {
    try {
      await widget.sdk.startCall(
        callId: widget.createCallId(),
        peerId: widget.peerId,
        callType: SDKConnectCallType.voice,
      );
    } on CallLifecycleException {
      _showMessage('P2P only: max 2 participants per room.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to start voice call.');
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
            appBar: AppBar(title: const Text('Voice Feature')),
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.call, size: 52),
                      const SizedBox(height: 12),
                      Text(
                        'Voice call with SDKConnect widget',
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
                        onPressed: _startVoiceCall,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Start Voice Call'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return RemoteVoiceCallWidget(sdk: widget.sdk, title: 'Voice Feature');
      },
    );
  }
}
