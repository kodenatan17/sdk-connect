import 'dart:async';

import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/enums/call_type.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/sdk/livekit_media_engine_factory.dart';
import 'package:sdk_connect/sdk/video_call_sdk.dart';
import 'package:sdk_connect/sdk/voice_call_sdk.dart';

enum SDKConnectCallType { voice, video }

enum SDKConnectConnectionState {
  /// No active media session.
  idle,

  /// Session setup is in progress.
  connecting,

  /// Session is active and stable.
  connected,

  /// Session is recovering after interruption.
  reconnecting,

  /// Session terminated gracefully.
  disconnected,

  /// Session terminated due to unrecoverable error.
  failed,
}

/// Widget-level lifecycle phase that aggregates SDKConnect RTC states with
/// consumer UI rendering states.
///
/// Mapping:
/// - [calling]   → SDKConnect `connecting`
/// - [connected] → SDKConnect `connected` or `reconnecting`
/// - [ended]     → SDKConnect `idle`, `disconnected`, or `failed`
enum SDKConnectWidgetPhase {
  /// Session setup phase.
  calling,

  /// Media session active; includes temporary reconnecting intervals.
  connected,

  /// No active session or session has terminated.
  ended;

  /// Maps an [SDKConnectConnectionState] to its corresponding widget phase.
  static SDKConnectWidgetPhase from(SDKConnectConnectionState state) {
    return switch (state) {
      SDKConnectConnectionState.idle => SDKConnectWidgetPhase.ended,
      SDKConnectConnectionState.connecting => SDKConnectWidgetPhase.calling,
      SDKConnectConnectionState.connected => SDKConnectWidgetPhase.connected,
      SDKConnectConnectionState.reconnecting => SDKConnectWidgetPhase.connected,
      SDKConnectConnectionState.disconnected => SDKConnectWidgetPhase.ended,
      SDKConnectConnectionState.failed => SDKConnectWidgetPhase.ended,
    };
  }
}

/// Standardised widget-layer callbacks for consumer UI integration.
///
/// Widgets fire these callbacks as observers; they do not own lifecycle logic.
/// All handlers are optional — supply only what the consumer needs.
class SDKConnectWidgetCallbacks {
  const SDKConnectWidgetCallbacks({
    this.onCallStateChanged,
    this.onReconnect,
    this.onDisconnected,
    this.onEnded,
  });

  /// Fired every time the [SDKConnectWidgetPhase] changes.
  ///
  /// Note: widgets emit [SDKConnectWidgetPhase.ended] on initial mount when
  /// SDK state is idle (no active session).
  final void Function(SDKConnectWidgetPhase phase)? onCallStateChanged;

  /// Fired once each time the connection enters reconnecting.
  final void Function()? onReconnect;

  /// Fired when the session reaches a disconnected or failed state.
  final void Function(String? reason)? onDisconnected;

  /// Fired exactly once when the call reaches its terminal state.
  /// Deduplicated — safe to use for navigation / cleanup.
  final void Function(String? reason)? onEnded;
}

enum SDKConnectAudioRoute {
  earpiece,
  speaker,
  bluetooth,
  wiredHeadset,
  unknown,
}

class SDKConnectParticipantState {
  const SDKConnectParticipantState({
    this.localParticipantId,
    this.remoteParticipantId,
    required this.hasRemoteParticipant,
  });

  final String? localParticipantId;
  final String? remoteParticipantId;
  final bool hasRemoteParticipant;

  SDKConnectParticipantState copyWith({
    String? localParticipantId,
    String? remoteParticipantId,
    bool? hasRemoteParticipant,
  }) {
    return SDKConnectParticipantState(
      localParticipantId: localParticipantId ?? this.localParticipantId,
      remoteParticipantId: remoteParticipantId ?? this.remoteParticipantId,
      hasRemoteParticipant: hasRemoteParticipant ?? this.hasRemoteParticipant,
    );
  }
}

class SDKConnectMediaState {
  const SDKConnectMediaState({
    required this.localAudioEnabled,
    required this.remoteAudioEnabled,
    required this.localVideoEnabled,
    required this.remoteVideoEnabled,
    required this.audioRoute,
  });

  final bool localAudioEnabled;
  final bool remoteAudioEnabled;
  final bool localVideoEnabled;
  final bool remoteVideoEnabled;
  final SDKConnectAudioRoute audioRoute;

  SDKConnectMediaState copyWith({
    bool? localAudioEnabled,
    bool? remoteAudioEnabled,
    bool? localVideoEnabled,
    bool? remoteVideoEnabled,
    SDKConnectAudioRoute? audioRoute,
  }) {
    return SDKConnectMediaState(
      localAudioEnabled: localAudioEnabled ?? this.localAudioEnabled,
      remoteAudioEnabled: remoteAudioEnabled ?? this.remoteAudioEnabled,
      localVideoEnabled: localVideoEnabled ?? this.localVideoEnabled,
      remoteVideoEnabled: remoteVideoEnabled ?? this.remoteVideoEnabled,
      audioRoute: audioRoute ?? this.audioRoute,
    );
  }
}

class SDKConnectNetworkState {
  const SDKConnectNetworkState({
    this.score,
    required this.isWeak,
    required this.isRecovered,
  });

  final int? score;
  final bool isWeak;
  final bool isRecovered;

  SDKConnectNetworkState copyWith({
    int? score,
    bool clearScore = false,
    bool? isWeak,
    bool? isRecovered,
  }) {
    return SDKConnectNetworkState(
      score: clearScore ? null : (score ?? this.score),
      isWeak: isWeak ?? this.isWeak,
      isRecovered: isRecovered ?? this.isRecovered,
    );
  }
}

class SDKConnectRuntimeState {
  const SDKConnectRuntimeState({
    required this.callState,
    required this.connectionState,
    required this.participants,
    required this.media,
    required this.network,
  });

  final CallState callState;
  final SDKConnectConnectionState connectionState;
  final SDKConnectParticipantState participants;
  final SDKConnectMediaState media;
  final SDKConnectNetworkState network;

  factory SDKConnectRuntimeState.fromCallState(
    CallState state, {
    required String localUserId,
    SDKConnectAudioRoute audioRoute = SDKConnectAudioRoute.earpiece,
  }) {
    return SDKConnectRuntimeState(
      callState: state,
      connectionState: mapConnectionState(state),
      participants: SDKConnectParticipantState(
        localParticipantId: localUserId,
        remoteParticipantId: state.session?.peerId,
        hasRemoteParticipant:
            state.session != null &&
            (state.phase == CallPhase.connecting ||
                state.phase == CallPhase.connected ||
                state.phase == CallPhase.reconnecting),
      ),
      media: SDKConnectMediaState(
        localAudioEnabled: !state.isMuted,
        remoteAudioEnabled: state.session != null,
        localVideoEnabled: state.isVideoEnabled,
        remoteVideoEnabled:
            state.session?.callType == CallType.video && state.session != null,
        audioRoute: audioRoute,
      ),
      network: SDKConnectNetworkState(
        score: state.networkScore,
        isWeak: state.isAudioPriority,
        isRecovered: !state.isAudioPriority,
      ),
    );
  }

  SDKConnectRuntimeState copyWith({
    CallState? callState,
    SDKConnectConnectionState? connectionState,
    SDKConnectParticipantState? participants,
    SDKConnectMediaState? media,
    SDKConnectNetworkState? network,
  }) {
    return SDKConnectRuntimeState(
      callState: callState ?? this.callState,
      connectionState: connectionState ?? this.connectionState,
      participants: participants ?? this.participants,
      media: media ?? this.media,
      network: network ?? this.network,
    );
  }

  /// Maps core call state to public SDK connection state.
  ///
  /// This is the single mapping used by SDK runtime and widgets.
  static SDKConnectConnectionState mapConnectionState(CallState state) {
    return switch (state.phase) {
      CallPhase.idle => SDKConnectConnectionState.idle,
      CallPhase.connecting => SDKConnectConnectionState.connecting,
      CallPhase.connected => SDKConnectConnectionState.connected,
      CallPhase.reconnecting => SDKConnectConnectionState.reconnecting,
      CallPhase.disconnected => SDKConnectConnectionState.disconnected,
      CallPhase.failed => SDKConnectConnectionState.failed,
    };
  }
}

class SDKConnectCredentials {
  const SDKConnectCredentials({required this.roomUrl, required this.token});

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

typedef SDKConnectTokenProvider =
    Future<SDKConnectCredentials> Function(SDKConnectTokenRequest request);

enum SDKConnectEventKind {
  /// User-intent level events from SDK session flow.
  user,

  /// Lifecycle and transport-status events.
  connection,

  /// Sanitized runtime errors surfaced by the SDK.
  error,

  /// Token lifecycle events for token-provider observability.
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
  const SDKConnectConnectionEvent({required this.type, required this.state})
    : super(SDKConnectEventKind.connection);

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

/// Public callbacks for custom UI consumers.
///
/// These callbacks observe SDK/engine state only and do not own signaling.
class SDKConnectCallbacks {
  const SDKConnectCallbacks({
    this.onEvent,
    this.onUser,
    this.onConnection,
    this.onError,
    this.onToken,
    this.onConnectionStateChanged,
    this.onReconnecting,
    this.onReconnected,
    this.onConnectionLost,
    this.onParticipantJoined,
    this.onParticipantLeft,
    this.onNetworkQualityChanged,
    this.onLocalAudioChanged,
    this.onRemoteAudioChanged,
    this.onLocalVideoChanged,
    this.onRemoteVideoChanged,
    this.onAudioRouteChanged,
    this.onCallWarning,
    this.onCallRecovered,
  });

  final void Function(SDKConnectEvent event)? onEvent;
  final void Function(SDKConnectUserEvent event)? onUser;
  final void Function(SDKConnectConnectionEvent event)? onConnection;
  final void Function(SDKConnectErrorEvent event)? onError;
  final void Function(SDKConnectTokenEvent event)? onToken;

  /// Lightweight runtime callbacks for plug-and-play UI consumers.
  ///
  /// These callbacks observe [CallEngine] state transitions and do not own
  /// signaling decisions.
  final void Function(SDKConnectConnectionState state, CallState callState)?
  onConnectionStateChanged;
  final void Function(CallState callState)? onReconnecting;
  final void Function(CallState callState)? onReconnected;
  final void Function(CallState callState, String? reason)? onConnectionLost;
  final void Function(String participantId)? onParticipantJoined;
  final void Function(String participantId)? onParticipantLeft;
  final void Function(SDKConnectNetworkState network)? onNetworkQualityChanged;
  final void Function(bool enabled)? onLocalAudioChanged;
  final void Function(bool enabled)? onRemoteAudioChanged;
  final void Function(bool enabled)? onLocalVideoChanged;
  final void Function(bool enabled)? onRemoteVideoChanged;
  final void Function(SDKConnectAudioRoute route)? onAudioRouteChanged;
  final void Function(String warning, CallState callState)? onCallWarning;
  final void Function(String reason, CallState callState)? onCallRecovered;
}

class SDKConnect {
  /// Creates SDKConnect with an externally managed [CallEngine].
  ///
  /// Ownership boundary:
  /// - Business signaling (invite/accept/reject) stays outside SDKConnect.
  /// - SDKConnect owns media-session lifecycle.
  /// - Widgets/presentation only render observed runtime state.
  SDKConnect({
    required String localUserId,
    required CallEngine callEngine,
    required SDKConnectTokenProvider tokenProvider,
    SDKConnectCallbacks callbacks = const SDKConnectCallbacks(),
  }) : _callEngine = callEngine,
       _callbacks = callbacks,
       _localUserId = localUserId,
       _runtimeState = SDKConnectRuntimeState.fromCallState(
         callEngine.state,
         localUserId: localUserId,
       ),
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
      VideoCallSdk(voiceSdk: _voiceSdk, callEngine: _callEngine),
    );
    _bindRuntimeStateStreams();
  }

  factory SDKConnect.create({
    required String localUserId,
    required SDKConnectTokenProvider tokenProvider,
    SDKConnectCallbacks callbacks = const SDKConnectCallbacks(),
    SDKConnectReliabilityConfig reliability =
        const SDKConnectReliabilityConfig(),
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
  }) : _callEngine = callEngine,
       _callbacks = callbacks,
       _localUserId = localUserId,
       _runtimeState = SDKConnectRuntimeState.fromCallState(
         callEngine.state,
         localUserId: localUserId,
       ),
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
      VideoCallSdk(voiceSdk: _voiceSdk, callEngine: _callEngine),
    );
    _bindRuntimeStateStreams();
  }

  final CallEngine _callEngine;
  final SDKConnectCallbacks _callbacks;
  final String _localUserId;
  final bool _ownsEngine;
  final StreamController<SDKConnectEvent> _eventsController =
      StreamController<SDKConnectEvent>.broadcast();
  final StreamController<SDKConnectRuntimeState> _runtimeController =
      StreamController<SDKConnectRuntimeState>.broadcast();

  late final VoiceCallSdk _voiceSdk;
  late final SDKConnectVoiceApi voice;
  late final SDKConnectVideoApi video;

  StreamSubscription<CallState>? _stateSubscription;
  StreamSubscription<CallEngineEvent>? _engineEventSubscription;

  SDKConnectRuntimeState _runtimeState;
  SDKConnectCallType _nextOutgoingCallType = SDKConnectCallType.voice;
  SDKConnectConnectionState? _lastConnectionState;
  String? _lastConnectionLostFingerprint;
  bool _isDisposed = false;

  CallState get state => _voiceSdk.state;
  Stream<CallState> get states => _voiceSdk.states;
  Stream<SDKConnectEvent> get events => _eventsController.stream;
  SDKConnectRuntimeState get runtimeState => _runtimeState;
  Stream<SDKConnectRuntimeState> get runtimeStates => _runtimeController.stream;
  SDKConnectConnectionState get connectionState =>
      _runtimeState.connectionState;
  SDKConnectParticipantState get participants => _runtimeState.participants;
  SDKConnectMediaState get media => _runtimeState.media;
  SDKConnectNetworkState get network => _runtimeState.network;

  Future<void> initialize({String? localUserId}) {
    return _voiceSdk.initialize(localUserId: localUserId);
  }

  Future<void> startCall({
    required String peerId,
    String? callId,
    SDKConnectCallType callType = SDKConnectCallType.voice,
  }) {
    return _startCallInternal(
      peerId: peerId,
      callId: callId,
      callType: callType,
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

    await _engineEventSubscription?.cancel();
    await _stateSubscription?.cancel();
    await video._dispose();
    await _voiceSdk.dispose();
    if (_ownsEngine) {
      await _callEngine.dispose();
    }
    await _runtimeController.close();
    await _eventsController.close();
  }

  void _bindRuntimeStateStreams() {
    _stateSubscription = _callEngine.states.listen(_handleStateSnapshotChanged);
    _engineEventSubscription = _callEngine.events.listen(_handleEngineEvent);
    _emitRuntimeState();
  }

  void _handleStateSnapshotChanged(CallState state) {
    final nextConnection = SDKConnectRuntimeState.mapConnectionState(state);
    final nextRuntime = _runtimeState.copyWith(
      callState: state,
      connectionState: nextConnection,
      participants: _runtimeState.participants.copyWith(
        localParticipantId: _localUserId,
        remoteParticipantId: state.session?.peerId,
        hasRemoteParticipant:
            _runtimeState.participants.hasRemoteParticipant &&
            (state.phase == CallPhase.connected ||
                state.phase == CallPhase.reconnecting),
      ),
      media: _runtimeState.media.copyWith(
        localAudioEnabled: !state.isMuted,
        localVideoEnabled: state.isVideoEnabled,
      ),
      network: _runtimeState.network.copyWith(score: state.networkScore),
    );

    _runtimeState = nextRuntime;
    _emitRuntimeState();

    if (_lastConnectionState != nextConnection) {
      _callbacks.onConnectionStateChanged?.call(nextConnection, state);
      _lastConnectionState = nextConnection;
    }

    if (_isConnectionLostState(state)) {
      final callId = state.session?.callId ?? 'no_call';
      final reason = state.reason ?? 'unknown';
      final fingerprint = '${state.phase.name}::$callId::$reason';
      if (_lastConnectionLostFingerprint != fingerprint) {
        _lastConnectionLostFingerprint = fingerprint;
        _callbacks.onConnectionLost?.call(state, state.reason);
      }
    } else {
      _lastConnectionLostFingerprint = null;
    }
  }

  void _handleEngineEvent(CallEngineEvent event) {
    switch (event.type) {
      case CallEngineEventType.participantJoined:
        final participantId =
            event.reason ?? _runtimeState.callState.session?.peerId ?? 'remote';
        _runtimeState = _runtimeState.copyWith(
          participants: _runtimeState.participants.copyWith(
            remoteParticipantId: participantId,
            hasRemoteParticipant: true,
          ),
        );
        _callbacks.onParticipantJoined?.call(participantId);
        _emitRuntimeState();
        return;
      case CallEngineEventType.participantLeft:
        final participantId =
            event.reason ??
            _runtimeState.participants.remoteParticipantId ??
            'remote';
        _runtimeState = _runtimeState.copyWith(
          participants: _runtimeState.participants.copyWith(
            hasRemoteParticipant: false,
          ),
          media: _runtimeState.media.copyWith(
            remoteAudioEnabled: false,
            remoteVideoEnabled: false,
          ),
        );
        _callbacks.onParticipantLeft?.call(participantId);
        _emitRuntimeState();
        return;
      case CallEngineEventType.networkQualityChanged:
        _runtimeState = _runtimeState.copyWith(
          network: _runtimeState.network.copyWith(score: event.networkScore),
        );
        _callbacks.onNetworkQualityChanged?.call(_runtimeState.network);
        _emitRuntimeState();
        return;
      case CallEngineEventType.networkDegraded:
        _runtimeState = _runtimeState.copyWith(
          network: _runtimeState.network.copyWith(
            score: event.networkScore,
            isWeak: true,
            isRecovered: false,
          ),
        );
        _callbacks.onCallWarning?.call(
          'network_degraded',
          _runtimeState.callState,
        );
        _callbacks.onNetworkQualityChanged?.call(_runtimeState.network);
        _emitRuntimeState();
        return;
      case CallEngineEventType.networkRecovered:
        _runtimeState = _runtimeState.copyWith(
          network: _runtimeState.network.copyWith(
            score: event.networkScore,
            isWeak: false,
            isRecovered: true,
          ),
        );
        _callbacks.onCallRecovered?.call(
          'network_recovered',
          _runtimeState.callState,
        );
        _callbacks.onNetworkQualityChanged?.call(_runtimeState.network);
        _emitRuntimeState();
        return;
      case CallEngineEventType.reconnecting:
        _callbacks.onReconnecting?.call(_runtimeState.callState);
        _callbacks.onCallWarning?.call('reconnecting', _runtimeState.callState);
        return;
      case CallEngineEventType.recovered:
        _callbacks.onReconnected?.call(_runtimeState.callState);
        _callbacks.onCallRecovered?.call(
          'reconnected',
          _runtimeState.callState,
        );
        return;
      case CallEngineEventType.localAudioChanged:
        final enabled = event.reason != 'local_audio_disabled';
        _runtimeState = _runtimeState.copyWith(
          media: _runtimeState.media.copyWith(localAudioEnabled: enabled),
        );
        _callbacks.onLocalAudioChanged?.call(enabled);
        _emitRuntimeState();
        return;
      case CallEngineEventType.remoteAudioChanged:
        final enabled = event.reason == 'remote_audio_enabled';
        _runtimeState = _runtimeState.copyWith(
          media: _runtimeState.media.copyWith(remoteAudioEnabled: enabled),
        );
        _callbacks.onRemoteAudioChanged?.call(enabled);
        _emitRuntimeState();
        return;
      case CallEngineEventType.localVideoChanged:
        final enabled = event.reason != 'local_video_disabled';
        _runtimeState = _runtimeState.copyWith(
          media: _runtimeState.media.copyWith(localVideoEnabled: enabled),
        );
        _callbacks.onLocalVideoChanged?.call(enabled);
        _emitRuntimeState();
        return;
      case CallEngineEventType.remoteVideoChanged:
        final enabled = event.reason == 'remote_video_enabled';
        _runtimeState = _runtimeState.copyWith(
          media: _runtimeState.media.copyWith(remoteVideoEnabled: enabled),
        );
        _callbacks.onRemoteVideoChanged?.call(enabled);
        _emitRuntimeState();
        return;
      case CallEngineEventType.audioRouteChanged:
        final route = _toPublicAudioRoute(event.audioRoute);
        _runtimeState = _runtimeState.copyWith(
          media: _runtimeState.media.copyWith(audioRoute: route),
        );
        _callbacks.onAudioRouteChanged?.call(route);
        _emitRuntimeState();
        return;
      case CallEngineEventType.reconnectFailed:
        return;
      case CallEngineEventType.lifecycleChanged:
      case CallEngineEventType.interruptionStarted:
      case CallEngineEventType.interruptionRecovered:
      case CallEngineEventType.mediaSessionRestored:
      case CallEngineEventType.iceRecoveryStarted:
      case CallEngineEventType.iceRecovered:
      case CallEngineEventType.audioPriorityEnabled:
      case CallEngineEventType.audioPriorityDisabled:
      case CallEngineEventType.tokenRefreshRequested:
      case CallEngineEventType.tokenRefreshed:
      case CallEngineEventType.tokenRefreshFailed:
        return;
    }
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

  SDKConnectAudioRoute _toPublicAudioRoute(CallAudioRoute? route) {
    return switch (route) {
      CallAudioRoute.earpiece => SDKConnectAudioRoute.earpiece,
      CallAudioRoute.speaker => SDKConnectAudioRoute.speaker,
      CallAudioRoute.bluetooth => SDKConnectAudioRoute.bluetooth,
      CallAudioRoute.wiredHeadset => SDKConnectAudioRoute.wiredHeadset,
      CallAudioRoute.unknown => SDKConnectAudioRoute.unknown,
      null => SDKConnectAudioRoute.unknown,
    };
  }

  bool _isConnectionLostState(CallState state) {
    if (state.phase != CallPhase.disconnected &&
        state.phase != CallPhase.failed) {
      return false;
    }

    const expectedEndReasons = <String>{
      'ended_by_user',
      'sdk_disposed',
      'end_cleanup',
    };

    return !expectedEndReasons.contains(state.reason);
  }

  void _emitRuntimeState() {
    if (!_runtimeController.isClosed) {
      _runtimeController.add(_runtimeState);
    }
  }

  void _emitEvent(SDKConnectEvent event) {
    _callbacks.onEvent?.call(event);
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  void _ensureVideoOrVoice(SDKConnectCallType callType) {
    if (callType == SDKConnectCallType.voice ||
        callType == SDKConnectCallType.video) {
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

  Future<void> startCall({required String peerId, String? callId}) {
    return _sdk._startCallInternal(
      peerId: peerId,
      callId: callId,
      callType: SDKConnectCallType.voice,
    );
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

  Future<void> startCall({required String peerId, String? callId}) {
    return _sdk._startCallInternal(
      peerId: peerId,
      callId: callId,
      callType: SDKConnectCallType.video,
    );
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
