import 'dart:async';
import 'dart:math';

import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
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

typedef VoiceCallSignalValidator = FutureOr<bool> Function(VoiceCallSignal signal);

enum VoiceCallSignalType {
  invite,
  accept,
  reject,
  end,
}

class VoiceCallSignal {
  const VoiceCallSignal({
    required this.type,
    required this.callId,
    required this.fromUserId,
    required this.toUserId,
    this.reason,
  });

  final VoiceCallSignalType type;
  final String callId;
  final String fromUserId;
  final String toUserId;
  final String? reason;
}

abstract class VoiceCallSignalingTransport {
  Stream<VoiceCallSignal> get signals;

  Future<void> send(VoiceCallSignal signal);

  Future<void> dispose();
}

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
  dialing,
  ringing,
  connected,
  ended,
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
  failed,
}

class VoiceCallTokenEvent {
  const VoiceCallTokenEvent({
    required this.type,
    required this.request,
    this.error,
  });

  final VoiceCallTokenEventType type;
  final VoiceCallTokenRequest request;
  final Object? error;
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

class VoiceCallSdk {
  VoiceCallSdk({
    required String localUserId,
    required CallEngine callEngine,
    required VoiceCallSignalingTransport signaling,
    required VoiceCallTokenProvider tokenProvider,
    required VoiceCallSignalValidator signalValidator,
    VoiceCallCallbacks callbacks = const VoiceCallCallbacks(),
  })  : _callEngine = callEngine,
        _signaling = signaling,
        _tokenProvider = tokenProvider,
        _callbacks = callbacks,
        _signalValidator = signalValidator,
        _localUserId = localUserId,
        _ownsEngine = false,
        _ownsSignaling = false {
    _initializeInternal();
  }

  VoiceCallSdk._owned({
    required String localUserId,
    required CallEngine callEngine,
    required VoiceCallSignalingTransport signaling,
    required VoiceCallTokenProvider tokenProvider,
    required VoiceCallSignalValidator signalValidator,
    required VoiceCallCallbacks callbacks,
    required bool ownsSignaling,
  })  : _callEngine = callEngine,
        _signaling = signaling,
        _tokenProvider = tokenProvider,
        _callbacks = callbacks,
        _signalValidator = signalValidator,
        _localUserId = localUserId,
        _ownsEngine = true,
        _ownsSignaling = ownsSignaling {
    _initializeInternal();
  }

  factory VoiceCallSdk.liveKit({
    required String localUserId,
    required VoiceCallTokenProvider tokenProvider,
    required VoiceCallSignalValidator signalValidator,
    VoiceCallSignalingTransport? signaling,
    VoiceCallCallbacks callbacks = const VoiceCallCallbacks(),
    StructuredLogger? logger,
    DateTime Function()? clock,
  }) {
    final resolvedSignaling = signaling ?? InMemoryVoiceCallSignalingTransport();
    final callEngine = CallEngine(
      mediaEngine: createLiveKitMediaEngine(),
      logger: logger,
      clock: clock,
    );

    return VoiceCallSdk._owned(
      localUserId: localUserId,
      callEngine: callEngine,
      signaling: resolvedSignaling,
      tokenProvider: tokenProvider,
      callbacks: callbacks,
      ownsSignaling: signaling == null,
      signalValidator: signalValidator,
    );
  }

  final CallEngine _callEngine;
  final VoiceCallSignalingTransport _signaling;
  final VoiceCallTokenProvider _tokenProvider;
  final VoiceCallCallbacks _callbacks;
  final VoiceCallSignalValidator _signalValidator;
  final bool _ownsEngine;
  final bool _ownsSignaling;

  StreamSubscription<CallState>? _stateSubscription;
  StreamSubscription<VoiceCallSignal>? _signalSubscription;

  bool _isInitialized = false;
  bool _isDisposed = false;
  final Set<String> _processedSignalKeys = <String>{};
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

    _callbacks.onConnection?.call(
      VoiceCallConnectionEvent(
        type: VoiceCallConnectionEventType.initializing,
        state: _callEngine.state,
      ),
    );

    _stateSubscription = _callEngine.states.listen(_handleStateChanged);
    _signalSubscription = _signaling.signals.listen(_handleSignal);

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

      await _callEngine.startOutgoing(
        callId: resolvedCallId,
        peerId: peerId,
        roomUrl: credentials.roomUrl,
        token: credentials.token,
      );

      await _signaling.send(
        VoiceCallSignal(
          type: VoiceCallSignalType.invite,
          callId: resolvedCallId,
          fromUserId: _localUserId,
          toUserId: peerId,
        ),
      );

      _callbacks.onUser?.call(
        VoiceCallUserEvent(
          type: VoiceCallUserEventType.outgoingStarted,
          callId: resolvedCallId,
          peerId: peerId,
        ),
      );
    } catch (error, stackTrace) {
      _emitError('startCall', error, stackTrace);
      rethrow;
    }
  }

  Future<void> acceptCall() async {
    _ensureReady('acceptCall');

    final session = _callEngine.state.session;
    if (_callEngine.state.phase != CallPhase.ringing || session == null) {
      throw CallLifecycleException('No incoming call to accept.');
    }

    final request = VoiceCallTokenRequest(
      callId: session.callId,
      peerId: session.peerId,
      direction: CallDirection.incoming,
    );

    try {
      final credentials = await _resolveCredentials(request);

      await _callEngine.acceptIncoming(
        roomUrl: credentials.roomUrl,
        token: credentials.token,
      );

      await _signaling.send(
        VoiceCallSignal(
          type: VoiceCallSignalType.accept,
          callId: session.callId,
          fromUserId: _localUserId,
          toUserId: session.peerId,
        ),
      );

      _callbacks.onUser?.call(
        VoiceCallUserEvent(
          type: VoiceCallUserEventType.accepted,
          callId: session.callId,
          peerId: session.peerId,
        ),
      );
    } catch (error, stackTrace) {
      _emitError('acceptCall', error, stackTrace);
      rethrow;
    }
  }

  Future<void> rejectCall({String reason = 'rejected'}) async {
    _ensureReady('rejectCall');

    final session = _callEngine.state.session;
    if (_callEngine.state.phase != CallPhase.ringing || session == null) {
      throw CallLifecycleException('No incoming call to reject.');
    }

    try {
      await _signaling.send(
        VoiceCallSignal(
          type: VoiceCallSignalType.reject,
          callId: session.callId,
          fromUserId: _localUserId,
          toUserId: session.peerId,
          reason: reason,
        ),
      );

      await _callEngine.rejectIncoming(reason: reason);

      _callbacks.onUser?.call(
        VoiceCallUserEvent(
          type: VoiceCallUserEventType.rejected,
          callId: session.callId,
          peerId: session.peerId,
          reason: reason,
        ),
      );
    } catch (error, stackTrace) {
      _emitError('rejectCall', error, stackTrace);
      rethrow;
    }
  }

  Future<void> endCall({String reason = 'ended_by_user'}) async {
    _ensureReady('endCall');

    final session = _callEngine.state.session;
    if (session == null) {
      return;
    }

    try {
      await _signaling.send(
        VoiceCallSignal(
          type: VoiceCallSignalType.end,
          callId: session.callId,
          fromUserId: _localUserId,
          toUserId: session.peerId,
          reason: reason,
        ),
      );

      await _callEngine.endCall(reason: reason);
    } catch (error, stackTrace) {
      _emitError('endCall', error, stackTrace);
      rethrow;
    }
  }

  Future<void> toggleMute() async {
    _ensureReady('toggleMute');
    await _callEngine.setMuted(!_callEngine.state.isMuted);
  }

  Future<void> toggleSpeaker() async {
    _ensureReady('toggleSpeaker');
    await _callEngine.setSpeakerOn(!_callEngine.state.isSpeakerOn);
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
    await _signalSubscription?.cancel();
    if (_ownsSignaling) {
      await _signaling.dispose();
    }
    if (_ownsEngine) {
      await _callEngine.dispose();
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
    } catch (error, stackTrace) {
      _callbacks.onToken?.call(
        VoiceCallTokenEvent(
          type: VoiceCallTokenEventType.failed,
          request: request,
          error: error,
        ),
      );
      _emitError('resolveToken', error, stackTrace);
      rethrow;
    }
  }

  Future<void> _handleSignal(VoiceCallSignal signal) async {
    if (!_isInitialized || _isDisposed) {
      return;
    }

    if (signal.toUserId != _localUserId || !_isValidSignalEnvelope(signal)) {
      return;
    }

    final allowedByValidator = await _signalValidator(signal);
    if (!allowedByValidator) {
      return;
    }

    final signalKey = _signalKey(signal);
    if (!_processedSignalKeys.add(signalKey)) {
      return;
    }

    try {
      switch (signal.type) {
        case VoiceCallSignalType.invite:
          await _onInvite(signal);
        case VoiceCallSignalType.accept:
          _onAccept(signal);
        case VoiceCallSignalType.reject:
          await _onReject(signal);
        case VoiceCallSignalType.end:
          await _onEnd(signal);
      }
    } catch (error, stackTrace) {
      _emitError('signal.${signal.type.name}', error, stackTrace);
    }
  }

  Future<void> _onInvite(VoiceCallSignal signal) async {
    if (_callEngine.state.phase != CallPhase.idle) {
      await _signaling.send(
        VoiceCallSignal(
          type: VoiceCallSignalType.reject,
          callId: signal.callId,
            fromUserId: _localUserId,
          toUserId: signal.fromUserId,
          reason: 'busy',
        ),
      );
      return;
    }

    _callEngine.onIncoming(callId: signal.callId, peerId: signal.fromUserId);
    _callbacks.onUser?.call(
      VoiceCallUserEvent(
        type: VoiceCallUserEventType.incomingReceived,
        callId: signal.callId,
        peerId: signal.fromUserId,
      ),
    );
  }

  void _onAccept(VoiceCallSignal signal) {
    final state = _callEngine.state;
    final session = state.session;
    if (state.phase != CallPhase.dialing || session == null) {
      return;
    }

    if (session.callId != signal.callId || session.peerId != signal.fromUserId) {
      return;
    }

    _callEngine.markOutgoingConnected();
    _callbacks.onUser?.call(
      VoiceCallUserEvent(
        type: VoiceCallUserEventType.accepted,
        callId: signal.callId,
        peerId: signal.fromUserId,
      ),
    );
  }

  Future<void> _onReject(VoiceCallSignal signal) async {
    final state = _callEngine.state;
    final session = state.session;
    if (session == null) {
      return;
    }

    if (session.callId != signal.callId || session.peerId != signal.fromUserId) {
      return;
    }

    if (state.phase == CallPhase.dialing || state.phase == CallPhase.connected) {
      await _callEngine.endCall(reason: signal.reason ?? 'rejected_by_remote');
      _callbacks.onUser?.call(
        VoiceCallUserEvent(
          type: VoiceCallUserEventType.rejected,
          callId: signal.callId,
          peerId: signal.fromUserId,
          reason: signal.reason,
        ),
      );
    }
  }

  Future<void> _onEnd(VoiceCallSignal signal) async {
    final state = _callEngine.state;
    final session = state.session;
    if (session == null) {
      return;
    }

    if (session.callId != signal.callId || session.peerId != signal.fromUserId) {
      return;
    }

    if (state.phase == CallPhase.dialing ||
        state.phase == CallPhase.ringing ||
        state.phase == CallPhase.connected) {
      await _callEngine.endCall(reason: signal.reason ?? 'ended_by_remote');
      _callbacks.onUser?.call(
        VoiceCallUserEvent(
          type: VoiceCallUserEventType.ended,
          callId: signal.callId,
          peerId: signal.fromUserId,
          reason: signal.reason,
        ),
      );
    }
  }

  void _handleStateChanged(CallState state) {
    if (_isDisposed) {
      return;
    }

    final connectionType = switch (state.phase) {
      CallPhase.idle => VoiceCallConnectionEventType.idle,
      CallPhase.dialing => VoiceCallConnectionEventType.dialing,
      CallPhase.ringing => VoiceCallConnectionEventType.ringing,
      CallPhase.connected => VoiceCallConnectionEventType.connected,
      CallPhase.ended => VoiceCallConnectionEventType.ended,
    };

    _callbacks.onConnection?.call(
      VoiceCallConnectionEvent(type: connectionType, state: state),
    );

    if (state.phase == CallPhase.ended && state.reason == 'p2p_limit_exceeded') {
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
        stackTrace: stackTrace,
      ),
    );
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

  bool _isValidSignalEnvelope(VoiceCallSignal signal) {
    return signal.callId.trim().isNotEmpty &&
        signal.fromUserId.trim().isNotEmpty &&
        signal.toUserId.trim().isNotEmpty &&
        signal.fromUserId != signal.toUserId;
  }

  String _signalKey(VoiceCallSignal signal) {
    return '${signal.type.name}|${signal.callId}|${signal.fromUserId}|${signal.toUserId}|${signal.reason ?? ''}';
  }
}

class InMemoryVoiceCallSignalingTransport implements VoiceCallSignalingTransport {
  InMemoryVoiceCallSignalingTransport();

  final StreamController<VoiceCallSignal> _controller =
      StreamController<VoiceCallSignal>.broadcast();

  @override
  Stream<VoiceCallSignal> get signals => _controller.stream;

  @override
  Future<void> send(VoiceCallSignal signal) async {
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
