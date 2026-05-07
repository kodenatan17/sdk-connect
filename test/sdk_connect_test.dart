import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sdk_connect/sdk_connect.dart';

void main() {
  const validToken = 'header.payload.signature';

  test('outgoing lifecycle transitions stay consistent', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await engine.startOutgoing(
      callId: 'call-1',
      peerId: 'peer-1',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(engine.state.phase, CallPhase.dialing);
    expect(media.connectCount, 1);

    engine.markOutgoingConnected();
    expect(engine.state.phase, CallPhase.connected);

    await engine.endCall();

    expect(engine.state.phase, CallPhase.idle);
    expect(media.disconnectCount, 1);
    expect(logger.events, contains('call.start_outgoing'));
    expect(logger.events, contains('call.ended'));
    expect(logger.events, contains('end_cleanup'));

    await engine.dispose();
  });

  test('incoming accept and reject follow valid transitions', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    engine.onIncoming(callId: 'call-2', peerId: 'peer-2');
    expect(engine.state.phase, CallPhase.ringing);

    await engine.acceptIncoming(roomUrl: 'wss://room.test', token: validToken);
    expect(engine.state.phase, CallPhase.connected);

    await engine.setMuted(true);
    await engine.setSpeakerOn(true);
    expect(engine.state.isMuted, isTrue);
    expect(engine.state.isSpeakerOn, isTrue);
    expect(media.muteUpdates, 1);
    expect(media.speakerUpdates, 1);

    await engine.endCall(reason: 'hangup');
    expect(engine.state.phase, CallPhase.idle);
    expect(engine.state.isMuted, isFalse);
    expect(engine.state.isSpeakerOn, isFalse);

    engine.onIncoming(callId: 'call-3', peerId: 'peer-3');
    await engine.rejectIncoming(reason: 'busy');

    expect(engine.state.phase, CallPhase.idle);
    expect(logger.events, contains('call.incoming'));
    expect(logger.events, contains('call.accepted'));
    expect(logger.events, contains('call.rejected'));

    await engine.dispose();
  });

  test('single active call is enforced', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await engine.startOutgoing(
      callId: 'call-4',
      peerId: 'peer-4',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(
      () => engine.onIncoming(callId: 'call-5', peerId: 'peer-5'),
      throwsA(isA<CallLifecycleException>()),
    );

    expect(
      () => engine.startOutgoing(
        callId: 'call-6',
        peerId: 'peer-6',
        roomUrl: 'wss://room.test',
        token: validToken,
      ),
      throwsA(isA<CallLifecycleException>()),
    );

    expect(logger.events, contains('call.lifecycle_violation'));

    await engine.dispose();
  });

  test('connect failure transitions back to idle with logs', () async {
    final media = _FakeMediaEngine(throwOnConnect: true);
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await expectLater(
      () => engine.startOutgoing(
        callId: 'call-7',
        peerId: 'peer-7',
        roomUrl: 'wss://room.test',
        token: validToken,
      ),
      throwsA(isA<StateError>()),
    );

    expect(engine.state.phase, CallPhase.idle);
    expect(logger.events, contains('call.connect_failed'));
    expect(logger.events, contains('connect_failure_cleanup'));

    await engine.dispose();
  });

  test('disconnect failure still resets call to idle', () async {
    final media = _FakeMediaEngine(throwOnDisconnect: true);
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await engine.startOutgoing(
      callId: 'call-8',
      peerId: 'peer-8',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    await engine.endCall();

    expect(engine.state.phase, CallPhase.idle);
    expect(logger.events, contains('media.disconnect_failed'));

    await engine.dispose();
  });

  test('invalid token is rejected before media connect', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await expectLater(
      () => engine.startOutgoing(
        callId: 'call-9',
        peerId: 'peer-9',
        roomUrl: 'wss://room.test',
        token: 'invalid-token',
      ),
      throwsA(isA<CallLifecycleException>()),
    );

    expect(media.connectCount, 0);
    expect(engine.state.phase, CallPhase.idle);

    await engine.dispose();
  });

  test('p2p-only media rejection resets state to idle', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await engine.startOutgoing(
      callId: 'call-10',
      peerId: 'peer-10',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.p2pLimitExceeded,
        reason: 'p2p_limit_exceeded',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.idle);
    expect(logger.events, contains('call.p2p_limit_exceeded'));
    expect(logger.events, contains('p2p_limit_cleanup'));

    await engine.dispose();
  });

  test('unexpected media disconnect resets active call to idle', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await engine.startOutgoing(
      callId: 'call-11',
      peerId: 'peer-11',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.disconnected,
        reason: 'network_lost',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.idle);
    expect(logger.events, contains('call.media_disconnected'));
    expect(logger.events, contains('media_disconnect_cleanup'));

    await engine.dispose();
  });

  test('dispose is idempotent and blocks further transitions', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    await engine.dispose();
    await engine.dispose();

    expect(
      () => engine.onIncoming(callId: 'call-12', peerId: 'peer-12'),
      throwsA(isA<CallLifecycleException>()),
    );

    expect(
      () => engine.markOutgoingConnected(),
      throwsA(isA<CallLifecycleException>()),
    );

    expect(media.disconnectCount, 0);
  });

  test('sdk scope composes a shared call engine for controller init', () async {
    final media = _FakeMediaEngine();
    final scope = SdkConnectScope.liveKit(mediaEngine: media);
    final controller = scope.createVoiceCallController();

    await controller.startOutgoing(
      callId: 'call-13',
      peerId: 'peer-13',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(scope.callEngine.state.phase, CallPhase.dialing);
    expect(media.connectCount, 1);

    controller.dispose();
    await scope.dispose();
  });
}

class _FakeMediaEngine implements MediaEngine {
  _FakeMediaEngine({
    this.throwOnConnect = false,
    this.throwOnDisconnect = false,
  });

  final bool throwOnConnect;
  final bool throwOnDisconnect;

  int connectCount = 0;
  int disconnectCount = 0;
  int muteUpdates = 0;
  int speakerUpdates = 0;
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
    if (throwOnConnect) {
      throw StateError('connect failed');
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
    if (throwOnDisconnect) {
      throw StateError('disconnect failed');
    }
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
  }

  @override
  Future<void> setMuted(bool muted) async {
    muteUpdates += 1;
    _isMuted = muted;
  }

  @override
  Future<void> setSpeakerOn(bool speakerOn) async {
    speakerUpdates += 1;
    _isSpeakerOn = speakerOn;
  }

  @override
  Future<void> dispose() async {
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
    await _eventsController.close();
  }

  void emitEvent(MediaEngineEvent event) {
    _eventsController.add(event);
  }
}

class _InMemoryLogger implements StructuredLogger {
  final List<Map<String, Object?>> entries = <Map<String, Object?>>[];

  List<String> get events {
    return entries
        .map((entry) => entry['event'])
        .whereType<String>()
        .toList(growable: false);
  }

  @override
  void log({required String event, required Map<String, Object?> fields}) {
    entries.add(<String, Object?>{'event': event, ...fields});
  }
}
