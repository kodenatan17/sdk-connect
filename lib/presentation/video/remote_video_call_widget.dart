import 'package:flutter/material.dart';
import 'package:sdk_connect/presentation/video/video_call_widgets.dart';
import 'package:sdk_connect/sdk/sdk_connect_api.dart';

class RemoteVideoCallWidget extends StatelessWidget {
  const RemoteVideoCallWidget({
    super.key,
    required this.sdk,
    this.remoteVideo,
    this.localVideo,
    this.title,
  });

  final SDKConnect sdk;
  final Widget? remoteVideo;
  final Widget? localVideo;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      initialData: sdk.runtimeState,
      stream: sdk.runtimeStates,
      builder: (context, snapshot) {
        final runtime = snapshot.data ?? sdk.runtimeState;
        final isConnected = runtime.connectionState == SDKConnectConnectionState.connected;
        final isReconnecting =
            runtime.connectionState == SDKConnectConnectionState.reconnecting;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: Text(title ?? 'Video Call'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Picture in Picture',
                onPressed: () => sdk.video.enterPictureInPicture(),
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
                        ? remoteVideo
                        : _VideoPlaceholder(
                            title: runtime.participants.remoteParticipantId ?? 'Remote participant',
                            subtitle: runtime.participants.hasRemoteParticipant
                                ? 'Camera off'
                                : 'Waiting for participant',
                          ),
                  ),
                  localVideo: LocalVideo(
                    child: runtime.media.localVideoEnabled
                        ? localVideo
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
                      isReconnecting ? 'Reconnecting…' : 'Weak network, reducing video quality',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
                        onTap: isConnected || isReconnecting ? sdk.toggleMute : null,
                      ),
                      _ControlCircle(
                        icon: runtime.media.audioRoute == SDKConnectAudioRoute.speaker
                            ? Icons.volume_up
                            : Icons.hearing,
                        onTap: isConnected || isReconnecting ? sdk.toggleSpeaker : null,
                      ),
                      _ControlCircle(
                        icon: runtime.media.localVideoEnabled
                            ? Icons.videocam
                            : Icons.videocam_off,
                        onTap: isConnected || isReconnecting ? sdk.video.toggleCamera : null,
                      ),
                      _ControlCircle(
                        icon: Icons.call_end,
                        backgroundColor: Colors.red,
                        onTap: () => sdk.endCall(reason: 'ended_by_user'),
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
