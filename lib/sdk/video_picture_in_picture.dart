import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoPictureInPictureConfig {
  const VideoPictureInPictureConfig({
    this.aspectRatio = 9 / 16,
    this.sourceRectHint,
  });

  final double aspectRatio;
  final Rect? sourceRectHint;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'aspectRatio': aspectRatio,
      'sourceRectHint': sourceRectHint == null
          ? null
          : <String, double>{
              'left': sourceRectHint!.left,
              'top': sourceRectHint!.top,
              'right': sourceRectHint!.right,
              'bottom': sourceRectHint!.bottom,
            },
    };
  }
}

abstract class VideoPictureInPictureController {
  bool get isSupported;
  Stream<bool> get state;
  bool get isEnabled;

  Future<bool> enable({VideoPictureInPictureConfig config = const VideoPictureInPictureConfig()});
  Future<bool> disable();
  Future<void> dispose();
}

class MethodChannelVideoPictureInPictureController
    implements VideoPictureInPictureController {
  MethodChannelVideoPictureInPictureController({
    MethodChannel? channel,
  }) : _channel = channel ?? const MethodChannel('sdk_connect/video_pip');

  final MethodChannel _channel;
  final StreamController<bool> _stateController =
      StreamController<bool>.broadcast();

  bool _enabled = false;
  bool _disposed = false;

  @override
  bool get isSupported {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  Stream<bool> get state => _stateController.stream;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<bool> enable({
    VideoPictureInPictureConfig config = const VideoPictureInPictureConfig(),
  }) async {
    if (_disposed || !isSupported) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>(
        'enterPiP',
        config.toMap(),
      );
      _enabled = result ?? false;
    } on MissingPluginException {
      _enabled = false;
    } on PlatformException {
      _enabled = false;
    }

    _emitState();
    return _enabled;
  }

  @override
  Future<bool> disable() async {
    if (_disposed || !isSupported) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<bool>('exitPiP');
      _enabled = !(result ?? true);
    } on MissingPluginException {
      _enabled = false;
    } on PlatformException {
      _enabled = false;
    }

    _emitState();
    return !_enabled;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _stateController.close();
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_enabled);
    }
  }
}

class NoopVideoPictureInPictureController
    implements VideoPictureInPictureController {
  NoopVideoPictureInPictureController();

  final StreamController<bool> _stateController =
      StreamController<bool>.broadcast();

  bool _disposed = false;

  @override
  bool get isSupported => false;

  @override
  Stream<bool> get state => _stateController.stream;

  @override
  bool get isEnabled => false;

  @override
  Future<bool> enable({
    VideoPictureInPictureConfig config = const VideoPictureInPictureConfig(),
  }) async {
    return false;
  }

  @override
  Future<bool> disable() async {
    return false;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }

    _disposed = true;
    await _stateController.close();
  }
}
