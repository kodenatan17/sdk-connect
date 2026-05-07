import 'dart:async';

import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/core/models/call_session.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';

class CallEngine {
  CallEngine({
    required MediaEngine mediaEngine,
    StructuredLogger? logger,
    DateTime Function()? clock,
  })  : _mediaEngine = mediaEngine,
        _logger = logger ?? ConsoleStructuredLogger(),
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _state = CallState.idle();

  final MediaEngine _mediaEngine;
  final StructuredLogger _logger;
  final DateTime Function() _clock;
  final StreamController<CallState> _controller =
      StreamController<CallState>.broadcast();

  CallState _state;

  Stream<CallState> get states => _controller.stream;
  CallState get state => _state;

  Future<void> startOutgoing({
    required String callId,
    required String peerId,
    required String roomUrl,
    required String token,
  }) async {
    _guardStartAllowed('start_outgoing');
    _validateConnectParams(roomUrl: roomUrl, token: token);

    final session = CallSession(
      callId: callId,
      peerId: peerId,
      direction: CallDirection.outgoing,
      createdAt: _clock(),
    );

    _transition(
      to: CallPhase.dialing,
      session: session,
      event: 'call.start_outgoing',
      fields: const <String, Object?>{},
    );

    try {
      await _mediaEngine.connect(roomUrl: roomUrl, token: token);
      _log('media.connected', <String, Object?>{'callId': callId});
    } catch (error) {
      _transition(
        to: CallPhase.ended,
        reason: 'connect_failed',
        event: 'call.connect_failed',
        fields: <String, Object?>{
          'callId': callId,
          'error': error.toString(),
        },
      );
      _resetToIdle('connect_failure_cleanup');
      rethrow;
    }
  }

  void onIncoming({
    required String callId,
    required String peerId,
  }) {
    _guardStartAllowed('incoming');

    final session = CallSession(
      callId: callId,
      peerId: peerId,
      direction: CallDirection.incoming,
      createdAt: _clock(),
    );

    _transition(
      to: CallPhase.ringing,
      session: session,
      event: 'call.incoming',
      fields: const <String, Object?>{},
    );
  }

  Future<void> acceptIncoming({
    required String roomUrl,
    required String token,
  }) async {
    _guardPhase(
      expected: const <CallPhase>{CallPhase.ringing},
      action: 'accept_incoming',
    );
    _validateConnectParams(roomUrl: roomUrl, token: token);

    try {
      await _mediaEngine.connect(roomUrl: roomUrl, token: token);
      _log('media.connected', <String, Object?>{'callId': _state.session?.callId});
    } catch (error) {
      _transition(
        to: CallPhase.ended,
        reason: 'connect_failed',
        event: 'call.connect_failed',
        fields: <String, Object?>{'error': error.toString()},
      );
      _resetToIdle('connect_failure_cleanup');
      rethrow;
    }

    _transition(
      to: CallPhase.connected,
      event: 'call.accepted',
      fields: const <String, Object?>{},
    );
  }

  Future<void> rejectIncoming({String reason = 'rejected'}) async {
    _guardPhase(
      expected: const <CallPhase>{CallPhase.ringing},
      action: 'reject_incoming',
    );

    _transition(
      to: CallPhase.ended,
      reason: reason,
      event: 'call.rejected',
      fields: <String, Object?>{'reason': reason},
    );

    try {
      await _mediaEngine.disconnect();
      _log(
        'media.disconnected',
        <String, Object?>{'callId': _state.session?.callId},
      );
    } catch (error) {
      _log(
        'media.disconnect_failed',
        <String, Object?>{
          'callId': _state.session?.callId,
          'error': error.toString(),
        },
      );
    } finally {
      _resetToIdle('rejected_cleanup');
    }
  }

  void markOutgoingConnected() {
    _guardPhase(
      expected: const <CallPhase>{CallPhase.dialing},
      action: 'mark_outgoing_connected',
    );

    _transition(
      to: CallPhase.connected,
      event: 'call.connected',
      fields: const <String, Object?>{},
    );
  }

  Future<void> endCall({String reason = 'ended_by_user'}) async {
    _guardPhase(
      expected: const <CallPhase>{
        CallPhase.dialing,
        CallPhase.ringing,
        CallPhase.connected,
      },
      action: 'end_call',
    );

    _transition(
      to: CallPhase.ended,
      reason: reason,
      event: 'call.ended',
      fields: <String, Object?>{'reason': reason},
    );

    try {
      await _mediaEngine.disconnect();
      _log(
        'media.disconnected',
        <String, Object?>{'callId': _state.session?.callId},
      );
    } catch (error) {
      _log(
        'media.disconnect_failed',
        <String, Object?>{
          'callId': _state.session?.callId,
          'error': error.toString(),
        },
      );
    } finally {
      _resetToIdle('end_cleanup');
    }
  }

  Future<void> setMuted(bool muted) async {
    _guardPhase(
      expected: const <CallPhase>{CallPhase.connected},
      action: 'set_muted',
    );

    await _mediaEngine.setMuted(muted);
    _state = _state.copyWith(
      isMuted: muted,
      updatedAt: _clock(),
    );
    _controller.add(_state);
    _log(
      'call.mute_updated',
      <String, Object?>{
        'callId': _state.session?.callId,
        'isMuted': muted,
      },
    );
  }

  Future<void> setSpeakerOn(bool speakerOn) async {
    _guardPhase(
      expected: const <CallPhase>{CallPhase.connected},
      action: 'set_speaker_on',
    );

    await _mediaEngine.setSpeakerOn(speakerOn);
    _state = _state.copyWith(
      isSpeakerOn: speakerOn,
      updatedAt: _clock(),
    );
    _controller.add(_state);
    _log(
      'call.speaker_updated',
      <String, Object?>{
        'callId': _state.session?.callId,
        'isSpeakerOn': speakerOn,
      },
    );
  }

  Future<void> dispose() async {
    if (_state.phase != CallPhase.idle) {
      try {
        await _mediaEngine.disconnect();
      } catch (_) {
        // Ignore dispose disconnect errors; engine is being torn down.
      }
    }
    await _controller.close();
  }

  void _guardStartAllowed(String action) {
    _guardPhase(expected: const <CallPhase>{CallPhase.idle}, action: action);
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
    final hasJwtShape = token.split('.').length == 3;

    if (uri == null || !(uri.isScheme('ws') || uri.isScheme('wss'))) {
      throw CallLifecycleException('Invalid roomUrl.');
    }

    if (token.trim().isEmpty || !hasJwtShape) {
      throw CallLifecycleException('Invalid token.');
    }
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

    _state = _state.copyWith(
      phase: to,
      session: session,
      reason: reason,
      isMuted: to == CallPhase.connected ? _state.isMuted : false,
      isSpeakerOn: to == CallPhase.connected ? _state.isSpeakerOn : false,
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

  void _resetToIdle(String event) {
    _state = CallState(
      phase: CallPhase.idle,
      isMuted: false,
      isSpeakerOn: false,
      updatedAt: _clock(),
    );

    _controller.add(_state);
    _log(event, const <String, Object?>{});
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
}
