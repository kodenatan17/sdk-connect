import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk/voice_call_sdk.dart';

void main() {
  const validCredentials = VoiceCallCredentials(
    roomUrl: 'wss://room.test',
    token: 'header.payload.signature',
  );

  test('VoiceCallSdk starts media session and emits connecting/connected events', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final connectionEvents = <VoiceCallConnectionEventType>[];
    final tokenEvents = <VoiceCallTokenEventType>[];

    final sdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: engine,
      tokenProvider: (_) async => validCredentials,
      callbacks: VoiceCallCallbacks(
        onConnection: (event) => connectionEvents.add(event.type),
        onToken: (event) => tokenEvents.add(event.type),
      ),
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-1');
    await Future<void>.delayed(Duration.zero);

    expect(media.connectCount, 1);
    expect(engine.state.phase, CallPhase.connected);
    expect(connectionEvents, contains(VoiceCallConnectionEventType.connecting));
    expect(connectionEvents, contains(VoiceCallConnectionEventType.connected));
    expect(tokenEvents, contains(VoiceCallTokenEventType.requested));
    expect(tokenEvents, contains(VoiceCallTokenEventType.resolved));

    await sdk.dispose();
    await engine.dispose();
  });

  test('VoiceCallSdk accept/reject throw after signaling decoupling', () async {
    final sdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: CallEngine(mediaEngine: _FakeMediaEngine(), logger: _InMemoryLogger()),
      tokenProvider: (_) async => validCredentials,
    );

    await expectLater(() => sdk.acceptCall(), throwsA(isA<CallLifecycleException>()));
    await expectLater(() => sdk.rejectCall(), throwsA(isA<CallLifecycleException>()));

    await sdk.dispose();
  });

  test('VoiceCallSdk forwards p2p limit as user event', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final userEvents = <VoiceCallUserEventType>[];
    final sdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: engine,
      tokenProvider: (_) async => validCredentials,
      callbacks: VoiceCallCallbacks(
        onUser: (event) => userEvents.add(event.type),
      ),
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-2');
    await Future<void>.delayed(Duration.zero);

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.p2pLimitExceeded,
        reason: 'p2p_limit_exceeded',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(userEvents, contains(VoiceCallUserEventType.p2pLimitExceeded));

    await sdk.dispose();
    await engine.dispose();
  });
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

  void emitEvent(MediaEngineEvent event) {
    _eventsController.add(event);
  }
}

class _InMemoryLogger implements StructuredLogger {
  @override
  void log({required String event, required Map<String, Object?> fields}) {}
}
