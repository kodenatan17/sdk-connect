import 'package:flutter/material.dart';

class RemoteVideo extends StatelessWidget {
  const RemoteVideo({
    super.key,
    this.child,
    this.placeholder,
    this.fit = BoxFit.cover,
  });

  final Widget? child;
  final Widget? placeholder;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final content = child ??
        placeholder ??
        const ColoredBox(
          color: Color(0xFF10131A),
          child: Center(
            child: Icon(
              Icons.person,
              color: Color(0x80FFFFFF),
              size: 64,
            ),
          ),
        );

    return DecoratedBox(
      decoration: const BoxDecoration(color: Colors.black),
      child: FittedBox(
        fit: fit,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: 1080,
          height: 1920,
          child: content,
        ),
      ),
    );
  }
}

class LocalVideo extends StatelessWidget {
  const LocalVideo({
    super.key,
    this.child,
    this.placeholder,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  final Widget? child;
  final Widget? placeholder;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final content = child ??
        placeholder ??
        const ColoredBox(
          color: Color(0xFF1B202B),
          child: Center(
            child: Icon(
              Icons.videocam,
              color: Color(0x99FFFFFF),
              size: 22,
            ),
          ),
        );

    return ClipRRect(
      borderRadius: borderRadius,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Color(0xFF1B202B),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}

class VideoCallLayout extends StatelessWidget {
  const VideoCallLayout({
    super.key,
    required this.remoteVideo,
    required this.localVideo,
    this.previewSize = const Size(112, 168),
    this.previewAlignment = Alignment.topRight,
    this.previewMargin = const EdgeInsets.only(top: 16, right: 12),
    this.showLocalPreview = true,
  });

  final Widget remoteVideo;
  final Widget localVideo;
  final Size previewSize;
  final Alignment previewAlignment;
  final EdgeInsets previewMargin;
  final bool showLocalPreview;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        Positioned.fill(child: remoteVideo),
        if (showLocalPreview)
          Align(
            alignment: previewAlignment,
            child: Container(
              margin: previewMargin,
              width: previewSize.width,
              height: previewSize.height,
              child: localVideo,
            ),
          ),
      ],
    );
  }
}
