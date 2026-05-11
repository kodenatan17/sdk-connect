import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

/// Signaling states managed externally to SDKConnect.
///
/// These represent the pre-media lifecycle (outgoing dialing, incoming ringing,
/// or a rejected signal). SDKConnect connection states take over once media
/// negotiation begins.
enum _SignalingState { idle, dialing, ringing, rejected }

/// Video call screen for the example app.
///
/// - Pre-media phase: displays signaling state (dialing / ringing / rejected).
/// - Active phase: delegates rendering to [RemoteVideoCallWidget].
/// - Widget callbacks (onCallStateChanged, onReconnect, onDisconnected,
///   onEnded) are wired here; no lifecycle logic leaks into the widget.
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
  _SignalingState _signalingState = _SignalingState.idle;

  // ── Signaling ────────────────────────────────────────────────────────────

  Future<void> _dial() async {
    setState(() => _signalingState = _SignalingState.dialing);
    try {
      await widget.sdk.startCall(
        callId: widget.createCallId(),
        peerId: widget.peerId,
        callType: SDKConnectCallType.video,
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
      _showSnackBar('Failed to start video call.');
    }
  }

  // ── Widget callbacks (SDKConnect state only) ─────────────────────────────

  void _onCallStateChanged(SDKConnectWidgetPhase phase) {
    if (!mounted) return;
    if (phase == SDKConnectWidgetPhase.ended) {
      setState(() => _signalingState = _SignalingState.idle);
    }
  }

  void _onReconnect() {
    _showSnackBar('Reconnecting…');
  }

  void _onDisconnected(String? reason) {
    _showSnackBar(reason ?? 'Disconnected');
  }

  void _onEnded(String? reason) {
    if (!mounted) return;
    setState(() => _signalingState = _SignalingState.idle);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      stream: widget.sdk.runtimeStates,
      initialData: widget.sdk.runtimeState,
      builder: (context, snapshot) {
        final conn =
            (snapshot.data ?? widget.sdk.runtimeState).connectionState;
        final isActive =
            conn == SDKConnectConnectionState.connecting ||
            conn == SDKConnectConnectionState.connected ||
            conn == SDKConnectConnectionState.reconnecting;

        if (isActive) {
          return RemoteVideoCallWidget(
            sdk: widget.sdk,
            title: 'Video Call',
            callbacks: SDKConnectWidgetCallbacks(
              onCallStateChanged: _onCallStateChanged,
              onReconnect: _onReconnect,
              onDisconnected: _onDisconnected,
              onEnded: _onEnded,
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Video Call')),
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

// ── Pre-call body ─────────────────────────────────────────────────────────────

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
        const Icon(Icons.videocam, size: 52),
        const SizedBox(height: 12),
        Text(
          _label,
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Peer: $peerId',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        if (signalingState == _SignalingState.dialing ||
            signalingState == _SignalingState.ringing)
          const CircularProgressIndicator()
        else
          FilledButton.icon(
            onPressed: onDial,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Start Video Call'),
          ),
      ],
    );
  }

  String get _label => switch (signalingState) {
        _SignalingState.idle => 'Video call with SDKConnect',
        _SignalingState.dialing => 'Dialing…',
        _SignalingState.ringing => 'Ringing…',
        _SignalingState.rejected => 'Call rejected — try again',
      };
}
