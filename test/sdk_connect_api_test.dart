import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk_connect.dart';

void main() {
  const validCredentials = SDKConnectCredentials(
    roomUrl: 'wss://room.test',
    token: 'header.payload.signature',
  );

  test('SDKConnect forwards the unified voice lifecycle through callbacks', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final tokenRequests = <SDKConnectTokenRequest>[];
    final observedKinds = <SDKConnectEventKind>[];
    final userEvents = <SDKConnectUserEventType>[];
    final connectionEvents = <SDKConnectConnectionEventType>[];

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (request) async {
        tokenRequests.add(request);
        return validCredentials;
      },
      signalValidator: (_) async => true,
      callbacks: SDKConnectCallbacks(
        onEvent: (event) => observedKinds.add(event.kind),
        onUser: (event) => userEvents.add(event.type),
        onConnection: (event) => connectionEvents.add(event.type),
      ),
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-1');

    expect(media.connectCount, 1);
    expect(engine.state.phase, CallPhase.dialing);
    expect(tokenRequests.single.callType, SDKConnectCallType.voice);
    expect(tokenRequests.single.direction, CallDirection.outgoing);
    expect(signaling.sentSignals.single.type, SDKConnectSignalType.invite);
    expect(connectionEvents, contains(SDKConnectConnectionEventType.ready));
    expect(connectionEvents, contains(SDKConnectConnectionEventType.dialing));

    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.accept,
        callId: 'call-1',
        fromUserId: 'user-b',
        toUserId: 'user-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.connected);

    await sdk.setMuted(true);
    await sdk.setSpeakerOn(true);

    expect(engine.state.isMuted, isTrue);
    expect(engine.state.isSpeakerOn, isTrue);
    expect(userEvents, contains(SDKConnectUserEventType.outgoingStarted));
    expect(userEvents, contains(SDKConnectUserEventType.accepted));
    expect(observedKinds, contains(SDKConnectEventKind.token));
    expect(observedKinds, contains(SDKConnectEventKind.connection));
    expect(observedKinds, contains(SDKConnectEventKind.user));

    await sdk.endCall();

    expect(engine.state.phase, CallPhase.idle);

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect starts a video call and enables camera automatically', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    await sdk.video.startCall(peerId: 'user-b');

    expect(media.isVideoEnabled, isTrue);
    expect(engine.state.isVideoEnabled, isTrue);
    expect(engine.state.phase, CallPhase.dialing);
    expect(signaling.sentSignals.single.callType, SDKConnectCallType.video);

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect exposes split voice facade without video controls', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    await sdk.voice.startCall(peerId: 'user-b', callId: 'call-voice');

    expect(engine.state.phase, CallPhase.dialing);
    expect(engine.state.isVideoEnabled, isFalse);
    expect(signaling.sentSignals.single.callType, SDKConnectCallType.voice);

    await sdk.endCall();
    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect.setVideoEnabled toggles camera on connected call', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-v');
    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.accept,
        callId: 'call-v',
        fromUserId: 'user-b',
        toUserId: 'user-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.connected);
    expect(engine.state.isVideoEnabled, isFalse);

    await sdk.setVideoEnabled(true);
    expect(media.isVideoEnabled, isTrue);
    expect(engine.state.isVideoEnabled, isTrue);

    await sdk.toggleCamera();
    expect(media.isVideoEnabled, isFalse);
    expect(engine.state.isVideoEnabled, isFalse);

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect legacy startCall with callType video remains compatible', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    await sdk.startCall(peerId: 'user-b', callType: SDKConnectCallType.video);

    expect(engine.state.phase, CallPhase.dialing);
    expect(engine.state.isVideoEnabled, isTrue);
    expect(signaling.sentSignals.single.callType, SDKConnectCallType.video);

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect legacy acceptCall resolves incoming video call type from engine state', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.invite,
        callId: 'call-in-video',
        fromUserId: 'user-b',
        toUserId: 'user-a',
        callType: SDKConnectCallType.video,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.ringing);
    expect(engine.state.session?.callType, CallType.video);

    await sdk.acceptCall();

    expect(engine.state.phase, CallPhase.connected);
    expect(engine.state.isVideoEnabled, isTrue);
    expect(
      signaling.sentSignals.any(
        (signal) =>
            signal.type == SDKConnectSignalType.accept &&
            signal.callType == SDKConnectCallType.video,
      ),
      isTrue,
    );

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect.voice.acceptCall rejects incoming video invite mismatch', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.invite,
        callId: 'call-in-video-2',
        fromUserId: 'user-b',
        toUserId: 'user-a',
        callType: SDKConnectCallType.video,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      () => sdk.voice.acceptCall(),
      throwsA(isA<StateError>()),
    );

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect.video.acceptCall rejects incoming voice invite mismatch', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.invite,
        callId: 'call-in-voice-2',
        fromUserId: 'user-b',
        toUserId: 'user-a',
        callType: SDKConnectCallType.voice,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    await expectLater(
      () => sdk.video.acceptCall(),
      throwsA(isA<StateError>()),
    );

    await sdk.dispose();
    await engine.dispose();
  });

  test('CallEngine rejects expired JWT token', () async {
    final engine = CallEngine(
      mediaEngine: _FakeMediaEngine(),
      logger: _InMemoryLogger(),
    );

    // Build a JWT with exp in the past.
    final pastExp = (DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000) - 3600;
    final payload = base64Url.encode(utf8.encode('{"exp":$pastExp}'));
    final expiredToken = 'header.$payload.signature';

    await expectLater(
      () => engine.startOutgoing(
        callId: 'c1',
        peerId: 'p',
        roomUrl: 'wss://room.test',
        token: expiredToken,
      ),
      throwsA(isA<CallLifecycleException>()),
    );

    await engine.dispose();
  });

  test('CallEngine rejects malformed JWT (empty segment)', () async {
    final engine = CallEngine(
      mediaEngine: _FakeMediaEngine(),
      logger: _InMemoryLogger(),
    );

    await expectLater(
      () => engine.startOutgoing(
        callId: 'c1',
        peerId: 'p',
        roomUrl: 'wss://room.test',
        token: 'header..signature',
      ),
      throwsA(isA<CallLifecycleException>()),
    );

    await engine.dispose();
  });

  test('SDKConnect emits error event when signalValidator rejects a signal', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final errorEvents = <SDKConnectErrorEvent>[];

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => false, // always reject
      callbacks: SDKConnectCallbacks(
        onError: (e) => errorEvents.add(e),
      ),
    );

    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.invite,
        callId: 'call-x',
        fromUserId: 'user-b',
        toUserId: 'user-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.idle); // call was rejected by validator
    expect(errorEvents, isNotEmpty);
    expect(errorEvents.first.operation, 'signal.validation_rejected');

    await sdk.dispose();
    await engine.dispose();
  });

  test('SDKConnect emits error event for invalid signal envelope', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final errorEvents = <SDKConnectErrorEvent>[];

    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
      callbacks: SDKConnectCallbacks(
        onError: (e) => errorEvents.add(e),
      ),
    );

    // Signal with empty callId — invalid envelope.
    signaling.pushIncoming(
      const SDKConnectSignal(
        type: SDKConnectSignalType.invite,
        callId: '',
        fromUserId: 'user-b',
        toUserId: 'user-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.idle);
    expect(errorEvents, isNotEmpty);
    expect(errorEvents.first.operation, 'signal.validation_failed');

    await sdk.dispose();
    await engine.dispose();
  });
}

class _FakeSignalingTransport implements SDKConnectSignalingTransport {
  final List<SDKConnectSignal> sentSignals = <SDKConnectSignal>[];
  final StreamController<SDKConnectSignal> _controller =
      StreamController<SDKConnectSignal>.broadcast();

  @override
  Stream<SDKConnectSignal> get signals => _controller.stream;

  @override
  Future<void> send(SDKConnectSignal signal) async {
    sentSignals.add(signal);
  }

  void pushIncoming(SDKConnectSignal signal) {
    _controller.add(signal);
  }

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
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