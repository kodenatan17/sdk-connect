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

    await engine.endCall(reason: 'hangup');
    expect(engine.state.phase, CallPhase.idle);

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
  bool _connected = false;

  @override
  bool get isConnected => _connected;

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
