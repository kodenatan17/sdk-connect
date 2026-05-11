import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sdk_connect/presentation/video/video_call_widgets.dart';
import 'package:sdk_connect/sdk/sdk_connect_api.dart';

/// Reusable video-call widget for consumer UI integration.
///
/// Consumes [SDKConnect] runtime state exclusively — it owns no signaling or
/// reconnect logic. Supply [callbacks] to react to lifecycle transitions.
///
/// Widget phase mapping:
/// - CALLING   → [SDKConnectConnectionState.connecting]
/// - CONNECTED → [SDKConnectConnectionState.connected] | [SDKConnectConnectionState.reconnecting]
/// - ENDED     → [SDKConnectConnectionState.disconnected] | [SDKConnectConnectionState.failed]
class RemoteVideoCallWidget extends StatefulWidget {
  const RemoteVideoCallWidget({
    super.key,
    required this.sdk,
    this.remoteVideo,
    this.localVideo,
    this.title,
    this.callbacks = const SDKConnectWidgetCallbacks(),
  });

  final SDKConnect sdk;
  final Widget? remoteVideo;
  final Widget? localVideo;
  final String? title;

  /// Lifecycle callbacks for consumer UI integration.
  /// All handlers are optional.
  final SDKConnectWidgetCallbacks callbacks;

  @override
  State<RemoteVideoCallWidget> createState() => _RemoteVideoCallWidgetState();
}

class _RemoteVideoCallWidgetState extends State<RemoteVideoCallWidget> {
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
  void didUpdateWidget(covariant RemoteVideoCallWidget oldWidget) {
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
    final isTerminal = conn == SDKConnectConnectionState.disconnected ||
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
        final isConnected = runtime.connectionState == SDKConnectConnectionState.connected;
        final isReconnecting =
            runtime.connectionState == SDKConnectConnectionState.reconnecting;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(widget.title ?? 'Video Call'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Picture in Picture',
                onPressed: () => widget.sdk.video.enterPictureInPicture(),
                icon: const Icon(Icons.picture_in_picture_alt),
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: VideoCallLayout(
                  remoteVideo: RemoteVideo(
                    child: runtime.media.remoteVideoEnabled
                        ? widget.remoteVideo
                        : _VideoPlaceholder(
                            title: runtime.participants.remoteParticipantId ??
                                'Remote participant',
                            subtitle: runtime.participants.hasRemoteParticipant
                                ? 'Camera off'
                                : 'Waiting for participant',
                          ),
                  ),
                  localVideo: LocalVideo(
                    child: runtime.media.localVideoEnabled
                        ? widget.localVideo
                        : const _VideoPlaceholder(
                            title: 'You',
                            subtitle: 'Camera off',
                          ),
                  ),
                  showLocalPreview: true,
                ),
              ),
              if (isReconnecting || runtime.network.isWeak)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isReconnecting
                          ? const Color(0xCCB45309)
                          : const Color(0xCCB91C1C),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isReconnecting
                          ? 'Reconnecting…'
                          : 'Weak network, reducing video quality',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  minimum: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      _ControlCircle(
                        icon: runtime.media.localAudioEnabled ? Icons.mic : Icons.mic_off,
                        onTap: isConnected || isReconnecting
                            ? widget.sdk.toggleMute
                            : null,
                      ),
                      _ControlCircle(
                        icon: runtime.media.audioRoute == SDKConnectAudioRoute.speaker
                            ? Icons.volume_up
                            : Icons.hearing,
                        onTap: isConnected || isReconnecting
                            ? widget.sdk.toggleSpeaker
                            : null,
                      ),
                      _ControlCircle(
                        icon: runtime.media.localVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        onTap: isConnected || isReconnecting
                            ? widget.sdk.video.toggleCamera
                            : null,
                      ),
                      _ControlCircle(
                        icon: Icons.call_end,
                        backgroundColor: Colors.red,
                        onTap: () => widget.sdk.endCall(reason: 'ended_by_user'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF0F172A),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFFCBD5E1)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ControlCircle extends StatelessWidget {
  const _ControlCircle({
    required this.icon,
    required this.onTap,
    this.backgroundColor,
  });

  final IconData icon;
  final Future<void> Function()? onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    return IconButton.filled(
      style: IconButton.styleFrom(
        backgroundColor: backgroundColor ?? const Color(0xCC1E293B),
      ),
      onPressed: onTap == null ? null : () => onTap!.call(),
      icon: Icon(icon),
    );
  }
}
