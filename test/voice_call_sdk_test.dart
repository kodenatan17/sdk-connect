import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sdk_connect/sdk_connect.dart';

void main() {
  const validCredentials = VoiceCallCredentials(
    roomUrl: 'wss://room.test',
    token: 'header.payload.signature',
  );

  test('sdk initializes and starts outgoing call with internal token resolution', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final tokenRequests = <VoiceCallTokenRequest>[];
    final tokenEvents = <VoiceCallTokenEventType>[];
    final connectionEvents = <VoiceCallConnectionEventType>[];

    final sdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (request) async {
        tokenRequests.add(request);
        return validCredentials;
      },
      signalValidator: (_) async => true,
      callbacks: VoiceCallCallbacks(
        onToken: (event) => tokenEvents.add(event.type),
        onConnection: (event) => connectionEvents.add(event.type),
      ),
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-1');

    expect(media.connectCount, 1);
    expect(engine.state.phase, CallPhase.dialing);
    expect(tokenRequests.single.direction, CallDirection.outgoing);
    expect(signaling.sentSignals.single.type, VoiceCallSignalType.invite);
    expect(tokenEvents, <VoiceCallTokenEventType>[
      VoiceCallTokenEventType.requested,
      VoiceCallTokenEventType.resolved,
    ]);
    expect(connectionEvents, contains(VoiceCallConnectionEventType.ready));
    expect(connectionEvents, contains(VoiceCallConnectionEventType.dialing));

    signaling.pushIncoming(
      const VoiceCallSignal(
        type: VoiceCallSignalType.accept,
        callId: 'call-1',
        fromUserId: 'user-b',
        toUserId: 'user-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.connected);

    await sdk.dispose();
    await engine.dispose();
  });

  test('sdk handles incoming signal and accepts call internally', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final userEvents = <VoiceCallUserEventType>[];
    final sdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
      callbacks: VoiceCallCallbacks(
        onUser: (event) => userEvents.add(event.type),
      ),
    );

    signaling.pushIncoming(
      const VoiceCallSignal(
        type: VoiceCallSignalType.invite,
        callId: 'call-2',
        fromUserId: 'user-b',
        toUserId: 'user-a',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.ringing);
    expect(userEvents, contains(VoiceCallUserEventType.incomingReceived));

    await sdk.acceptCall();

    expect(engine.state.phase, CallPhase.connected);
    expect(
      signaling.sentSignals.last.type,
      VoiceCallSignalType.accept,
    );

    await sdk.dispose();
    await engine.dispose();
  });

  test('sdk surfaces p2p limit callback from call engine events', () async {
    final media = _FakeMediaEngine();
    final signaling = _FakeSignalingTransport();
    final engine = CallEngine(mediaEngine: media, logger: _InMemoryLogger());

    final userEvents = <VoiceCallUserEventType>[];
    final sdk = VoiceCallSdk(
      localUserId: 'user-a',
      callEngine: engine,
      signaling: signaling,
      tokenProvider: (_) async => validCredentials,
      signalValidator: (_) async => true,
      callbacks: VoiceCallCallbacks(
        onUser: (event) => userEvents.add(event.type),
      ),
    );

    await sdk.startCall(peerId: 'user-b', callId: 'call-3');

    media.emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.p2pLimitExceeded,
        reason: 'p2p_limit_exceeded',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(engine.state.phase, CallPhase.idle);
    expect(userEvents, contains(VoiceCallUserEventType.p2pLimitExceeded));

    await sdk.dispose();
    await engine.dispose();
  });
}

class _FakeSignalingTransport implements VoiceCallSignalingTransport {
  final List<VoiceCallSignal> sentSignals = <VoiceCallSignal>[];
  final StreamController<VoiceCallSignal> _controller =
      StreamController<VoiceCallSignal>.broadcast();

  @override
  Stream<VoiceCallSignal> get signals => _controller.stream;

  @override
  Future<void> send(VoiceCallSignal signal) async {
    sentSignals.add(signal);
  }

  void pushIncoming(VoiceCallSignal signal) {
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

  void emitEvent(MediaEngineEvent event) {
    _eventsController.add(event);
  }
}

class _InMemoryLogger implements StructuredLogger {
  @override
  void log({required String event, required Map<String, Object?> fields}) {}
}
