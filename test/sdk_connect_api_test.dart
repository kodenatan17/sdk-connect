import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk_connect.dart';

void main() {
  const validCredentials = SDKConnectCredentials(
    roomUrl: 'wss://room.test',
    token: 'header.payload.signature',
  );

  test('SDKConnect forwards media lifecycle and token events', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final eventKinds = <SDKConnectEventKind>[];
    final connectionEvents = <SDKConnectConnectionEventType>[];

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      tokenProvider: (_) async => validCredentials,
      callbacks: SDKConnectCallbacks(
        onEvent: (event) => eventKinds.add(event.kind),
        onConnection: (event) => connectionEvents.add(event.type),
      ),
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-1');
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.connected);
    expect(connectionEvents, contains(SDKConnectConnectionEventType.connecting));
    expect(connectionEvents, contains(SDKConnectConnectionEventType.connected));
    expect(eventKinds, contains(SDKConnectEventKind.connection));
    expect(eventKinds, contains(SDKConnectEventKind.token));

    await sdk.endCall();
    expect(engine.state.phase, CallPhase.idle);

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect video start enables camera', () async {
    final media = _FakeMediaEngine();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      tokenProvider: (_) async => validCredentials,
    );

    await sdk.video.startCall(peerId: 'user-b');

    expect(engine.state.phase, CallPhase.connected);
    expect(engine.state.isVideoEnabled, isTrue);
    expect(media.isVideoEnabled, isTrue);

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect no longer owns accept/reject lifecycle', () async {
    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: CallEngine(mediaEngine: _FakeMediaEngine(), logger: _InMemoryLogger()),
      tokenProvider: (_) async => validCredentials,
    );

    await expectLater(() => sdk.acceptCall(), throwsA(isA<StateError>()));
    await expectLater(() => sdk.rejectCall(), throwsA(isA<StateError>()));

    await sdk.dispose();
  });

  test('CallEngine rejects expired JWT token', () async {
    final engine = CallEngine(
      mediaEngine: _FakeMediaEngine(),
      logger: _InMemoryLogger(),
    );

    final pastExp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) - 3600;
    final payload = base64Url.encode(utf8.encode('{"exp":$pastExp}'));
    final expiredToken = 'header.$payload.signature';

    await expectLater(
      () => engine.connectSession(
        callId: 'c1',
        peerId: 'p',
        roomUrl: 'wss://room.test',
        token: expiredToken,
      ),
      throwsA(isA<CallLifecycleException>()),
    );

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
}

class _InMemoryLogger implements StructuredLogger {
  @override
  void log({required String event, required Map<String, Object?> fields}) {}
}
