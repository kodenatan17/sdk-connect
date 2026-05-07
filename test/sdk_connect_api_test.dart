import 'dart:async';

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

  test('SDKConnect keeps the future video slot non-breaking', () async {
    final sdk = SDKConnect(
      localUserId: 'user-a',
      callEngine: CallEngine(
        mediaEngine: _FakeMediaEngine(),
        logger: _InMemoryLogger(),
      ),
      signaling: _FakeSignalingTransport(),
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
    );

    await expectLater(
      () => sdk.startCall(
        peerId: 'user-b',
        callType: SDKConnectCallType.video,
      ),
      throwsA(isA<UnsupportedError>()),
    );

    await sdk.dispose();
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