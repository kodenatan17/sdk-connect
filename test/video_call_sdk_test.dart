import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/core/enums/call_type.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk/video_call_sdk.dart';
import 'package:sdk_connect/sdk/video_picture_in_picture.dart';
import 'package:sdk_connect/sdk/voice_call_sdk.dart';

void main() {
  const validCredentials = VoiceCallCredentials(
    roomUrl: 'wss://room.test',
    token: 'header.payload.signature',
  );

  test('VideoCallSdk enables camera on start call while reusing VoiceCallSdk flow', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final voiceSdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    final pip = _FakePipController();
    final videoSdk = VideoCallSdk(
      voiceSdk: voiceSdk,
      callEngine: engine,
      pictureInPicture: pip,
    );

    await videoSdk.startCall(peerId: 'user-b', callId: 'call-vid-1');

    expect(engine.state.phase, CallPhase.dialing);
    expect(engine.state.session?.callType, CallType.video);
    expect(engine.state.isVideoEnabled, isTrue);
    expect(media.isVideoEnabled, isTrue);
    expect(signaling.sentSignals.single.type, VoiceCallSignalType.invite);
    expect(signaling.sentSignals.single.callType, CallType.video);

    await videoSdk.enterPictureInPicture();
    expect(pip.isEnabled, isTrue);

    await videoSdk.exitPictureInPicture();
    expect(pip.isEnabled, isFalse);

    await videoSdk.dispose();
    await voiceSdk.dispose();
    await engine.dispose();
  });
}

class _FakeSignalingTransport implements VoiceCallSignalingTransport {
  final List<VoiceCallSignal> sentSignals = <VoiceCallSignal>[];
  final StreamController<VoiceCallSignal> _controller =
      StreamController<VoiceCallSignal>.broadcast();

  @override
  Stream<VoiceCallSignal> get signals => _controller.stream;

  @override
  Future<void> send(VoiceCallSignal signal) async {
    sentSignals.add(signal);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}

class _FakeMediaEngine implements MediaEngine {
  bool _connected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = false;
  final StreamController<MediaEngineEvent> _eventsController =
      StreamController<MediaEngineEvent>.broadcast();

  @override
  Stream<MediaEngineEvent> get events => _eventsController.stream;

  @override
  bool get isConnected => _connected;

  @override
  bool get isMuted => _isMuted;

  @override
  bool get isSpeakerOn => _isSpeakerOn;

  @override
  bool get isVideoEnabled => _isVideoEnabled;

  @override
  Future<void> connect({required String roomUrl, required String token}) async {
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = false;
  }

  @override
  Future<void> setMuted(bool muted) async {
    _isMuted = muted;
  }

  @override
  Future<void> setSpeakerOn(bool speakerOn) async {
    _isSpeakerOn = speakerOn;
  }

  @override
  Future<void> setCameraOn(bool enabled) async {
    _isVideoEnabled = enabled;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = false;
    await _eventsController.close();
  }
}

class _InMemoryLogger implements StructuredLogger {
  @override
  void log({required String event, required Map<String, Object?> fields}) {}
}

class _FakePipController implements VideoPictureInPictureController {
  final StreamController<bool> _stateController =
      StreamController<bool>.broadcast();

  bool _enabled = false;

  @override
  bool get isSupported => true;

  @override
  Stream<bool> get state => _stateController.stream;

  @override
  bool get isEnabled => _enabled;

  @override
  Future<bool> enable({
    VideoPictureInPictureConfig config = const VideoPictureInPictureConfig(),
  }) async {
    _enabled = true;
    _stateController.add(_enabled);
    return true;
  }

  @override
  Future<bool> disable() async {
    _enabled = false;
    _stateController.add(_enabled);
    return true;
  }

  @override
  Future<void> dispose() async {
    await _stateController.close();
  }
}
