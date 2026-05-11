import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/di/sdk_connect_scope.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk_connect.dart';

void main() {
  const validToken = 'header.payload.signature';

  test('connect session transitions idle -> connecting -> connected -> disconnected -> idle', () async {
    final media = _FakeMediaEngine();
    final logger = _InMemoryLogger();
    final engine = CallEngine(mediaEngine: media, logger: logger);

    await engine.connectSession(
      callId: 'call-1',
      peerId: 'peer-1',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(engine.state.phase, CallPhase.connected);
    expect(media.connectCount, 1);

    await engine.endCall();

    expect(engine.state.phase, CallPhase.idle);
    expect(media.disconnectCount, 1);
    expect(logger.events, contains('call.connect_session'));
    expect(logger.events, contains('call.disconnected'));

    await engine.dispose();
  });

  test('single active call is enforced while connected', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    await engine.connectSession(
      callId: 'call-2',
      peerId: 'peer-2',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    await expectLater(
      () => engine.connectSession(
        callId: 'call-3',
        peerId: 'peer-3',
        roomUrl: 'wss://room.test',
        token: validToken,
      ),
      throwsA(isA<CallLifecycleException>()),
    );

    await engine.dispose();
  });

  test('connect failure transitions to failed', () async {
    final media = _FakeMediaEngine(throwOnConnect: true);
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    await expectLater(
      () => engine.connectSession(
        callId: 'call-f1',
        peerId: 'peer-f1',
        roomUrl: 'wss://room.test',
        token: validToken,
      ),
      throwsA(isA<StateError>()),
    );

    expect(engine.state.phase, CallPhase.failed);
    expect(engine.state.reason, 'connect_failed');

    await engine.endCall();
    expect(engine.state.phase, CallPhase.idle);
    await engine.dispose();
  });

  test('p2p-only media rejection transitions to failed', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    await engine.connectSession(
      callId: 'call-p2p',
      peerId: 'peer-p2p',
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

    expect(engine.state.phase, CallPhase.disconnected);
    await engine.dispose();
  });

  test('auto reconnect recovers before grace timeout', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(
      mediaEngine: media,
      logger: _InMemoryLogger(),
      reconnectPolicy: const CallReconnectPolicy(
        maxAttempts: 3,
        initialDelay: Duration(milliseconds: 20),
        maxDelay: Duration(milliseconds: 40),
        graceTimeout: Duration(milliseconds: 220),
      ),
    );

    await engine.connectSession(
      callId: 'call-r1',
      peerId: 'peer-r1',
      roomUrl: 'wss://room.test',
      token: validToken,
    );
    media.connectFailuresBeforeSuccess = 1;

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.disconnected,
        reason: 'network_drop',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 140));
    expect(engine.state.phase, CallPhase.connected);
    expect(engine.state.isReconnecting, isFalse);

    await engine.dispose();
  });

  test('silent token refresh is deduplicated during reconnect storms', () async {
    final media = _FakeMediaEngine();
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiringToken = _jwtWithExp(nowSec + 20);
    final refreshedToken = _jwtWithExp(nowSec + 3600);
    var refreshCalls = 0;

    final completer = Completer<String>();
    final engine = CallEngine(
      mediaEngine: media,
      logger: _InMemoryLogger(),
      reconnectPolicy: const CallReconnectPolicy(
        initialDelay: Duration(milliseconds: 10),
        maxDelay: Duration(milliseconds: 20),
        graceTimeout: Duration(milliseconds: 260),
        tokenRefreshBeforeExpiry: Duration(minutes: 2),
      ),
      tokenRefresher: (_, __) {
        refreshCalls += 1;
        return completer.future;
      },
    );

    await engine.connectSession(
      callId: 'call-r2',
      peerId: 'peer-r2',
      roomUrl: 'wss://room.test',
      token: expiringToken,
    );

    media.connectFailuresBeforeSuccess = 1;
    media.emitEvent(const MediaEngineEvent(type: MediaEngineEventType.disconnected));
    media.emitEvent(const MediaEngineEvent(type: MediaEngineEventType.disconnected));

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(refreshCalls, 1);

    completer.complete(refreshedToken);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(refreshCalls, 1);
    expect(media.updatedTokens, contains(refreshedToken));

    await engine.dispose();
  });

  test('scope composes shared call engine for controller init', () async {
    final media = _FakeMediaEngine();
    final scope = SdkConnectScope.liveKit(mediaEngine: media);
    final controller = scope.createVoiceCallController();

    await controller.startOutgoing(
      callId: 'call-13',
      peerId: 'peer-13',
      roomUrl: 'wss://room.test',
      token: validToken,
    );

    expect(scope.callEngine.state.phase, CallPhase.connected);
    expect(media.connectCount, 1);

    controller.dispose();
    await scope.dispose();
  });
}

class _FakeMediaEngine implements MediaEngine {
  _FakeMediaEngine({
    this.throwOnConnect = false,
    this.connectFailuresBeforeSuccess = 0,
  });

  final bool throwOnConnect;
  int connectFailuresBeforeSuccess;

  int connectCount = 0;
  int disconnectCount = 0;
  bool _connected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = false;
  final List<String> updatedTokens = <String>[];
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
    if (throwOnConnect) {
      throw StateError('connect failed');
    }
    if (connectFailuresBeforeSuccess > 0) {
      connectFailuresBeforeSuccess -= 1;
      throw StateError('connect failed temporarily');
    }
    _connected = true;
  }

  @override
  Future<void> disconnect() async {
    disconnectCount += 1;
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
  Future<void> updateToken(String token) async {
    updatedTokens.add(token);
  }

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

String _jwtWithExp(int exp) {
  final payload = base64Url.encode(utf8.encode('{"exp":$exp}'));
  return 'header.$payload.signature';
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
