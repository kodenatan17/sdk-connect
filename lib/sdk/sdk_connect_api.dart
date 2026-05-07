import 'dart:async';

import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/sdk/livekit_media_engine_factory.dart';
import 'package:sdk_connect/sdk/voice_call_sdk.dart';

enum SDKConnectCallType {
  voice,
  video,
}

class SDKConnectCredentials {
  const SDKConnectCredentials({
    required this.roomUrl,
    required this.token,
  });

  final String roomUrl;
  final String token;

  VoiceCallCredentials _toVoiceCredentials() {
    return VoiceCallCredentials(roomUrl: roomUrl, token: token);
  }
}

class SDKConnectTokenRequest {
  const SDKConnectTokenRequest({
    required this.callId,
    required this.peerId,
    required this.direction,
    this.callType = SDKConnectCallType.voice,
  });

  final String callId;
  final String peerId;
  final CallDirection direction;
  final SDKConnectCallType callType;

  factory SDKConnectTokenRequest._fromVoice(VoiceCallTokenRequest request) {
    return SDKConnectTokenRequest(
      callId: request.callId,
      peerId: request.peerId,
      direction: request.direction,
    );
  }
}

typedef SDKConnectTokenProvider = Future<SDKConnectCredentials> Function(
  SDKConnectTokenRequest request,
);

typedef SDKConnectSignalValidator = FutureOr<bool> Function(
  SDKConnectSignal signal,
);

enum SDKConnectSignalType {
  invite,
  accept,
  reject,
  end,
}

class SDKConnectSignal {
  const SDKConnectSignal({
    required this.type,
    required this.callId,
    required this.fromUserId,
    required this.toUserId,
    this.callType = SDKConnectCallType.voice,
    this.reason,
  });

  final SDKConnectSignalType type;
  final String callId;
  final String fromUserId;
  final String toUserId;
  final SDKConnectCallType callType;
  final String? reason;

  factory SDKConnectSignal._fromVoice(VoiceCallSignal signal) {
    return SDKConnectSignal(
      type: SDKConnectSignalType.values.byName(signal.type.name),
      callId: signal.callId,
      fromUserId: signal.fromUserId,
      toUserId: signal.toUserId,
      reason: signal.reason,
    );
  }

  VoiceCallSignal _toVoiceSignal() {
    return VoiceCallSignal(
      type: VoiceCallSignalType.values.byName(type.name),
      callId: callId,
      fromUserId: fromUserId,
      toUserId: toUserId,
      reason: reason,
    );
  }
}

abstract class SDKConnectSignalingTransport {
  Stream<SDKConnectSignal> get signals;

  Future<void> send(SDKConnectSignal signal);

  Future<void> dispose();
}

class InMemorySDKConnectSignalingTransport
    implements SDKConnectSignalingTransport {
  InMemorySDKConnectSignalingTransport();

  final StreamController<SDKConnectSignal> _controller =
      StreamController<SDKConnectSignal>.broadcast();

  @override
  Stream<SDKConnectSignal> get signals => _controller.stream;

  @override
  Future<void> send(SDKConnectSignal signal) async {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(signal);
  }

  @override
  Future<void> dispose() async {
    if (_controller.isClosed) {
      return;
    }
    await _controller.close();
  }
}

enum SDKConnectEventKind {
  user,
  connection,
  error,
  token,
}

abstract class SDKConnectEvent {
  const SDKConnectEvent(this.kind);

  final SDKConnectEventKind kind;
}

enum SDKConnectUserEventType {
  outgoingStarted,
  incomingReceived,
  accepted,
  rejected,
  ended,
  p2pLimitExceeded,
}

class SDKConnectUserEvent extends SDKConnectEvent {
  const SDKConnectUserEvent({
    required this.type,
    required this.callId,
    required this.peerId,
    this.callType = SDKConnectCallType.voice,
    this.reason,
  }) : super(SDKConnectEventKind.user);

  final SDKConnectUserEventType type;
  final String callId;
  final String peerId;
  final SDKConnectCallType callType;
  final String? reason;

  factory SDKConnectUserEvent._fromVoice(VoiceCallUserEvent event) {
    return SDKConnectUserEvent(
      type: SDKConnectUserEventType.values.byName(event.type.name),
      callId: event.callId,
      peerId: event.peerId,
      reason: event.reason,
    );
  }
}

enum SDKConnectConnectionEventType {
  initializing,
  ready,
  dialing,
  ringing,
  connected,
  ended,
  idle,
}

class SDKConnectConnectionEvent extends SDKConnectEvent {
  const SDKConnectConnectionEvent({
    required this.type,
    required this.state,
  }) : super(SDKConnectEventKind.connection);

  final SDKConnectConnectionEventType type;
  final CallState state;

  factory SDKConnectConnectionEvent._fromVoice(VoiceCallConnectionEvent event) {
    return SDKConnectConnectionEvent(
      type: SDKConnectConnectionEventType.values.byName(event.type.name),
      state: event.state,
    );
  }
}

enum SDKConnectTokenEventType {
  requested,
  resolved,
  failed,
}

class SDKConnectTokenEvent extends SDKConnectEvent {
  const SDKConnectTokenEvent({
    required this.type,
    required this.request,
    this.error,
  }) : super(SDKConnectEventKind.token);

  final SDKConnectTokenEventType type;
  final SDKConnectTokenRequest request;
  final Object? error;

  factory SDKConnectTokenEvent._fromVoice(VoiceCallTokenEvent event) {
    return SDKConnectTokenEvent(
      type: SDKConnectTokenEventType.values.byName(event.type.name),
      request: SDKConnectTokenRequest._fromVoice(event.request),
      error: event.error,
    );
  }
}

class SDKConnectErrorEvent extends SDKConnectEvent {
  const SDKConnectErrorEvent({
    required this.operation,
    required this.error,
    this.stackTrace,
  }) : super(SDKConnectEventKind.error);

  final String operation;
  final Object error;
  final StackTrace? stackTrace;

  factory SDKConnectErrorEvent._fromVoice(VoiceCallErrorEvent event) {
    return SDKConnectErrorEvent(
      operation: event.operation,
      error: event.error,
      stackTrace: event.stackTrace,
    );
  }
}

class SDKConnectCallbacks {
  const SDKConnectCallbacks({
    this.onEvent,
    this.onUser,
    this.onConnection,
    this.onError,
    this.onToken,
  });

  final void Function(SDKConnectEvent event)? onEvent;
  final void Function(SDKConnectUserEvent event)? onUser;
  final void Function(SDKConnectConnectionEvent event)? onConnection;
  final void Function(SDKConnectErrorEvent event)? onError;
  final void Function(SDKConnectTokenEvent event)? onToken;
}

class SDKConnect {
  SDKConnect({
    required String localUserId,
    required CallEngine callEngine,
    required SDKConnectSignalingTransport signaling,
    required SDKConnectTokenProvider tokenProvider,
    required SDKConnectSignalValidator signalValidator,
    SDKConnectCallbacks callbacks = const SDKConnectCallbacks(),
  })  : _callEngine = callEngine,
        _signaling = signaling,
        _callbacks = callbacks,
        _ownsEngine = false,
        _ownsSignaling = false {
    _voiceSdk = VoiceCallSdk(
      localUserId: localUserId,
      callEngine: callEngine,
      signaling: _SDKConnectSignalingTransportAdapter(signaling),
      tokenProvider: (request) async {
        final credentials = await tokenProvider(
          SDKConnectTokenRequest._fromVoice(request),
        );
        return credentials._toVoiceCredentials();
      },
      signalValidator: (signal) {
        return signalValidator(SDKConnectSignal._fromVoice(signal));
      },
      callbacks: VoiceCallCallbacks(
        onUser: _handleVoiceUserEvent,
        onConnection: _handleVoiceConnectionEvent,
        onError: _handleVoiceErrorEvent,
        onToken: _handleVoiceTokenEvent,
      ),
    );
  }

  factory SDKConnect.create({
    required String localUserId,
    required SDKConnectTokenProvider tokenProvider,
    required SDKConnectSignalValidator signalValidator,
    SDKConnectSignalingTransport? signaling,
    SDKConnectCallbacks callbacks = const SDKConnectCallbacks(),
    StructuredLogger? logger,
    DateTime Function()? clock,
  }) {
    final resolvedSignaling = signaling ?? InMemorySDKConnectSignalingTransport();
    final callEngine = CallEngine(
      mediaEngine: createLiveKitMediaEngine(),
      logger: logger,
      clock: clock,
    );

    return SDKConnect._owned(
      localUserId: localUserId,
      callEngine: callEngine,
      signaling: resolvedSignaling,
      tokenProvider: tokenProvider,
      signalValidator: signalValidator,
      callbacks: callbacks,
      ownsSignaling: signaling == null,
    );
  }

  SDKConnect._owned({
    required String localUserId,
    required CallEngine callEngine,
    required SDKConnectSignalingTransport signaling,
    required SDKConnectTokenProvider tokenProvider,
    required SDKConnectSignalValidator signalValidator,
    required SDKConnectCallbacks callbacks,
    required bool ownsSignaling,
  })  : _callEngine = callEngine,
        _signaling = signaling,
        _callbacks = callbacks,
        _ownsEngine = true,
        _ownsSignaling = ownsSignaling {
    _voiceSdk = VoiceCallSdk(
      localUserId: localUserId,
      callEngine: callEngine,
      signaling: _SDKConnectSignalingTransportAdapter(signaling),
      tokenProvider: (request) async {
        final credentials = await tokenProvider(
          SDKConnectTokenRequest._fromVoice(request),
        );
        return credentials._toVoiceCredentials();
      },
      signalValidator: (signal) {
        return signalValidator(SDKConnectSignal._fromVoice(signal));
      },
      callbacks: VoiceCallCallbacks(
        onUser: _handleVoiceUserEvent,
        onConnection: _handleVoiceConnectionEvent,
        onError: _handleVoiceErrorEvent,
        onToken: _handleVoiceTokenEvent,
      ),
    );
  }

  final CallEngine _callEngine;
  final SDKConnectSignalingTransport _signaling;
  final SDKConnectCallbacks _callbacks;
  final bool _ownsEngine;
  final bool _ownsSignaling;
  final StreamController<SDKConnectEvent> _eventsController =
      StreamController<SDKConnectEvent>.broadcast();

  late final VoiceCallSdk _voiceSdk;

  bool _isDisposed = false;

  CallState get state => _voiceSdk.state;
  Stream<CallState> get states => _voiceSdk.states;
  Stream<SDKConnectEvent> get events => _eventsController.stream;

  Future<void> initialize({String? localUserId}) {
    return _voiceSdk.initialize(localUserId: localUserId);
  }

  Future<void> startCall({
    required String peerId,
    String? callId,
    SDKConnectCallType callType = SDKConnectCallType.voice,
  }) async {
    _ensureVideoOrVoice(callType);
    await _voiceSdk.startCall(peerId: peerId, callId: callId);
    if (callType == SDKConnectCallType.video) {
      await _voiceSdk.setVideoEnabled(true);
    }
  }

  Future<void> acceptCall({
    SDKConnectCallType callType = SDKConnectCallType.voice,
  }) async {
    _ensureVideoOrVoice(callType);
    await _voiceSdk.acceptCall();
    if (callType == SDKConnectCallType.video) {
      await _voiceSdk.setVideoEnabled(true);
    }
  }

  Future<void> rejectCall({String reason = 'rejected'}) {
    return _voiceSdk.rejectCall(reason: reason);
  }

  Future<void> endCall({String reason = 'ended_by_user'}) {
    return _voiceSdk.endCall(reason: reason);
  }

  Future<void> setMuted(bool muted) {
    return _voiceSdk.setMuted(muted);
  }

  Future<void> toggleMute() {
    return _voiceSdk.toggleMute();
  }

  Future<void> setSpeakerOn(bool speakerOn) {
    return _voiceSdk.setSpeakerOn(speakerOn);
  }

  Future<void> toggleSpeaker() {
    return _voiceSdk.toggleSpeaker();
  }

  Future<void> setVideoEnabled(bool enabled) {
    return _voiceSdk.setVideoEnabled(enabled);
  }

  Future<void> toggleCamera() {
    return _voiceSdk.toggleCamera();
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    await _voiceSdk.dispose();
    if (_ownsSignaling) {
      await _signaling.dispose();
    }
    if (_ownsEngine) {
      await _callEngine.dispose();
    }
    await _eventsController.close();
  }

  void _handleVoiceUserEvent(VoiceCallUserEvent event) {
    final mappedEvent = SDKConnectUserEvent._fromVoice(event);
    _callbacks.onUser?.call(mappedEvent);
    _emitEvent(mappedEvent);
  }

  void _handleVoiceConnectionEvent(VoiceCallConnectionEvent event) {
    final mappedEvent = SDKConnectConnectionEvent._fromVoice(event);
    _callbacks.onConnection?.call(mappedEvent);
    _emitEvent(mappedEvent);
  }

  void _handleVoiceErrorEvent(VoiceCallErrorEvent event) {
    final mappedEvent = SDKConnectErrorEvent._fromVoice(event);
    _callbacks.onError?.call(mappedEvent);
    _emitEvent(mappedEvent);
  }

  void _handleVoiceTokenEvent(VoiceCallTokenEvent event) {
    final mappedEvent = SDKConnectTokenEvent._fromVoice(event);
    _callbacks.onToken?.call(mappedEvent);
    _emitEvent(mappedEvent);
  }

  void _emitEvent(SDKConnectEvent event) {
    _callbacks.onEvent?.call(event);
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  void _ensureVideoOrVoice(SDKConnectCallType callType) {
    if (callType == SDKConnectCallType.voice || callType == SDKConnectCallType.video) {
      return;
    }
    throw UnsupportedError('Unsupported callType: ${callType.name}.');
  }
}

class _SDKConnectSignalingTransportAdapter
    implements VoiceCallSignalingTransport {
  _SDKConnectSignalingTransportAdapter(this._delegate);

  final SDKConnectSignalingTransport _delegate;

  @override
  Stream<VoiceCallSignal> get signals =>
      _delegate.signals.map((signal) => signal._toVoiceSignal());

  @override
  Future<void> send(VoiceCallSignal signal) {
    return _delegate.send(SDKConnectSignal._fromVoice(signal));
  }

  @override
  Future<void> dispose() {
    return _delegate.dispose();
  }
}