import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/enums/call_type.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/presentation/voice/voice_call_controller.dart';
import 'package:sdk_connect/sdk/livekit_media_engine_factory.dart';

class VoiceCallCredentials {
  const VoiceCallCredentials({
    required this.roomUrl,
    required this.token,
  });

  final String roomUrl;
  final String token;
}

class VoiceCallTokenRequest {
  const VoiceCallTokenRequest({
    required this.callId,
    required this.peerId,
    required this.direction,
  });

  final String callId;
  final String peerId;
  final CallDirection direction;
}

typedef VoiceCallTokenProvider = Future<VoiceCallCredentials> Function(
  VoiceCallTokenRequest request,
);

enum VoiceCallUserEventType {
  outgoingStarted,
  incomingReceived,
  accepted,
  rejected,
  ended,
  p2pLimitExceeded,
}

class VoiceCallUserEvent {
  const VoiceCallUserEvent({
    required this.type,
    required this.callId,
    required this.peerId,
    this.reason,
  });

  final VoiceCallUserEventType type;
  final String callId;
  final String peerId;
  final String? reason;
}

enum VoiceCallConnectionEventType {
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

class VoiceCallConnectionEvent {
  const VoiceCallConnectionEvent({
    required this.type,
    required this.state,
  });

  final VoiceCallConnectionEventType type;
  final CallState state;
}

enum VoiceCallTokenEventType {
  requested,
  resolved,
  refreshRequested,
  refreshed,
  refreshFailed,
  failed,
}

class VoiceCallTokenEvent {
  const VoiceCallTokenEvent({
    required this.type,
    required this.request,
    this.error,
    this.reconnectAttempt,
  });

  final VoiceCallTokenEventType type;
  final VoiceCallTokenRequest request;
  final Object? error;
  final int? reconnectAttempt;
}

class VoiceCallErrorEvent {
  const VoiceCallErrorEvent({
    required this.operation,
    required this.error,
    this.stackTrace,
  });

  final String operation;
  final Object error;
  final StackTrace? stackTrace;
}

class VoiceCallCallbacks {
  const VoiceCallCallbacks({
    this.onUser,
    this.onConnection,
    this.onError,
    this.onToken,
  });

  final void Function(VoiceCallUserEvent event)? onUser;
  final void Function(VoiceCallConnectionEvent event)? onConnection;
  final void Function(VoiceCallErrorEvent event)? onError;
  final void Function(VoiceCallTokenEvent event)? onToken;
}

class VoiceCallSdk with WidgetsBindingObserver {
  VoiceCallSdk({
    required String localUserId,
    required CallEngine callEngine,
    required VoiceCallTokenProvider tokenProvider,
    VoiceCallCallbacks callbacks = const VoiceCallCallbacks(),
  })  : _callEngine = callEngine,
        _tokenProvider = tokenProvider,
        _callbacks = callbacks,
        _localUserId = localUserId,
        _ownsEngine = false {
    _initializeInternal();
  }

  VoiceCallSdk._owned({
    required String localUserId,
    required CallEngine callEngine,
    required VoiceCallTokenProvider tokenProvider,
    required VoiceCallCallbacks callbacks,
  })  : _callEngine = callEngine,
        _tokenProvider = tokenProvider,
        _callbacks = callbacks,
        _localUserId = localUserId,
        _ownsEngine = true {
    _initializeInternal();
  }

  factory VoiceCallSdk.liveKit({
    required String localUserId,
    required VoiceCallTokenProvider tokenProvider,
    VoiceCallCallbacks callbacks = const VoiceCallCallbacks(),
    StructuredLogger? logger,
    DateTime Function()? clock,
    CallReconnectPolicy reconnectPolicy = const CallReconnectPolicy(),
    CallNetworkThresholds networkThresholds = const CallNetworkThresholds(),
  }) {
    final callEngine = CallEngine(
      mediaEngine: createLiveKitMediaEngine(),
      logger: logger,
      clock: clock,
      reconnectPolicy: reconnectPolicy,
      networkThresholds: networkThresholds,
      tokenRefresher: (session, reconnectAttempt) async {
        final credentials = await tokenProvider(
          VoiceCallTokenRequest(
            callId: session.callId,
            peerId: session.peerId,
            direction: session.direction,
          ),
        );
        return credentials.token;
      },
    );

    return VoiceCallSdk._owned(
      localUserId: localUserId,
      callEngine: callEngine,
      tokenProvider: tokenProvider,
      callbacks: callbacks,
    );
  }

  final CallEngine _callEngine;
  final VoiceCallTokenProvider _tokenProvider;
  final VoiceCallCallbacks _callbacks;
  final bool _ownsEngine;

  StreamSubscription<CallState>? _stateSubscription;
  StreamSubscription<CallEngineEvent>? _engineEventSubscription;

  bool _isInitialized = false;
  bool _isDisposed = false;
  bool _isLifecycleObserverRegistered = false;
  final String _localUserId;

  CallState get state => _callEngine.state;
  Stream<CallState> get states => _callEngine.states;

  VoiceCallController createController() {
    return VoiceCallController(engine: _callEngine);
  }

  Future<void> initialize({String? localUserId}) async {
    _ensureNotDisposed('initialize');
    if (localUserId != null && localUserId != _localUserId) {
      throw StateError('VoiceCallSdk localUserId is immutable.');
    }
  }

  void _initializeInternal() {
    if (_isInitialized) {
      return;
    }

    _registerLifecycleObserver();

    _callbacks.onConnection?.call(
      VoiceCallConnectionEvent(
        type: VoiceCallConnectionEventType.initializing,
        state: _callEngine.state,
      ),
    );

    _stateSubscription = _callEngine.states.listen(_handleStateChanged);
    _engineEventSubscription = _callEngine.events.listen(_handleEngineEvent);

    _isInitialized = true;

    _callbacks.onConnection?.call(
      VoiceCallConnectionEvent(
        type: VoiceCallConnectionEventType.ready,
        state: _callEngine.state,
      ),
    );
  }

  Future<void> startCall({
    required String peerId,
    String? callId,
    CallType callType = CallType.voice,
  }) async {
    _ensureReady('startCall');

    final resolvedCallId = callId ?? _generateCallId();
    final request = VoiceCallTokenRequest(
      callId: resolvedCallId,
      peerId: peerId,
      direction: CallDirection.outgoing,
    );

    try {
      final credentials = await _resolveCredentials(request);

      await _callEngine.connectSession(
        callId: resolvedCallId,
        peerId: peerId,
        roomUrl: credentials.roomUrl,
        token: credentials.token,
        direction: CallDirection.outgoing,
        callType: callType,
      );

      _callbacks.onUser?.call(
        VoiceCallUserEvent(
          type: VoiceCallUserEventType.outgoingStarted,
          callId: resolvedCallId,
          peerId: peerId,
        ),
      );
    } catch (error) {
      _emitError('startCall', _sanitizeError(error), null);
      rethrow;
    }
  }

  Future<void> acceptCall() async {
    throw CallLifecycleException(
      'acceptCall is removed from VoiceCallSdk. Signaling/invitation flow is handled externally.',
    );
  }

  Future<void> rejectCall({String reason = 'rejected'}) async {
    throw CallLifecycleException(
      'rejectCall is removed from VoiceCallSdk. Signaling/invitation flow is handled externally.',
    );
  }

  Future<void> endCall({String reason = 'ended_by_user'}) async {
    _ensureReady('endCall');

    final session = _callEngine.state.session;
    if (session == null) {
      return;
    }

    try {
      await _callEngine.endCall(reason: reason);
    } catch (error) {
      _emitError('endCall', _sanitizeError(error), null);
      rethrow;
    }
  }

  Future<void> setMuted(bool muted) async {
    _ensureReady('setMuted');
    await _callEngine.setMuted(muted);
  }

  Future<void> toggleMute() async {
    await setMuted(!_callEngine.state.isMuted);
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    _ensureReady('setSpeakerOn');
    await _callEngine.setSpeakerOn(speakerOn);
  }

  Future<void> toggleSpeaker() async {
    await setSpeakerOn(!_callEngine.state.isSpeakerOn);
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    final phase = _callEngine.state.phase;
    if (phase != CallPhase.idle) {
      try {
        await _callEngine.endCall(reason: 'sdk_disposed');
      } on CallLifecycleException {
        await _callEngine.dispose();
      }
    }
    await _stateSubscription?.cancel();
    await _engineEventSubscription?.cancel();
    _unregisterLifecycleObserver();
    if (_ownsEngine) {
      await _callEngine.dispose();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isDisposed) {
      return;
    }
    unawaited(_callEngine.onAppLifecycleChanged(state.toEngineLifecycleState()));
  }

  void _registerLifecycleObserver() {
    if (_isLifecycleObserverRegistered) {
      return;
    }
    try {
      WidgetsBinding.instance.addObserver(this);
      _isLifecycleObserverRegistered = true;
    } catch (_) {
      _isLifecycleObserverRegistered = false;
    }
  }

  void _unregisterLifecycleObserver() {
    if (!_isLifecycleObserverRegistered) {
      return;
    }
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {
      // Binding may already be torn down.
    } finally {
      _isLifecycleObserverRegistered = false;
    }
  }

  Future<VoiceCallCredentials> _resolveCredentials(
    VoiceCallTokenRequest request,
  ) async {
    _callbacks.onToken?.call(
      VoiceCallTokenEvent(
        type: VoiceCallTokenEventType.requested,
        request: request,
      ),
    );

    try {
      final credentials = await _tokenProvider(request);
      _callbacks.onToken?.call(
        VoiceCallTokenEvent(
          type: VoiceCallTokenEventType.resolved,
          request: request,
        ),
      );
      return credentials;
    } catch (error) {
      final sanitized = _sanitizeError(error);
      _callbacks.onToken?.call(
        VoiceCallTokenEvent(
          type: VoiceCallTokenEventType.failed,
          request: request,
          error: sanitized,
        ),
      );
      _emitError('resolveToken', sanitized, null);
      rethrow;
    }
  }

  void _handleStateChanged(CallState state) {
    if (_isDisposed) {
      return;
    }

    final connectionType = switch (state.phase) {
      CallPhase.idle => VoiceCallConnectionEventType.idle,
      CallPhase.connecting => VoiceCallConnectionEventType.connecting,
      CallPhase.connected => VoiceCallConnectionEventType.connected,
      CallPhase.reconnecting => VoiceCallConnectionEventType.reconnecting,
      CallPhase.disconnected => VoiceCallConnectionEventType.disconnected,
      CallPhase.failed => VoiceCallConnectionEventType.failed,
    };

    _callbacks.onConnection?.call(
      VoiceCallConnectionEvent(type: connectionType, state: state),
    );

    if ((state.phase == CallPhase.failed || state.phase == CallPhase.disconnected) &&
        state.reason == 'p2p_limit_exceeded') {
      final session = state.session;
      if (session != null) {
        _callbacks.onUser?.call(
          VoiceCallUserEvent(
            type: VoiceCallUserEventType.p2pLimitExceeded,
            callId: session.callId,
            peerId: session.peerId,
            reason: state.reason,
          ),
        );
      }
    }
  }

  void _emitError(String operation, Object error, StackTrace? stackTrace) {
    _callbacks.onError?.call(
      VoiceCallErrorEvent(
        operation: operation,
        error: error,
        stackTrace: null,
      ),
    );
  }

  String _sanitizeError(Object error) {
    final text = error.toString();
    final jwtRegex = RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
    return text.replaceAll(jwtRegex, '[redacted_jwt]');
  }

  Future<void> _handleEngineEvent(CallEngineEvent event) async {
    if (_isDisposed) {
      return;
    }

    final session = _callEngine.state.session;
    switch (event.type) {
      case CallEngineEventType.lifecycleChanged:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.lifecycleChanged,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.interruptionStarted:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.interruptionStarted,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.interruptionRecovered:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.interruptionRecovered,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.mediaSessionRestored:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.mediaSessionRestored,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.audioRouteChanged:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.audioRouteChanged,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.participantJoined:
      case CallEngineEventType.participantLeft:
      case CallEngineEventType.networkQualityChanged:
      case CallEngineEventType.localAudioChanged:
      case CallEngineEventType.remoteAudioChanged:
      case CallEngineEventType.localVideoChanged:
      case CallEngineEventType.remoteVideoChanged:
        return;
      case CallEngineEventType.reconnecting:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.reconnecting,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.recovered:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.recovered,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.reconnectFailed:
        _emitError(
          'reconnect.failed',
          StateError('Reconnect failed: ${event.reason ?? 'unknown'}'),
          null,
        );
        return;
      case CallEngineEventType.iceRecoveryStarted:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.iceRecoveryStarted,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.iceRecovered:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.iceRecovered,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.networkDegraded:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.networkDegraded,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.networkRecovered:
        _callbacks.onConnection?.call(
          VoiceCallConnectionEvent(
            type: VoiceCallConnectionEventType.networkRecovered,
            state: _callEngine.state,
          ),
        );
        return;
      case CallEngineEventType.audioPriorityEnabled:
      case CallEngineEventType.audioPriorityDisabled:
        // Audio priority state is reflected through CallState.
        return;
      case CallEngineEventType.tokenRefreshRequested:
        if (session == null) {
          return;
        }
        _callbacks.onToken?.call(
          VoiceCallTokenEvent(
            type: VoiceCallTokenEventType.refreshRequested,
            request: VoiceCallTokenRequest(
              callId: session.callId,
              peerId: session.peerId,
              direction: session.direction,
            ),
            reconnectAttempt: event.reconnectAttempt,
          ),
        );
        return;
      case CallEngineEventType.tokenRefreshed:
        if (session == null) {
          return;
        }
        _callbacks.onToken?.call(
          VoiceCallTokenEvent(
            type: VoiceCallTokenEventType.refreshed,
            request: VoiceCallTokenRequest(
              callId: session.callId,
              peerId: session.peerId,
              direction: session.direction,
            ),
            reconnectAttempt: event.reconnectAttempt,
          ),
        );
        return;
      case CallEngineEventType.tokenRefreshFailed:
        if (session == null) {
          return;
        }
        _callbacks.onToken?.call(
          VoiceCallTokenEvent(
            type: VoiceCallTokenEventType.refreshFailed,
            request: VoiceCallTokenRequest(
              callId: session.callId,
              peerId: session.peerId,
              direction: session.direction,
            ),
            error: event.error == null ? null : _sanitizeError(event.error!),
            reconnectAttempt: event.reconnectAttempt,
          ),
        );
        return;
    }
  }

  void _ensureReady(String action) {
    _ensureNotDisposed(action);
    if (!_isInitialized || _localUserId.isEmpty) {
      throw StateError('VoiceCallSdk is not initialized. Cannot call $action.');
    }
  }

  void _ensureNotDisposed(String action) {
    if (_isDisposed) {
      throw StateError('VoiceCallSdk is disposed. Cannot call $action.');
    }
  }

  String _generateCallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'call_$hex';
  }

}

extension on AppLifecycleState {
  CallAppLifecycleState toEngineLifecycleState() {
    return switch (this) {
      AppLifecycleState.resumed => CallAppLifecycleState.resumed,
      AppLifecycleState.inactive => CallAppLifecycleState.inactive,
      AppLifecycleState.hidden => CallAppLifecycleState.hidden,
      AppLifecycleState.paused => CallAppLifecycleState.paused,
      AppLifecycleState.detached => CallAppLifecycleState.detached,
    };
  }
}
