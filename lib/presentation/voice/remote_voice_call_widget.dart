import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk/sdk_connect_api.dart';

/// Reusable voice-call widget for plug-and-play consumer UI.
///
/// Observer-only: reads [SDKConnect] runtime state and does not own signaling.
///
/// Callback behavior:
/// - [SDKConnectWidgetCallbacks.onCallStateChanged] fires on phase changes.
/// - [SDKConnectWidgetCallbacks.onReconnect] fires once per reconnect entry.
/// - [SDKConnectWidgetCallbacks.onDisconnected]/[SDKConnectWidgetCallbacks.onEnded]
///   fire only for terminal states (disconnected/failed).
///
/// Built-in fallback UI includes participant avatar, status text, and controls.
///
/// Widget phase mapping:
/// - CALLING   → [SDKConnectConnectionState.connecting]
/// - CONNECTED → [SDKConnectConnectionState.connected] | [SDKConnectConnectionState.reconnecting]
/// - ENDED     → [SDKConnectConnectionState.disconnected] | [SDKConnectConnectionState.failed]
class RemoteVoiceCallWidget extends StatefulWidget {
  const RemoteVoiceCallWidget({
    super.key,
    required this.sdk,
    this.title,
    this.callbacks = const SDKConnectWidgetCallbacks(),
  });

  final SDKConnect sdk;
  final String? title;

  /// Lifecycle callbacks for consumer UI integration.
  /// All handlers are optional.
  final SDKConnectWidgetCallbacks callbacks;

  @override
  State<RemoteVoiceCallWidget> createState() => _RemoteVoiceCallWidgetState();
}

class _RemoteVoiceCallWidgetState extends State<RemoteVoiceCallWidget> {
  StreamSubscription<SDKConnectRuntimeState>? _subscription;
  SDKConnectConnectionState? _prevConnectionState;
  SDKConnectWidgetPhase? _prevWidgetPhase;
  bool _hasNotifiedTerminal = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.sdk.runtimeStates.listen(_handleRuntimeState);
    _handleRuntimeState(widget.sdk.runtimeState);
  }

  @override
  void didUpdateWidget(covariant RemoteVoiceCallWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sdk == widget.sdk) {
      return;
    }
    _subscription?.cancel();
    _prevConnectionState = null;
    _prevWidgetPhase = null;
    _hasNotifiedTerminal = false;
    _subscription = widget.sdk.runtimeStates.listen(_handleRuntimeState);
    _handleRuntimeState(widget.sdk.runtimeState);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleRuntimeState(SDKConnectRuntimeState runtime) {
    final conn = runtime.connectionState;
    final phase = SDKConnectWidgetPhase.from(conn);

    // Phase-change notification.
    if (_prevWidgetPhase != phase) {
      _prevWidgetPhase = phase;
      widget.callbacks.onCallStateChanged?.call(phase);
    }

    // Reconnect notification — fires once per reconnecting entry.
    if (conn == SDKConnectConnectionState.reconnecting &&
        _prevConnectionState != SDKConnectConnectionState.reconnecting) {
      widget.callbacks.onReconnect?.call();
    }

    // Terminal state handling — deduplicated.
    final isTerminal =
        conn == SDKConnectConnectionState.disconnected ||
        conn == SDKConnectConnectionState.failed;

    if (isTerminal) {
      if (!_hasNotifiedTerminal) {
        _hasNotifiedTerminal = true;
        widget.callbacks.onDisconnected?.call(runtime.callState.reason);
        widget.callbacks.onEnded?.call(runtime.callState.reason);
      }
    } else {
      _hasNotifiedTerminal = false;
    }

    _prevConnectionState = conn;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      initialData: widget.sdk.runtimeState,
      stream: widget.sdk.runtimeStates,
      builder: (context, snapshot) {
        final runtime = snapshot.data ?? widget.sdk.runtimeState;
        final call = runtime.callState;
        final peerId =
            runtime.participants.remoteParticipantId ??
            call.session?.peerId ??
            'Remote';
        final isConnected =
            runtime.connectionState == SDKConnectConnectionState.connected;
        final isReconnecting =
            runtime.connectionState == SDKConnectConnectionState.reconnecting;
        final isWeakNetwork = runtime.network.isWeak;

        return Scaffold(
          appBar: AppBar(title: Text(widget.title ?? 'Voice Call')),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: <Widget>[
                  _StatusBanner(
                    isReconnecting: isReconnecting,
                    isWeakNetwork: isWeakNetwork,
                  ),
                  const Spacer(),
                  CircleAvatar(
                    radius: 46,
                    backgroundColor: const Color(0xFF1E293B),
                    child: Text(
                      (peerId.isEmpty ? '?' : peerId[0]).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    peerId,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _statusText(runtime),
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Audio route: \${runtime.media.audioRoute.name}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  const Spacer(),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      _ControlChip(
                        icon: runtime.media.localAudioEnabled
                            ? Icons.mic
                            : Icons.mic_off,
                        label: runtime.media.localAudioEnabled
                            ? 'Mute'
                            : 'Unmute',
                        onTap: isConnected || isReconnecting
                            ? widget.sdk.toggleMute
                            : null,
                      ),
                      _ControlChip(
                        icon:
                            runtime.media.audioRoute ==
                                SDKConnectAudioRoute.speaker
                            ? Icons.volume_up
                            : Icons.hearing,
                        label:
                            runtime.media.audioRoute ==
                                SDKConnectAudioRoute.speaker
                            ? 'Speaker Off'
                            : 'Speaker On',
                        onTap: isConnected || isReconnecting
                            ? widget.sdk.toggleSpeaker
                            : null,
                      ),
                      _ControlChip(
                        icon: Icons.call_end,
                        label: 'End',
                        onTap: () =>
                            widget.sdk.endCall(reason: 'ended_by_user'),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _statusText(SDKConnectRuntimeState runtime) {
    if (!runtime.participants.hasRemoteParticipant &&
        runtime.connectionState != SDKConnectConnectionState.idle) {
      return 'Waiting for participant';
    }

    return switch (runtime.connectionState) {
      SDKConnectConnectionState.idle => 'No active call',
      SDKConnectConnectionState.connecting => 'Connecting...',
      SDKConnectConnectionState.connected => 'Connected',
      SDKConnectConnectionState.reconnecting => 'Reconnecting...',
      SDKConnectConnectionState.disconnected =>
        runtime.callState.reason ?? 'Disconnected',
      SDKConnectConnectionState.failed =>
        runtime.callState.reason ?? 'Connection failed',
    };
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.isReconnecting,
    required this.isWeakNetwork,
  });

  final bool isReconnecting;
  final bool isWeakNetwork;

  @override
  Widget build(BuildContext context) {
    if (!isReconnecting && !isWeakNetwork) {
      return const SizedBox(height: 8);
    }

    final color = isReconnecting
        ? const Color(0xFFB45309)
        : const Color(0xFFB91C1C);
    final text = isReconnecting
        ? 'Reconnecting…'
        : 'Weak network, prioritizing audio';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _ControlChip extends StatelessWidget {
  const _ControlChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.backgroundColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Future<void> Function()? onTap;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
      ),
      onPressed: onTap == null ? null : () => onTap!.call(),
      icon: Icon(icon),
      label: Text(label),
    );
  }
}
