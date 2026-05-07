import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/sdk_connect.dart';

void main() {
  const validToken = 'header.payload.signature';

  test('controller maps lifecycle states to simple UI modes', () async {
    final engine = CallEngine(
      mediaEngine: _FakeMediaEngine(),
      logger: _InMemoryLogger(),
    );
    final controller = VoiceCallController(engine: engine);

    expect(controller.uiState.mode, VoiceCallUiMode.idle);
    expect(controller.uiState.title, 'No active call');

    engine.onIncoming(callId: 'call-1', peerId: 'peer-a');
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.mode, VoiceCallUiMode.incoming);
    expect(controller.uiState.showAccept, isTrue);
    expect(controller.uiState.showReject, isTrue);

    await controller.acceptIncoming(
      roomUrl: 'wss://room.test',
      token: validToken,
    );
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.mode, VoiceCallUiMode.inCall);
    expect(controller.uiState.controlsEnabled, isTrue);

    await controller.endCall();
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.mode, VoiceCallUiMode.idle);

    controller.dispose();
    await engine.dispose();
  });

  test('controller actions wire to engine and enforce control phase', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());
    final controller = VoiceCallController(engine: engine);

    await controller.toggleMute();
    await controller.toggleSpeaker();
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.isMuted, isFalse);
    expect(controller.uiState.isSpeakerOn, isFalse);

    await controller.startOutgoing(
      callId: 'call-2',
      peerId: 'peer-b',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(engine.state.phase, CallPhase.dialing);
    expect(media.connectCount, 1);

    controller.markOutgoingConnected();
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.mode, VoiceCallUiMode.inCall);

    await controller.endCall();
    expect(engine.state.phase, CallPhase.idle);

    engine.onIncoming(callId: 'call-3', peerId: 'peer-c');
    await controller.acceptIncoming(roomUrl: 'wss://room.test', token: validToken);
    await Future<void>.delayed(Duration.zero);

    await controller.toggleMute();
    await controller.toggleSpeaker();
    await Future<void>.delayed(Duration.zero);
    expect(controller.uiState.isMuted, isTrue);
    expect(controller.uiState.isSpeakerOn, isTrue);

    await controller.endCall();
    expect(engine.state.phase, CallPhase.idle);
    expect(controller.uiState.isMuted, isFalse);
    expect(controller.uiState.isSpeakerOn, isFalse);

    engine.onIncoming(callId: 'call-4', peerId: 'peer-d');
    await Future<void>.delayed(Duration.zero);
    await controller.rejectIncoming(reason: 'not_allowed_now');
    expect(engine.state.phase, CallPhase.idle);

    controller.dispose();
    await engine.dispose();
  });

  testWidgets(
    'voice screen renders incoming and in-call controls',
    (tester) async {
    final engine = CallEngine(
      mediaEngine: _FakeMediaEngine(),
      logger: _InMemoryLogger(),
    );
    final controller = VoiceCallController(engine: engine);

    Future<void> onAccept() {
      return controller.acceptIncoming(
        roomUrl: 'wss://room.test',
        token: validToken,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: VoiceCallScreen(
          controller: controller,
          onAccept: onAccept,
          onReject: () => controller.rejectIncoming(),
          onEnd: () => controller.endCall(),
        ),
      ),
    );

    engine.onIncoming(callId: 'call-4', peerId: 'peer-d');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Incoming call'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Reject'), findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

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
  int disconnectCount = 0;
  bool _connected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
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
  Future<void> connect({required String roomUrl, required String token}) async {
    connectCount += 1;
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
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
  Future<void> dispose() async {
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
    await _eventsController.close();
  }
}

class _InMemoryLogger implements StructuredLogger {
  @override
  void log({required String event, required Map<String, Object?> fields}) {}
}