import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/presentation/voice/voice_call_controller.dart';
import 'package:sdk_connect/presentation/voice/voice_call_screen.dart';

void main() {
  const validToken = 'header.payload.signature';

  test('controller maps media lifecycle to UI modes', () async {
    final engine = CallEngine(
      mediaEngine: _FakeMediaEngine(),
      logger: _InMemoryLogger(),
    );
    final controller = VoiceCallController(engine: engine);

    expect(controller.uiState.mode, VoiceCallUiMode.idle);
    expect(controller.uiState.title, 'No active call');

    await controller.startOutgoing(
      callId: 'call-1',
      peerId: 'peer-a',
      roomUrl: 'wss://room.test',
      token: validToken,
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.connected);
    expect(controller.uiState.mode, VoiceCallUiMode.inCall);
    expect(controller.uiState.controlsEnabled, isTrue);

    await controller.endCall();
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.mode, VoiceCallUiMode.idle);

    controller.dispose();
    await engine.dispose();
  });

  test('controller actions wire to engine controls', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());
    final controller = VoiceCallController(engine: engine);

    await controller.startOutgoing(
      callId: 'call-2',
      peerId: 'peer-b',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(engine.state.phase, CallPhase.connected);
    expect(media.connectCount, 1);

    await controller.toggleMute();
    await controller.toggleSpeaker();
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.isMuted, isTrue);
    expect(controller.uiState.isSpeakerOn, isTrue);

    await controller.endCall();
    expect(engine.state.phase, CallPhase.idle);

    controller.dispose();
    await engine.dispose();
  });

  testWidgets(
    'voice screen renders in-call controls for connected session',
    (tester) async {
      final engine = CallEngine(
        mediaEngine: _FakeMediaEngine(),
        logger: _InMemoryLogger(),
      );
      final controller = VoiceCallController(engine: engine);

      await controller.startOutgoing(
        callId: 'call-3',
        peerId: 'peer-c',
        roomUrl: 'wss://room.test',
        token: validToken,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: VoiceCallScreen(
            controller: controller,
            onEnd: () => controller.endCall(),
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining('In call with'), findsOneWidget);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Speaker'), findsOneWidget);
      expect(find.byTooltip('End'), findsOneWidget);

      controller.dispose();
      await engine.dispose();
    },
    skip: true,
  );
}

class _FakeMediaEngine implements MediaEngine {
  int connectCount = 0;
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
    connectCount += 1;
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
  Future<void> restartIce() async {}

  @override
  Future<void> updateToken(String token) async {}

  @override
  Future<void> setConnectionProfile(MediaConnectionProfile profile) async {
    if (profile.preferAudio) {
      _isVideoEnabled = false;
    }
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
