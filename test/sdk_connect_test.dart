import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:sdk_connect/sdk_connect.dart';
import 'package:sdk_connect/di/sdk_connect_scope.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';

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
    final engine = CallEngine(
      mediaEngine: media,
      logger: logger,
      reconnectPolicy: const CallReconnectPolicy(enabled: false),
    );

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

  test('auto reconnect recovers call state before grace timeout', () async {
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
    final events = <CallEngineEventType>[];
    final sub = engine.events.listen((event) => events.add(event.type));

    await engine.startOutgoing(
      callId: 'call-r1',
      peerId: 'peer-r1',
      roomUrl: 'wss://room.test',
      token: validToken,
    );
    engine.markOutgoingConnected();
    media.connectFailuresBeforeSuccess = 1;

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.disconnected,
        reason: 'network_drop',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.state.phase, CallPhase.connected);
    expect(engine.state.reconnectAttempts, greaterThanOrEqualTo(1));

    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(engine.state.phase, CallPhase.connected);
    expect(engine.state.isReconnecting, isFalse);
    expect(engine.state.session?.callId, 'call-r1');
    expect(events, contains(CallEngineEventType.reconnecting));
    expect(events, contains(CallEngineEventType.recovered));

    await sub.cancel();
    await engine.dispose();
  });

  test('reconnect loop prevention ends call if disconnect repeats inside cooldown', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(
      mediaEngine: media,
      logger: _InMemoryLogger(),
      reconnectPolicy: const CallReconnectPolicy(
        maxAttempts: 2,
        initialDelay: Duration(milliseconds: 10),
        maxDelay: Duration(milliseconds: 20),
        graceTimeout: Duration(milliseconds: 120),
        reconnectCooldown: Duration(milliseconds: 600),
      ),
    );

    await engine.startOutgoing(
      callId: 'call-r2',
      peerId: 'peer-r2',
      roomUrl: 'wss://room.test',
      token: validToken,
    );
    engine.markOutgoingConnected();

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.disconnected,
        reason: 'network_drop_1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(engine.state.phase, CallPhase.connected);

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.disconnected,
        reason: 'network_drop_2',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(engine.state.phase, CallPhase.idle);

    await engine.dispose();
  });

  test('silent token refresh happens during reconnect without leaking token', () async {
    final media = _FakeMediaEngine();
    final nowSec = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    final expiringToken = _jwtWithExp(nowSec + 20);
    final refreshedToken = _jwtWithExp(nowSec + 3600);
    var refreshCalls = 0;

    final engine = CallEngine(
      mediaEngine: media,
      logger: _InMemoryLogger(),
      reconnectPolicy: const CallReconnectPolicy(
        initialDelay: Duration(milliseconds: 10),
        maxDelay: Duration(milliseconds: 20),
        graceTimeout: Duration(milliseconds: 200),
        tokenRefreshBeforeExpiry: Duration(minutes: 2),
      ),
      tokenRefresher: (session, reconnectAttempt) async {
        refreshCalls += 1;
        return refreshedToken;
      },
    );
    final events = <CallEngineEventType>[];
    final sub = engine.events.listen((event) => events.add(event.type));

    await engine.startOutgoing(
      callId: 'call-r3',
      peerId: 'peer-r3',
      roomUrl: 'wss://room.test',
      token: expiringToken,
    );
    engine.markOutgoingConnected();
    media.connectFailuresBeforeSuccess = 1;

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.disconnected,
        reason: 'network_drop',
      ),
    );

    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(refreshCalls, 1);
    expect(media.updatedTokens, contains(refreshedToken));
    expect(events, contains(CallEngineEventType.tokenRefreshRequested));
    expect(events, contains(CallEngineEventType.tokenRefreshed));

    await sub.cancel();
    await engine.dispose();
  });

  test('adaptive audio-priority fallback downgrades and recovers on stable network', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(
      mediaEngine: media,
      logger: _InMemoryLogger(),
      networkThresholds: const CallNetworkThresholds(
        weakScore: 30,
        stableScore: 70,
        stableDuration: Duration(milliseconds: 40),
      ),
    );

    await engine.startOutgoing(
      callId: 'call-r4',
      peerId: 'peer-r4',
      roomUrl: 'wss://room.test',
      token: validToken,
      callType: CallType.video,
    );
    engine.markOutgoingConnected();
    await engine.setVideoEnabled(true);

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.networkQualityChanged,
        networkQuality: MediaNetworkQuality(score: 20, bitrateKbps: 120),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(engine.state.isAudioPriority, isTrue);
    expect(engine.state.isVideoEnabled, isFalse);

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.networkQualityChanged,
        networkQuality: MediaNetworkQuality(score: 80, bitrateKbps: 900),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));

    expect(engine.state.isAudioPriority, isFalse);
    expect(engine.state.isVideoEnabled, isTrue);
    expect(media.lastProfile.preferAudio, isFalse);

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
    this.connectFailuresBeforeSuccess = 0,
  });

  final bool throwOnConnect;
  final bool throwOnDisconnect;
  int connectFailuresBeforeSuccess;

  int connectCount = 0;
  int disconnectCount = 0;
  int muteUpdates = 0;
  int speakerUpdates = 0;
  bool _connected = false;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = false;
  int restartIceCount = 0;
  final List<String> updatedTokens = <String>[];
  MediaConnectionProfile lastProfile = MediaConnectionProfile.balanced;
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
    if (throwOnDisconnect) {
      throw StateError('disconnect failed');
    }
    _connected = false;
    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = false;
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
  Future<void> setCameraOn(bool enabled) async {
    _isVideoEnabled = enabled;
  }

  @override
  Future<void> restartIce() async {
    restartIceCount += 1;
  }

  @override
  Future<void> updateToken(String token) async {
    updatedTokens.add(token);
  }

  @override
  Future<void> setConnectionProfile(MediaConnectionProfile profile) async {
    lastProfile = profile;
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
