import 'dart:async';

import 'package:sdk_connect/core/enums/call_type.dart';
import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/sdk/livekit_media_engine_factory.dart';
import 'package:sdk_connect/sdk/video_call_sdk.dart';
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

  factory SDKConnectTokenRequest._fromVoice(
    VoiceCallTokenRequest request, {
    required SDKConnectCallType callType,
  }) {
    return SDKConnectTokenRequest(
      callId: request.callId,
      peerId: request.peerId,
      direction: request.direction,
      callType: callType,
    );
  }
}

class SDKConnectReliabilityConfig {
  const SDKConnectReliabilityConfig({
    this.reconnectPolicy = const CallReconnectPolicy(),
    this.networkThresholds = const CallNetworkThresholds(),
  });

  final CallReconnectPolicy reconnectPolicy;
  final CallNetworkThresholds networkThresholds;
}

typedef SDKConnectTokenProvider = Future<SDKConnectCredentials> Function(
  SDKConnectTokenRequest request,
);

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

  factory SDKConnectUserEvent._fromVoice(
    VoiceCallUserEvent event, {
    required SDKConnectCallType callType,
  }) {
    return SDKConnectUserEvent(
      type: SDKConnectUserEventType.values.byName(event.type.name),
      callId: event.callId,
      peerId: event.peerId,
      callType: callType,
      reason: event.reason,
    );
  }
}

enum SDKConnectConnectionEventType {
  initializing,
  ready,
  lifecycleChanged,
  connecting,
  connected,
  interruptionStarted,
  interruptionRecovered,
  mediaSessionRestored,
  audioRouteChanged,
  reconnecting,
  recovered,
  iceRecoveryStarted,
  iceRecovered,
  networkDegraded,
  networkRecovered,
  disconnected,
  failed,
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
  refreshRequested,
  refreshed,
  refreshFailed,
  failed,
}

class SDKConnectTokenEvent extends SDKConnectEvent {
  const SDKConnectTokenEvent({
    required this.type,
    required this.request,
    this.error,
    this.reconnectAttempt,
  }) : super(SDKConnectEventKind.token);

  final SDKConnectTokenEventType type;
  final SDKConnectTokenRequest request;
  final Object? error;
  final int? reconnectAttempt;

  factory SDKConnectTokenEvent._fromVoice(
    VoiceCallTokenEvent event, {
    required SDKConnectCallType callType,
  }) {
    return SDKConnectTokenEvent(
      type: SDKConnectTokenEventType.values.byName(event.type.name),
      request: SDKConnectTokenRequest._fromVoice(
        event.request,
        callType: callType,
      ),
      error: event.error,
      reconnectAttempt: event.reconnectAttempt,
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
    required SDKConnectTokenProvider tokenProvider,
    SDKConnectCallbacks callbacks = const SDKConnectCallbacks(),
  })  : _callEngine = callEngine,
        _callbacks = callbacks,
      _ownsEngine = false {
    _voiceSdk = VoiceCallSdk(
      localUserId: localUserId,
      callEngine: callEngine,
      tokenProvider: (request) async {
        final credentials = await tokenProvider(
          SDKConnectTokenRequest._fromVoice(
            request,
            callType: _resolveRequestCallType(request),
          ),
        );
        return credentials._toVoiceCredentials();
      },
      callbacks: VoiceCallCallbacks(
        onUser: _handleVoiceUserEvent,
        onConnection: _handleVoiceConnectionEvent,
        onError: _handleVoiceErrorEvent,
        onToken: _handleVoiceTokenEvent,
      ),
    );
    voice = SDKConnectVoiceApi._(this);
    video = SDKConnectVideoApi._(
      this,
      VideoCallSdk(
        voiceSdk: _voiceSdk,
        callEngine: _callEngine,
      ),
    );
  }

  factory SDKConnect.create({
    required String localUserId,
    required SDKConnectTokenProvider tokenProvider,
    SDKConnectCallbacks callbacks = const SDKConnectCallbacks(),
    SDKConnectReliabilityConfig reliability = const SDKConnectReliabilityConfig(),
    StructuredLogger? logger,
    DateTime Function()? clock,
  }) {
    final callEngine = CallEngine(
      mediaEngine: createLiveKitMediaEngine(),
      logger: logger,
      clock: clock,
      reconnectPolicy: reliability.reconnectPolicy,
      networkThresholds: reliability.networkThresholds,
      tokenRefresher: (session, reconnectAttempt) async {
        final credentials = await tokenProvider(
          SDKConnectTokenRequest(
            callId: session.callId,
            peerId: session.peerId,
            direction: session.direction,
            callType: session.callType.toPublic(),
          ),
        );
        return credentials.token;
      },
    );

    return SDKConnect._owned(
      localUserId: localUserId,
      callEngine: callEngine,
      tokenProvider: tokenProvider,
      callbacks: callbacks,
    );
  }

  SDKConnect._owned({
    required String localUserId,
    required CallEngine callEngine,
    required SDKConnectTokenProvider tokenProvider,
    required SDKConnectCallbacks callbacks,
  })  : _callEngine = callEngine,
        _callbacks = callbacks,
      _ownsEngine = true {
    _voiceSdk = VoiceCallSdk(
      localUserId: localUserId,
      callEngine: callEngine,
      tokenProvider: (request) async {
        final credentials = await tokenProvider(
          SDKConnectTokenRequest._fromVoice(
            request,
            callType: _resolveRequestCallType(request),
          ),
        );
        return credentials._toVoiceCredentials();
      },
      callbacks: VoiceCallCallbacks(
        onUser: _handleVoiceUserEvent,
        onConnection: _handleVoiceConnectionEvent,
        onError: _handleVoiceErrorEvent,
        onToken: _handleVoiceTokenEvent,
      ),
    );
    voice = SDKConnectVoiceApi._(this);
    video = SDKConnectVideoApi._(
      this,
      VideoCallSdk(
        voiceSdk: _voiceSdk,
        callEngine: _callEngine,
      ),
    );
  }

  final CallEngine _callEngine;
  final SDKConnectCallbacks _callbacks;
  final bool _ownsEngine;
  final StreamController<SDKConnectEvent> _eventsController =
      StreamController<SDKConnectEvent>.broadcast();

  late final VoiceCallSdk _voiceSdk;
  late final SDKConnectVoiceApi voice;
  late final SDKConnectVideoApi video;

  SDKConnectCallType _nextOutgoingCallType = SDKConnectCallType.voice;

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
  }) {
    return _startCallInternal(peerId: peerId, callId: callId, callType: callType);
  }

  Future<void> acceptCall({
    SDKConnectCallType? callType,
  }) {
    throw StateError(
      'acceptCall is removed from SDKConnect. Signaling/invitation flow is handled externally.',
    );
  }

  Future<void> rejectCall({String reason = 'rejected'}) {
    throw StateError(
      'rejectCall is removed from SDKConnect. Signaling/invitation flow is handled externally.',
    );
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
    return _callEngine.setVideoEnabled(enabled);
  }

  Future<void> toggleCamera() {
    return _callEngine.setVideoEnabled(!_callEngine.state.isVideoEnabled);
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    await video._dispose();
    await _voiceSdk.dispose();
    if (_ownsEngine) {
      await _callEngine.dispose();
    }
    await _eventsController.close();
  }

  void _handleVoiceUserEvent(VoiceCallUserEvent event) {
    final mappedEvent = SDKConnectUserEvent._fromVoice(
      event,
      callType: _resolveCurrentCallType(),
    );
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
    final mappedEvent = SDKConnectTokenEvent._fromVoice(
      event,
      callType: _resolveRequestCallType(event.request),
    );
    _callbacks.onToken?.call(mappedEvent);
    _emitEvent(mappedEvent);
  }

  Future<void> _startCallInternal({
    required String peerId,
    String? callId,
    required SDKConnectCallType callType,
  }) async {
    _ensureVideoOrVoice(callType);
    _nextOutgoingCallType = callType;
    try {
      await _voiceSdk.startCall(
        peerId: peerId,
        callId: callId,
        callType: callType.toCore(),
      );
      if (callType == SDKConnectCallType.video) {
        await _callEngine.setVideoEnabled(true);
      }
    } finally {
      _nextOutgoingCallType = _resolveCurrentCallType();
    }
  }

  Future<void> _acceptCallInternal({
    SDKConnectCallType? callType,
  }) {
    throw StateError(
      'acceptCall is removed from SDKConnect. Signaling/invitation flow is handled externally.',
    );
  }

  SDKConnectCallType _resolveCurrentCallType() {
    final sessionType = _callEngine.state.session?.callType;
    if (sessionType == null) {
      return SDKConnectCallType.voice;
    }
    return sessionType.toPublic();
  }

  SDKConnectCallType _resolveRequestCallType(VoiceCallTokenRequest request) {
    final session = _callEngine.state.session;
    if (session != null && session.callId == request.callId) {
      return session.callType.toPublic();
    }
    return _nextOutgoingCallType;
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

class SDKConnectVoiceApi {
  SDKConnectVoiceApi._(this._sdk);

  final SDKConnect _sdk;

  CallState get state => _sdk.state;
  Stream<CallState> get states => _sdk.states;

  Future<void> initialize({String? localUserId}) {
    return _sdk.initialize(localUserId: localUserId);
  }

  Future<void> startCall({
    required String peerId,
    String? callId,
  }) {
    return _sdk._startCallInternal(
      peerId: peerId,
      callId: callId,
      callType: SDKConnectCallType.voice,
    );
  }

  Future<void> acceptCall() {
    return _sdk._acceptCallInternal(callType: SDKConnectCallType.voice);
  }

  Future<void> rejectCall({String reason = 'rejected'}) {
    return _sdk.rejectCall(reason: reason);
  }

  Future<void> endCall({String reason = 'ended_by_user'}) {
    return _sdk.endCall(reason: reason);
  }

  Future<void> setMuted(bool muted) {
    return _sdk.setMuted(muted);
  }

  Future<void> toggleMute() {
    return _sdk.toggleMute();
  }

  Future<void> setSpeakerOn(bool speakerOn) {
    return _sdk.setSpeakerOn(speakerOn);
  }

  Future<void> toggleSpeaker() {
    return _sdk.toggleSpeaker();
  }
}

class SDKConnectVideoApi {
  SDKConnectVideoApi._(this._sdk, this._videoSdk);

  final SDKConnect _sdk;
  final VideoCallSdk _videoSdk;

  CallState get state => _sdk.state;
  Stream<CallState> get states => _sdk.states;

  Future<void> initialize({String? localUserId}) {
    return _sdk.initialize(localUserId: localUserId);
  }

  Future<void> startCall({
    required String peerId,
    String? callId,
  }) {
    return _sdk._startCallInternal(
      peerId: peerId,
      callId: callId,
      callType: SDKConnectCallType.video,
    );
  }

  Future<void> acceptCall() {
    return _sdk._acceptCallInternal(callType: SDKConnectCallType.video);
  }

  Future<void> rejectCall({String reason = 'rejected'}) {
    return _sdk.rejectCall(reason: reason);
  }

  Future<void> endCall({String reason = 'ended_by_user'}) {
    return _sdk.endCall(reason: reason);
  }

  Future<void> setMuted(bool muted) {
    return _sdk.setMuted(muted);
  }

  Future<void> toggleMute() {
    return _sdk.toggleMute();
  }

  Future<void> setSpeakerOn(bool speakerOn) {
    return _sdk.setSpeakerOn(speakerOn);
  }

  Future<void> toggleSpeaker() {
    return _sdk.toggleSpeaker();
  }

  Future<void> setCameraEnabled(bool enabled) {
    return _videoSdk.setCameraEnabled(enabled);
  }

  Future<void> toggleCamera() {
    return _videoSdk.toggleCamera();
  }

  Future<void> enterPictureInPicture() {
    return _videoSdk.enterPictureInPicture();
  }

  Future<void> exitPictureInPicture() {
    return _videoSdk.exitPictureInPicture();
  }

  Future<void> _dispose() {
    return _videoSdk.dispose();
  }
}

extension on SDKConnectCallType {
  CallType toCore() {
    return switch (this) {
      SDKConnectCallType.voice => CallType.voice,
      SDKConnectCallType.video => CallType.video,
    };
  }
}

extension on CallType {
  SDKConnectCallType toPublic() {
    return switch (this) {
      CallType.voice => SDKConnectCallType.voice,
      CallType.video => SDKConnectCallType.video,
    };
  }
}