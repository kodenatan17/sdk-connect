import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

/// Signaling states managed externally to SDKConnect.
///
/// These represent pre-media business signaling before SDK media starts.
/// SDKConnect connection states take over once media
/// negotiation begins.
enum _SignalingState { idle, dialing, rejected }

/// Voice call screen for the example app.
///
/// - Pre-media phase: displays signaling state (dialing / rejected).
/// - Active phase: delegates rendering to [RemoteVoiceCallWidget].
/// - Widget callbacks (onReconnect, onDisconnected, onEnded) are wired here;
///   no lifecycle logic leaks into the widget.
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
  _SignalingState _signalingState = _SignalingState.idle;

  Future<void> _dial() async {
    setState(() => _signalingState = _SignalingState.dialing);
    try {
      await widget.sdk.startCall(
        callId: widget.createCallId(),
        peerId: widget.peerId,
        callType: SDKConnectCallType.voice,
      );
    } on CallLifecycleException {
      if (!mounted) return;
      setState(() => _signalingState = _SignalingState.rejected);
      _showSnackBar('P2P only: max 2 participants per room.');
    } on StateError {
      if (!mounted) return;
      setState(() => _signalingState = _SignalingState.idle);
      _showSnackBar('Missing SDK runtime configuration.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _signalingState = _SignalingState.idle);
      _showSnackBar('Failed to start voice call.');
    }
  }

  void _onReconnect() {
    _showSnackBar('Reconnecting…');
  }

  void _onDisconnected(String? reason) {
    _showSnackBar(reason ?? 'Disconnected');
  }

  void _onEnded(String? _) {
    if (!mounted) return;
    setState(() => _signalingState = _SignalingState.idle);
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      stream: widget.sdk.runtimeStates,
      initialData: widget.sdk.runtimeState,
      builder: (context, snapshot) {
        final conn = (snapshot.data ?? widget.sdk.runtimeState).connectionState;
        final isActive =
            conn == SDKConnectConnectionState.connecting ||
            conn == SDKConnectConnectionState.connected ||
            conn == SDKConnectConnectionState.reconnecting;

        if (isActive) {
          return RemoteVoiceCallWidget(
            sdk: widget.sdk,
            title: 'Voice Call',
            callbacks: SDKConnectWidgetCallbacks(
              onReconnect: _onReconnect,
              onDisconnected: _onDisconnected,
              onEnded: _onEnded,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Voice Call')),
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _PreCallBody(
                  signalingState: _signalingState,
                  peerId: widget.peerId,
                  onDial: _dial,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreCallBody extends StatelessWidget {
  const _PreCallBody({
    required this.signalingState,
    required this.peerId,
    required this.onDial,
  });

  final _SignalingState signalingState;
  final String peerId;
  final VoidCallback onDial;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Icon(Icons.call, size: 52),
        const SizedBox(height: 12),
        Text(
          _label,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text('Peer: $peerId', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        if (signalingState == _SignalingState.dialing)
          const CircularProgressIndicator()
        else
          FilledButton.icon(
            onPressed: onDial,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Voice Call'),
          ),
      ],
    );
  }

  String get _label => switch (signalingState) {
    _SignalingState.idle => 'Voice call with SDKConnect',
    _SignalingState.dialing => 'Dialing…',
    _SignalingState.rejected => 'Call rejected — try again',
  };
}
