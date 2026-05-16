import 'dart:async';
import 'dart:convert';

import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/enums/call_type.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/core/models/call_session.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';

typedef CallTokenRefresher = Future<String> Function(
  CallSession session,
  int reconnectAttempt,
);

class CallReconnectPolicy {
  const CallReconnectPolicy({
    this.enabled = true,
    this.maxAttempts = 6,
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 12),
    this.graceTimeout = const Duration(seconds: 25),
    this.reconnectCooldown = const Duration(seconds: 15),
    this.tokenRefreshBeforeExpiry = const Duration(minutes: 2),
    this.enableIceRecovery = true,
  });

  final bool enabled;
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final Duration graceTimeout;
  final Duration reconnectCooldown;
  final Duration tokenRefreshBeforeExpiry;
  final bool enableIceRecovery;
}

class CallNetworkThresholds {
  const CallNetworkThresholds({
    this.weakScore = 35,
    this.stableScore = 65,
    this.stableDuration = const Duration(seconds: 8),
    this.audioPriorityBitrateKbps = 180,
    this.audioPriorityMaxVideoHeight = 180,
    this.audioPriorityMaxVideoFps = 12,
  });

  final int weakScore;
  final int stableScore;
  final Duration stableDuration;
  final int audioPriorityBitrateKbps;
  final int audioPriorityMaxVideoHeight;
  final int audioPriorityMaxVideoFps;
}

enum CallAppLifecycleState {
  resumed,
  inactive,
  paused,
  hidden,
  detached,
}

enum CallAudioRoute {
  earpiece,
  speaker,
  bluetooth,
  wiredHeadset,
  unknown,
}

enum CallEngineEventType {
  lifecycleChanged,
  participantJoined,
  participantLeft,
  interruptionStarted,
  interruptionRecovered,
  mediaSessionRestored,
  audioRouteChanged,
  networkQualityChanged,
  localAudioChanged,
  remoteAudioChanged,
  localVideoChanged,
  remoteVideoChanged,
  reconnecting,
  recovered,
  reconnectFailed,
  iceRecoveryStarted,
  iceRecovered,
  networkDegraded,
  networkRecovered,
  audioPriorityEnabled,
  audioPriorityDisabled,
  tokenRefreshRequested,
  tokenRefreshed,
  tokenRefreshFailed,
}

class CallEngineEvent {
  const CallEngineEvent({
    required this.type,
    required this.timestamp,
    this.callId,
    this.reason,
    this.reconnectAttempt,
    this.networkScore,
    this.error,
    this.lifecycleState,
    this.audioRoute,
  });

  final CallEngineEventType type;
  final String? callId;
  final String? reason;
  final int? reconnectAttempt;
  final int? networkScore;
  final Object? error;
  final CallAppLifecycleState? lifecycleState;
  final CallAudioRoute? audioRoute;
  final DateTime timestamp;
}

class CallEngine {
  CallEngine({
    required MediaEngine mediaEngine,
    StructuredLogger? logger,
    DateTime Function()? clock,
    CallReconnectPolicy reconnectPolicy = const CallReconnectPolicy(),
    CallNetworkThresholds networkThresholds = const CallNetworkThresholds(),
    CallTokenRefresher? tokenRefresher,
  })  : _mediaEngine = mediaEngine,
        _logger = logger ?? ConsoleStructuredLogger(),
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _reconnectPolicy = reconnectPolicy,
        _networkThresholds = networkThresholds,
        _tokenRefresher = tokenRefresher,
        _state = CallState.idle() {
    _mediaEventsSubscription = _mediaEngine.events.listen(_handleMediaEvent);
  }

  final MediaEngine _mediaEngine;
  final StructuredLogger _logger;
  final DateTime Function() _clock;
  final CallReconnectPolicy _reconnectPolicy;
  final CallNetworkThresholds _networkThresholds;
  final CallTokenRefresher? _tokenRefresher;
  final StreamController<CallState> _controller =
      StreamController<CallState>.broadcast();
  final StreamController<CallEngineEvent> _eventsController =
      StreamController<CallEngineEvent>.broadcast();
  late final StreamSubscription<MediaEngineEvent> _mediaEventsSubscription;

  CallState _state;
  bool _isDisposed = false;
  bool _isDisconnectingInternally = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  Timer? _graceTimer;
  Timer? _stableNetworkTimer;
  DateTime? _lastRecoveryCycleAt;
  bool _videoWasEnabledBeforeFallback = false;
  String? _activeRoomUrl;
  String? _activeToken;
  Future<void> _operationQueue = Future<void>.value();
  Future<String>? _tokenRefreshInFlight;
  bool _isReconnectAttemptInFlight = false;
  bool _isInterrupted = false;
  DateTime? _lastActionAt;
  String? _lastActionKey;
  CallAppLifecycleState _lastLifecycleState = CallAppLifecycleState.resumed;
  CallAudioRoute _audioRoute = CallAudioRoute.earpiece;

  Stream<CallState> get states => _controller.stream;
  Stream<CallEngineEvent> get events => _eventsController.stream;
  CallState get state => _state;

  Future<void> connectSession({
    required String callId,
    required String peerId,
    required String roomUrl,
    required String token,
    CallDirection direction = CallDirection.outgoing,
    CallType callType = CallType.voice,
  }) async {
    await _runSerialized('connect_session', () async {
      _guardStartAllowed('connect_session');
      _validateConnectParams(roomUrl: roomUrl, token: token);

      final session = CallSession(
        callId: callId,
        peerId: peerId,
        direction: direction,
        callType: callType,
        createdAt: _clock(),
      );

      _transition(
        to: CallPhase.connecting,
        session: session,
        event: 'call.connect_session',
        fields: const <String, Object?>{},
        clearReason: true,
      );

      try {
        _setActiveConnection(roomUrl: roomUrl, token: token);
        _resetRecoveryCycle();
        await _mediaEngine.connect(roomUrl: roomUrl, token: token);
        _log('media.connected', <String, Object?>{'callId': callId});
      } on P2PLimitExceededException catch (_) {
        _transition(
          to: CallPhase.failed,
          reason: 'p2p_limit_exceeded',
          event: 'call.p2p_limit_exceeded',
          fields: <String, Object?>{'callId': callId},
        );
        rethrow;
      } catch (error) {
        _transition(
          to: CallPhase.failed,
          reason: 'connect_failed',
          event: 'call.connect_failed',
          fields: <String, Object?>{
            'callId': callId,
            'error': _sanitizeError(error),
          },
        );
        rethrow;
      }

      _transition(
        to: CallPhase.connected,
        event: 'call.connected',
        fields: const <String, Object?>{},
      );
    });
  }

  @Deprecated('Use connectSession instead. Signaling/invitation ownership is external.')
  Future<void> startOutgoing({
    required String callId,
    required String peerId,
    required String roomUrl,
    required String token,
    CallType callType = CallType.voice,
  }) {
    return connectSession(
      callId: callId,
      peerId: peerId,
      roomUrl: roomUrl,
      token: token,
      direction: CallDirection.outgoing,
      callType: callType,
    );
  }

  @Deprecated('Incoming invitation lifecycle is owned by external signaling.')
  void onIncoming({
    required String callId,
    required String peerId,
    CallType callType = CallType.voice,
  }) {
    throw CallLifecycleException(
      'onIncoming is removed from CallEngine. Handle signaling externally and call connectSession when ready to join media.',
    );
  }

  @Deprecated('Incoming invitation lifecycle is owned by external signaling.')
  Future<void> acceptIncoming({
    required String roomUrl,
    required String token,
  }) {
    throw CallLifecycleException(
      'acceptIncoming is removed from CallEngine. Use connectSession instead.',
    );
  }

  @Deprecated('Incoming invitation lifecycle is owned by external signaling.')
  Future<void> rejectIncoming({String reason = 'rejected'}) {
    throw CallLifecycleException(
      'rejectIncoming is removed from CallEngine. Handle invitation rejection in signaling layer.',
    );
  }

  @Deprecated('Media connect transitions to connected automatically.')
  void markOutgoingConnected() {
    throw CallLifecycleException(
      'markOutgoingConnected is removed. CallEngine transitions to connected after media connect.',
    );
  }

  Future<void> endCall({String reason = 'ended_by_user'}) async {
    await _runSerialized('end_call', () async {
      if (_state.phase == CallPhase.idle) {
        return;
      }

      if (_state.phase == CallPhase.disconnected || _state.phase == CallPhase.failed) {
        _resetToIdle('end_cleanup');
        return;
      }

      _guardPhase(
        expected: const <CallPhase>{
          CallPhase.connecting,
          CallPhase.connected,
          CallPhase.reconnecting,
        },
        action: 'end_call',
      );

      _transition(
        to: CallPhase.disconnected,
        reason: reason,
        event: 'call.disconnected',
        fields: <String, Object?>{'reason': reason},
      );

      try {
        await _disconnectMedia();
        _log(
          'media.disconnected',
          <String, Object?>{'callId': _state.session?.callId},
        );
      } catch (error) {
        _log(
          'media.disconnect_failed',
          <String, Object?>{
            'callId': _state.session?.callId,
            'error': _sanitizeError(error),
          },
        );
      } finally {
        _resetToIdle('end_cleanup');
      }
    });
  }

  Future<void> setMuted(bool muted) async {
    await _runSerialized('set_muted', () async {
      _guardPhase(
        expected: const <CallPhase>{CallPhase.connected, CallPhase.reconnecting},
        action: 'set_muted',
      );
      if (_state.isMuted == muted) {
        return;
      }

      await _mediaEngine.setMuted(muted);
      _state = _state.copyWith(
        isMuted: muted,
        updatedAt: _clock(),
      );
      _controller.add(_state);
      _emitEngineEvent(
        CallEngineEvent(
          type: CallEngineEventType.localAudioChanged,
          callId: _state.session?.callId,
          reason: muted ? 'local_audio_disabled' : 'local_audio_enabled',
          timestamp: _clock(),
        ),
      );
      _log(
        'call.mute_updated',
        <String, Object?>{
          'callId': _state.session?.callId,
          'isMuted': muted,
        },
      );
    });
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    await _runSerialized('set_speaker_on', () async {
      _guardPhase(
        expected: const <CallPhase>{CallPhase.connected, CallPhase.reconnecting},
        action: 'set_speaker_on',
      );
      if (_state.isSpeakerOn == speakerOn) {
        return;
      }

      await _mediaEngine.setSpeakerOn(speakerOn);
      _state = _state.copyWith(
        isSpeakerOn: speakerOn,
        updatedAt: _clock(),
      );
      _controller.add(_state);
      _audioRoute = speakerOn ? CallAudioRoute.speaker : CallAudioRoute.earpiece;
      _emitEngineEvent(
        CallEngineEvent(
          type: CallEngineEventType.audioRouteChanged,
          callId: _state.session?.callId,
          reason: _audioRoute.name,
          audioRoute: _audioRoute,
          timestamp: _clock(),
        ),
      );
      _log(
        'call.speaker_updated',
        <String, Object?>{
          'callId': _state.session?.callId,
          'isSpeakerOn': speakerOn,
        },
      );
    });
  }

  Future<void> setVideoEnabled(bool enabled) async {
    await _runSerialized('set_video_enabled', () async {
      _guardPhase(
        expected: const <CallPhase>{CallPhase.connecting, CallPhase.connected, CallPhase.reconnecting},
        action: 'set_video_enabled',
      );
      if (_state.isVideoEnabled == enabled) {
        return;
      }

      await _mediaEngine.setCameraOn(enabled);
      _state = _state.copyWith(
        isVideoEnabled: enabled,
        updatedAt: _clock(),
      );
      _controller.add(_state);
      _emitEngineEvent(
        CallEngineEvent(
          type: CallEngineEventType.localVideoChanged,
          callId: _state.session?.callId,
          reason: enabled ? 'local_video_enabled' : 'local_video_disabled',
          timestamp: _clock(),
        ),
      );
      _log(
        'call.video_updated',
        <String, Object?>{
          'callId': _state.session?.callId,
          'isVideoEnabled': enabled,
        },
      );
    });
  }

  Future<void> onAppLifecycleChanged(CallAppLifecycleState lifecycleState) async {
    await _runSerialized('app_lifecycle_changed', () async {
      final isDuplicateState = lifecycleState == _lastLifecycleState;
      if (isDuplicateState &&
          _isActionDebounced(
            'lifecycle.${lifecycleState.name}',
            window: const Duration(milliseconds: 700),
          )) {
        return;
      }
      _lastLifecycleState = lifecycleState;
      _emitEngineEvent(
        CallEngineEvent(
          type: CallEngineEventType.lifecycleChanged,
          callId: _state.session?.callId,
          lifecycleState: lifecycleState,
          reason: lifecycleState.name,
          timestamp: _clock(),
        ),
      );

      if (_state.session == null ||
          (_state.phase != CallPhase.connected &&
              _state.phase != CallPhase.connecting &&
              _state.phase != CallPhase.reconnecting)) {
        return;
      }

      final isBackgroundLike = lifecycleState == CallAppLifecycleState.inactive ||
          lifecycleState == CallAppLifecycleState.paused ||
          lifecycleState == CallAppLifecycleState.hidden;

      if (isBackgroundLike) {
        if (_isInterrupted) {
          return;
        }
        _isInterrupted = true;
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.interruptionStarted,
            callId: _state.session?.callId,
            reason: lifecycleState.name,
            lifecycleState: lifecycleState,
            timestamp: _clock(),
          ),
        );
        return;
      }

      if (lifecycleState == CallAppLifecycleState.resumed && _isInterrupted) {
        _isInterrupted = false;
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.interruptionRecovered,
            callId: _state.session?.callId,
            reason: 'app_resumed',
            lifecycleState: lifecycleState,
            timestamp: _clock(),
          ),
        );
        await _restoreMediaSession();
      }
    });
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }

    _isDisposed = true;

    try {
      if (_state.phase != CallPhase.idle) {
        await _disconnectMedia();
        _resetToIdle('dispose_cleanup');
      }
    } catch (_) {
      _resetToIdle('dispose_cleanup');
    } finally {
      _cancelRecoveryTimers();
      await _mediaEventsSubscription.cancel();
      await _mediaEngine.dispose();
      await _eventsController.close();
      await _controller.close();
    }
  }

  Future<T> _runSerialized<T>(
    String action,
    Future<T> Function() operation,
  ) {
    final next = _operationQueue
        .catchError((Object _) {
          // Keep the serialization chain alive after failures.
        })
        .then((_) async {
          _ensureActive(action);
          return operation();
        });

    _operationQueue = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  bool _isActionDebounced(String actionKey, {Duration window = const Duration(milliseconds: 350)}) {
    final now = _clock();
    final lastKey = _lastActionKey;
    final lastAt = _lastActionAt;
    if (lastKey == actionKey && lastAt != null && now.difference(lastAt) < window) {
      return true;
    }
    _lastActionKey = actionKey;
    _lastActionAt = now;
    return false;
  }

  void _ensureActive(String action) {
    if (_isDisposed) {
      throw CallLifecycleException('CallEngine is disposed. Cannot $action.');
    }
  }

  void _guardStartAllowed(String action) {
    _guardPhase(
      expected: const <CallPhase>{
        CallPhase.idle,
        CallPhase.disconnected,
        CallPhase.failed,
      },
      action: action,
    );
  }

  void _guardPhase({
    required Set<CallPhase> expected,
    required String action,
  }) {
    if (expected.contains(_state.phase)) {
      return;
    }

    _log(
      'call.lifecycle_violation',
      <String, Object?>{
        'action': action,
        'currentPhase': _state.phase.name,
        'expected': expected.map((phase) => phase.name).toList(),
      },
    );

    throw CallLifecycleException(
      'Invalid transition for $action from ${_state.phase.name}.',
    );
  }

  void _validateConnectParams({
    required String roomUrl,
    required String token,
  }) {
    final uri = Uri.tryParse(roomUrl);
    if (uri == null || !(uri.isScheme('ws') || uri.isScheme('wss'))) {
      throw CallLifecycleException('Invalid roomUrl: must be a ws:// or wss:// URI.');
    }

    final parts = token.trim().split('.');
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) {
      throw CallLifecycleException('Invalid token: malformed JWT structure.');
    }

    // Attempt to decode payload and check expiry.
    try {
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final dynamic json = jsonDecode(decoded);
      if (json is Map) {
        final exp = json['exp'];
        if (exp is num) {
          final expiry = DateTime.fromMillisecondsSinceEpoch(
            exp.toInt() * 1000,
            isUtc: true,
          );
          if (expiry.isBefore(_clock())) {
            throw CallLifecycleException('Invalid token: JWT has expired.');
          }
        }
      }
    } on CallLifecycleException {
      rethrow;
    } catch (_) {
      // Non-decodable payload: structural shape was already verified above.
    }
  }

  Future<void> _disconnectMedia() async {
    _isDisconnectingInternally = true;
    try {
      await _mediaEngine.disconnect();
    } finally {
      _isDisconnectingInternally = false;
    }
  }

  void _handleMediaEvent(MediaEngineEvent event) {
    if (_isDisposed || _isDisconnectingInternally) {
      return;
    }

    unawaited(
      _runSerialized(
        'media_event.${event.type.name}',
        () => _processMediaEvent(event),
      ),
    );
  }

  Future<void> _processMediaEvent(MediaEngineEvent event) async {
    if (_isDisposed || _isDisconnectingInternally) {
      return;
    }

    switch (event.type) {
      case MediaEngineEventType.p2pLimitExceeded:
        _handleUnexpectedTermination(
          reason: event.reason ?? 'p2p_limit_exceeded',
          event: 'call.p2p_limit_exceeded',
          cleanupEvent: 'p2p_limit_cleanup',
        );
        return;
      case MediaEngineEventType.disconnected:
        _handleMediaDisconnected(event.reason ?? 'media_disconnected');
        return;
      case MediaEngineEventType.participantJoined:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.participantJoined,
            callId: _state.session?.callId,
            reason: event.participantId,
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.participantLeft:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.participantLeft,
            callId: _state.session?.callId,
            reason: event.participantId,
            timestamp: _clock(),
          ),
        );
        _handleMediaDisconnected('remote_participant_left');
        return;
      case MediaEngineEventType.localAudioChanged:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.localAudioChanged,
            callId: _state.session?.callId,
            reason: event.enabled == true
                ? 'local_audio_enabled'
                : 'local_audio_disabled',
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.remoteAudioChanged:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.remoteAudioChanged,
            callId: _state.session?.callId,
            reason: event.enabled == true
                ? 'remote_audio_enabled'
                : 'remote_audio_disabled',
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.localVideoChanged:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.localVideoChanged,
            callId: _state.session?.callId,
            reason: event.enabled == true
                ? 'local_video_enabled'
                : 'local_video_disabled',
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.remoteVideoChanged:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.remoteVideoChanged,
            callId: _state.session?.callId,
            reason: event.enabled == true
                ? 'remote_video_enabled'
                : 'remote_video_disabled',
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.reconnecting:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.reconnecting,
            callId: _state.session?.callId,
            reason: event.reason,
            reconnectAttempt: _reconnectAttempt,
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.reconnected:
        _completeRecovery(reason: event.reason ?? 'media_reconnected');
        return;
      case MediaEngineEventType.iceRestarting:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.iceRecoveryStarted,
            callId: _state.session?.callId,
            reason: event.reason,
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.iceRecovered:
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.iceRecovered,
            callId: _state.session?.callId,
            reason: event.reason,
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.networkQualityChanged:
        final quality = event.networkQuality;
        if (quality != null) {
          _handleNetworkQuality(quality);
        }
        return;
      case MediaEngineEventType.interruptionStarted:
        _isInterrupted = true;
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.interruptionStarted,
            callId: _state.session?.callId,
            reason: event.reason ?? 'media_interruption_started',
            timestamp: _clock(),
          ),
        );
        return;
      case MediaEngineEventType.interruptionEnded:
        _isInterrupted = false;
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.interruptionRecovered,
            callId: _state.session?.callId,
            reason: event.reason ?? 'media_interruption_ended',
            timestamp: _clock(),
          ),
        );
        await _restoreMediaSession();
        return;
      case MediaEngineEventType.audioRouteChanged:
        final route = _mapMediaAudioRoute(event.audioRoute);
        _audioRoute = route;
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.audioRouteChanged,
            callId: _state.session?.callId,
            reason: event.reason ?? route.name,
            audioRoute: route,
            timestamp: _clock(),
          ),
        );
        return;
    }
  }

  void _handleMediaDisconnected(String reason) {
    if (_state.phase == CallPhase.idle) {
      return;
    }

    if (reason == 'remote_participant_left') {
      _handleUnexpectedTermination(
        reason: reason,
        event: 'call.remote_participant_left',
        cleanupEvent: 'remote_participant_left_cleanup',
      );
      return;
    }

    if (_isActionDebounced('media_disconnected.$reason', window: const Duration(milliseconds: 250))) {
      return;
    }

    if (!_shouldRecover()) {
      _handleUnexpectedTermination(
        reason: reason,
        event: 'call.media_disconnected',
        cleanupEvent: 'media_disconnect_cleanup',
      );
      return;
    }

    _startRecovery(reason);
  }

  bool _shouldRecover() {
    if (!_reconnectPolicy.enabled) {
      return false;
    }

    if (_state.session == null || _activeRoomUrl == null || _activeToken == null) {
      return false;
    }

    if (_state.phase != CallPhase.connected) {
      return false;
    }

    final lastCycleAt = _lastRecoveryCycleAt;
    if (lastCycleAt != null && _clock().difference(lastCycleAt) < _reconnectPolicy.reconnectCooldown) {
      return false;
    }

    return true;
  }

  void _startRecovery(String reason) {
    _reconnectAttempt = 0;
    _lastRecoveryCycleAt = _clock();

    _transition(
      to: CallPhase.reconnecting,
      reason: reason,
      event: 'call.reconnecting',
      fields: <String, Object?>{'reason': reason},
    );

    _state = _state.copyWith(reconnectAttempts: _reconnectAttempt, updatedAt: _clock());
    _controller.add(_state);

    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.reconnecting,
        callId: _state.session?.callId,
        reason: reason,
        reconnectAttempt: _reconnectAttempt,
        timestamp: _clock(),
      ),
    );

    _startGraceTimer();
    _scheduleReconnectAttempt(Duration.zero);
  }

  void _startGraceTimer() {
    _graceTimer?.cancel();
    _graceTimer = Timer(_reconnectPolicy.graceTimeout, () {
      if (_isDisposed || !_state.isReconnecting) {
        return;
      }

      _emitEngineEvent(
        CallEngineEvent(
          type: CallEngineEventType.reconnectFailed,
          callId: _state.session?.callId,
          reason: 'recovery_grace_timeout',
          reconnectAttempt: _reconnectAttempt,
          timestamp: _clock(),
        ),
      );

      _transition(
        to: CallPhase.failed,
        reason: 'recovery_grace_timeout',
        event: 'call.recovery_grace_timeout',
        fields: const <String, Object?>{},
      );
      _cancelRecoveryTimers();
    });
  }

  void _scheduleReconnectAttempt(Duration delay) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      unawaited(_runSerialized('reconnect_attempt', _attemptReconnect));
    });
  }

  Future<void> _attemptReconnect() async {
    if (_isDisposed || !_state.isReconnecting) {
      return;
    }
    if (_isReconnectAttemptInFlight) {
      return;
    }
    _isReconnectAttemptInFlight = true;
    try {
      if (_reconnectAttempt >= _reconnectPolicy.maxAttempts) {
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.reconnectFailed,
            callId: _state.session?.callId,
            reason: 'max_reconnect_attempts',
            reconnectAttempt: _reconnectAttempt,
            timestamp: _clock(),
          ),
        );
        _transition(
          to: CallPhase.failed,
          reason: 'max_reconnect_attempts',
          event: 'call.reconnect_failed',
          fields: const <String, Object?>{},
        );
        _cancelRecoveryTimers();
        return;
      }

      _reconnectAttempt += 1;
      _state = _state.copyWith(
        reconnectAttempts: _reconnectAttempt,
        updatedAt: _clock(),
      );
      _controller.add(_state);

      final session = _state.session;
      final roomUrl = _activeRoomUrl;
      if (session == null || roomUrl == null || _activeToken == null) {
        return;
      }

      _emitEngineEvent(
        CallEngineEvent(
          type: CallEngineEventType.reconnecting,
          callId: session.callId,
          reconnectAttempt: _reconnectAttempt,
          reason: 'reconnect_attempt',
          timestamp: _clock(),
        ),
      );

      try {
        if (_reconnectPolicy.enableIceRecovery) {
          _emitEngineEvent(
            CallEngineEvent(
              type: CallEngineEventType.iceRecoveryStarted,
              callId: session.callId,
              reconnectAttempt: _reconnectAttempt,
              timestamp: _clock(),
            ),
          );
          await _mediaEngine.restartIce();
        }

        final token = await _resolveTokenForReconnect(session);
        await _mediaEngine.connect(roomUrl: roomUrl, token: token);
        await _restoreMediaSession();
        _completeRecovery(reason: 'reconnect_success');
      } on P2PLimitExceededException catch (_) {
        _handleUnexpectedTermination(
          reason: 'p2p_limit_exceeded',
          event: 'call.p2p_limit_exceeded',
          cleanupEvent: 'p2p_limit_cleanup',
        );
      } catch (error) {
        _log(
          'call.reconnect_attempt_failed',
          <String, Object?>{
            'callId': session.callId,
            'attempt': _reconnectAttempt,
            'error': _sanitizeError(error),
          },
        );

        final backoff = _computeBackoff(_reconnectAttempt);
        _scheduleReconnectAttempt(backoff);
      }
    } finally {
      _isReconnectAttemptInFlight = false;
    }
  }

  Duration _computeBackoff(int attempt) {
    if (attempt <= 1) {
      return _reconnectPolicy.initialDelay;
    }

    final ms = _reconnectPolicy.initialDelay.inMilliseconds * (1 << (attempt - 1));
    final bounded = ms > _reconnectPolicy.maxDelay.inMilliseconds
        ? _reconnectPolicy.maxDelay.inMilliseconds
        : ms;
    return Duration(milliseconds: bounded);
  }

  Future<String> _resolveTokenForReconnect(CallSession session) async {
    final currentToken = _activeToken!;
    final shouldRefresh = _tokenShouldRefresh(currentToken);
    if (!shouldRefresh || _tokenRefresher == null) {
      return currentToken;
    }

    final inFlight = _tokenRefreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.tokenRefreshRequested,
        callId: session.callId,
        reconnectAttempt: _reconnectAttempt,
        timestamp: _clock(),
      ),
    );

    final refreshFuture = (() async {
      try {
        final refreshed = await _tokenRefresher(session, _reconnectAttempt);
        _validateConnectParams(roomUrl: _activeRoomUrl!, token: refreshed);
        await _mediaEngine.updateToken(refreshed);
        _activeToken = refreshed;

        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.tokenRefreshed,
            callId: session.callId,
            reconnectAttempt: _reconnectAttempt,
            timestamp: _clock(),
          ),
        );

        return refreshed;
      } catch (error) {
        _emitEngineEvent(
          CallEngineEvent(
            type: CallEngineEventType.tokenRefreshFailed,
            callId: session.callId,
            reconnectAttempt: _reconnectAttempt,
            error: _sanitizeError(error),
            timestamp: _clock(),
          ),
        );
        rethrow;
      } finally {
        _tokenRefreshInFlight = null;
      }
    })();

    _tokenRefreshInFlight = refreshFuture;
    return refreshFuture;
  }

  bool _tokenShouldRefresh(String token) {
    final expiry = _tryParseTokenExpiry(token);
    if (expiry == null) {
      return false;
    }

    return expiry.difference(_clock()) <= _reconnectPolicy.tokenRefreshBeforeExpiry;
  }

  DateTime? _tryParseTokenExpiry(String token) {
    try {
      final parts = token.trim().split('.');
      if (parts.length != 3 || parts.any((p) => p.isEmpty)) {
        return null;
      }
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final dynamic json = jsonDecode(decoded);
      if (json is Map) {
        final exp = json['exp'];
        if (exp is num) {
          return DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000, isUtc: true);
        }
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _completeRecovery({required String reason}) {
    if (!_state.isReconnecting) {
      return;
    }

    _graceTimer?.cancel();
    _reconnectTimer?.cancel();

    _transition(
      to: CallPhase.connected,
      reason: null,
      clearReason: true,
      event: 'call.recovered_connected',
      fields: const <String, Object?>{},
    );

    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.recovered,
        callId: _state.session?.callId,
        reason: reason,
        reconnectAttempt: _reconnectAttempt,
        timestamp: _clock(),
      ),
    );

    _log(
      'call.recovered',
      <String, Object?>{
        'callId': _state.session?.callId,
        'attempts': _reconnectAttempt,
      },
    );
  }

  void _handleNetworkQuality(MediaNetworkQuality quality) {
    _state = _state.copyWith(
      networkScore: quality.score,
      updatedAt: _clock(),
    );
    _controller.add(_state);

    if (_state.phase != CallPhase.connected && _state.phase != CallPhase.reconnecting) {
      return;
    }

    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.networkQualityChanged,
        callId: _state.session?.callId,
        networkScore: quality.score,
        timestamp: _clock(),
      ),
    );

    if (quality.score <= _networkThresholds.weakScore) {
      _stableNetworkTimer?.cancel();
      if (!_state.isAudioPriority) {
        unawaited(_enableAudioPriorityFallback(quality.score));
      }
      return;
    }

    if (quality.score >= _networkThresholds.stableScore && _state.isAudioPriority) {
      _stableNetworkTimer?.cancel();
      _stableNetworkTimer = Timer(_networkThresholds.stableDuration, () {
        unawaited(_recoverFromAudioPriority());
      });
    }
  }

  Future<void> _enableAudioPriorityFallback(int score) async {
    _videoWasEnabledBeforeFallback = _state.isVideoEnabled;

    await _mediaEngine.setConnectionProfile(
      MediaConnectionProfile(
        preferAudio: true,
        maxBitrateKbps: _networkThresholds.audioPriorityBitrateKbps,
        maxVideoHeight: _networkThresholds.audioPriorityMaxVideoHeight,
        maxVideoFps: _networkThresholds.audioPriorityMaxVideoFps,
      ),
    );

    if (_state.isVideoEnabled) {
      await _mediaEngine.setCameraOn(false);
    }

    _state = _state.copyWith(
      isVideoEnabled: false,
      isAudioPriority: true,
      updatedAt: _clock(),
    );
    _controller.add(_state);

    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.networkDegraded,
        callId: _state.session?.callId,
        networkScore: score,
        timestamp: _clock(),
      ),
    );
    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.audioPriorityEnabled,
        callId: _state.session?.callId,
        networkScore: score,
        timestamp: _clock(),
      ),
    );
  }

  Future<void> _recoverFromAudioPriority() async {
    if (_state.phase != CallPhase.connected || !_state.isAudioPriority) {
      return;
    }

    await _mediaEngine.setConnectionProfile(MediaConnectionProfile.balanced);

    if (_videoWasEnabledBeforeFallback) {
      await _mediaEngine.setCameraOn(true);
    }

    _state = _state.copyWith(
      isVideoEnabled: _videoWasEnabledBeforeFallback,
      isAudioPriority: false,
      updatedAt: _clock(),
    );
    _controller.add(_state);

    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.networkRecovered,
        callId: _state.session?.callId,
        networkScore: _state.networkScore,
        timestamp: _clock(),
      ),
    );
    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.audioPriorityDisabled,
        callId: _state.session?.callId,
        networkScore: _state.networkScore,
        timestamp: _clock(),
      ),
    );
  }

  Future<void> _restoreMediaSession() async {
    if ((_state.phase != CallPhase.connected &&
            _state.phase != CallPhase.reconnecting) ||
        _state.session == null) {
      return;
    }

    if (!_mediaEngine.isConnected) {
      final roomUrl = _activeRoomUrl;
      final token = _activeToken;
      if (roomUrl == null || token == null) {
        return;
      }

      final refreshedToken = await _resolveTokenForReconnect(_state.session!);
      await _mediaEngine.connect(roomUrl: roomUrl, token: refreshedToken);
    }

    await _mediaEngine.setMuted(_state.isMuted);
    await _mediaEngine.setSpeakerOn(_state.isSpeakerOn);
    await _mediaEngine.setCameraOn(_state.isVideoEnabled);

    _audioRoute = _state.isSpeakerOn ? CallAudioRoute.speaker : CallAudioRoute.earpiece;
    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.mediaSessionRestored,
        callId: _state.session?.callId,
        reason: 'media_session_restored',
        timestamp: _clock(),
      ),
    );
    _emitEngineEvent(
      CallEngineEvent(
        type: CallEngineEventType.audioRouteChanged,
        callId: _state.session?.callId,
        reason: _audioRoute.name,
        audioRoute: _audioRoute,
        timestamp: _clock(),
      ),
    );
  }

  CallAudioRoute _mapMediaAudioRoute(MediaAudioRoute? route) {
    return switch (route) {
      MediaAudioRoute.earpiece => CallAudioRoute.earpiece,
      MediaAudioRoute.speaker => CallAudioRoute.speaker,
      MediaAudioRoute.bluetooth => CallAudioRoute.bluetooth,
      MediaAudioRoute.wiredHeadset => CallAudioRoute.wiredHeadset,
      MediaAudioRoute.unknown => CallAudioRoute.unknown,
      null => CallAudioRoute.unknown,
    };
  }

  void _handleUnexpectedTermination({
    required String reason,
    required String event,
    required String cleanupEvent,
  }) {
    if (_state.phase == CallPhase.idle) {
      return;
    }

    _transition(
      to: CallPhase.disconnected,
      reason: reason,
      event: event,
      fields: <String, Object?>{'reason': reason},
    );
    _log(cleanupEvent, const <String, Object?>{});
  }

  void _transition({
    required CallPhase to,
    required String event,
    required Map<String, Object?> fields,
    CallSession? session,
    String? reason,
    bool clearReason = false,
  }) {
    final from = _state.phase;
    if (!_isTransitionAllowed(from: from, to: to)) {
      _log(
        'call.transition_blocked',
        <String, Object?>{
          'from': from.name,
          'to': to.name,
          'event': event,
          'callId': _state.session?.callId,
        },
      );
      throw CallLifecycleException('Invalid transition from ${from.name} to ${to.name}.');
    }

    _state = _state.copyWith(
      phase: to,
      session: session,
      reason: reason,
      isMuted: (to == CallPhase.connected || to == CallPhase.reconnecting) ? _state.isMuted : false,
      isSpeakerOn:
        (to == CallPhase.connected || to == CallPhase.reconnecting) ? _state.isSpeakerOn : false,
      isVideoEnabled: (to == CallPhase.connected ||
          to == CallPhase.connecting ||
          to == CallPhase.reconnecting)
        ? _state.isVideoEnabled
        : false,
      isReconnecting: to == CallPhase.reconnecting ? true : false,
      reconnectAttempts: to == CallPhase.reconnecting ? _state.reconnectAttempts : 0,
      networkScore:
        (to == CallPhase.connected || to == CallPhase.reconnecting) ? _state.networkScore : null,
      clearNetworkScore: !(to == CallPhase.connected || to == CallPhase.reconnecting),
      isAudioPriority: to == CallPhase.connected || to == CallPhase.reconnecting
        ? _state.isAudioPriority
        : false,
      clearReason: clearReason,
      updatedAt: _clock(),
    );

    _controller.add(_state);

    _log(
      event,
      <String, Object?>{
        'from': from.name,
        'to': to.name,
        'callId': _state.session?.callId,
        'peerId': _state.session?.peerId,
        ...fields,
      },
    );
  }

  bool _isTransitionAllowed({
    required CallPhase from,
    required CallPhase to,
  }) {
    if (from == to) {
      return true;
    }

    final allowed = <CallPhase, Set<CallPhase>>{
      CallPhase.idle: const <CallPhase>{CallPhase.connecting},
      CallPhase.connecting: const <CallPhase>{
        CallPhase.connected,
        CallPhase.disconnected,
        CallPhase.failed,
      },
      CallPhase.connected: const <CallPhase>{
        CallPhase.reconnecting,
        CallPhase.disconnected,
        CallPhase.failed,
      },
      CallPhase.reconnecting: const <CallPhase>{
        CallPhase.connected,
        CallPhase.disconnected,
        CallPhase.failed,
      },
      CallPhase.disconnected: const <CallPhase>{CallPhase.idle, CallPhase.connecting},
      CallPhase.failed: const <CallPhase>{CallPhase.idle, CallPhase.connecting},
    };

    return allowed[from]?.contains(to) ?? false;
  }

  void _resetToIdle(String event) {
    _cancelRecoveryTimers();
    _activeRoomUrl = null;
    _activeToken = null;
    _tokenRefreshInFlight = null;
    _reconnectAttempt = 0;
    _isReconnectAttemptInFlight = false;
    _isInterrupted = false;
    _videoWasEnabledBeforeFallback = false;
    _audioRoute = CallAudioRoute.earpiece;

    _state = CallState(
      phase: CallPhase.idle,
      isMuted: false,
      isSpeakerOn: false,
      isVideoEnabled: false,
      isReconnecting: false,
      reconnectAttempts: 0,
      networkScore: null,
      isAudioPriority: false,
      updatedAt: _clock(),
    );

    _controller.add(_state);
    _log(event, const <String, Object?>{});
  }

  void _setActiveConnection({
    required String roomUrl,
    required String token,
  }) {
    _activeRoomUrl = roomUrl;
    _activeToken = token;
  }

  void _resetRecoveryCycle() {
    _cancelRecoveryTimers();
    _reconnectAttempt = 0;
    _isReconnectAttemptInFlight = false;
    _videoWasEnabledBeforeFallback = false;
    _state = _state.copyWith(
      isReconnecting: false,
      reconnectAttempts: 0,
      isAudioPriority: false,
      updatedAt: _clock(),
    );
    _controller.add(_state);
  }

  void _cancelRecoveryTimers() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _graceTimer?.cancel();
    _graceTimer = null;
    _stableNetworkTimer?.cancel();
    _stableNetworkTimer = null;
  }

  void _emitEngineEvent(CallEngineEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }

  void _log(String event, Map<String, Object?> fields) {
    _logger.log(
      event: event,
      fields: <String, Object?>{
        'timestamp': _clock().toIso8601String(),
        ...fields,
      },
    );
  }

  String _sanitizeError(Object error) {
    final text = error.toString();
    final jwtRegex = RegExp(r'[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+');
    return text.replaceAll(jwtRegex, '[redacted_jwt]');
  }
}