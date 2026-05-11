import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/engine/call_engine.dart';

enum VoiceCallUiMode {
  idle,
  connecting,
  inCall,
  reconnecting,
  disconnected,
  failed,
}

@immutable
class VoiceCallUiState {
  const VoiceCallUiState({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.showAccept,
    required this.showReject,
    required this.showEnd,
    required this.controlsEnabled,
    required this.isMuted,
    required this.isSpeakerOn,
  });

  final VoiceCallUiMode mode;
  final String title;
  final String subtitle;
  final bool showAccept;
  final bool showReject;
  final bool showEnd;
  final bool controlsEnabled;
  final bool isMuted;
  final bool isSpeakerOn;

  factory VoiceCallUiState.fromCallState(CallState state) {
    final peer = state.session?.peerId ?? 'Unknown';

    switch (state.phase) {
      case CallPhase.idle:
        return const VoiceCallUiState(
          mode: VoiceCallUiMode.idle,
          title: 'No active call',
          subtitle: 'Ready to call',
          showAccept: false,
          showReject: false,
          showEnd: false,
          controlsEnabled: false,
          isMuted: false,
          isSpeakerOn: false,
        );
      case CallPhase.connecting:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.connecting,
          title: 'Connecting to $peer',
          subtitle: 'Establishing media session',
          showAccept: false,
          showReject: false,
          showEnd: true,
          controlsEnabled: false,
          isMuted: false,
          isSpeakerOn: false,
        );
      case CallPhase.connected:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.inCall,
          title: 'In call with $peer',
          subtitle: state.session?.direction == CallDirection.outgoing
              ? 'Connected (outgoing)'
              : 'Connected',
          showAccept: false,
          showReject: false,
          showEnd: true,
          controlsEnabled: true,
          isMuted: state.isMuted,
          isSpeakerOn: state.isSpeakerOn,
        );
      case CallPhase.reconnecting:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.reconnecting,
          title: 'Reconnecting',
          subtitle: state.reason ?? 'Recovering media session',
          showAccept: false,
          showReject: false,
          showEnd: true,
          controlsEnabled: false,
          isMuted: state.isMuted,
          isSpeakerOn: state.isSpeakerOn,
        );
      case CallPhase.disconnected:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.disconnected,
          title: 'Disconnected',
          subtitle: state.reason ?? 'Session ended',
          showAccept: false,
          showReject: false,
          showEnd: false,
          controlsEnabled: false,
          isMuted: false,
          isSpeakerOn: false,
        );
      case CallPhase.failed:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.failed,
          title: 'Connection failed',
          subtitle: state.reason ?? 'Unable to establish media session',
          showAccept: false,
          showReject: false,
          showEnd: false,
          controlsEnabled: false,
          isMuted: false,
          isSpeakerOn: false,
        );
    }
  }
}

class VoiceCallController extends ChangeNotifier {
  VoiceCallController({required CallEngine engine})
      : _engine = engine,
        _uiState = VoiceCallUiState.fromCallState(engine.state) {
    _subscription = _engine.states.listen(_handleState);
  }

  final CallEngine _engine;
  late final StreamSubscription<CallState> _subscription;

  VoiceCallUiState _uiState;

  VoiceCallUiState get uiState => _uiState;
  CallState get callState => _engine.state;

  Future<void> startOutgoing({
    required String callId,
    required String peerId,
    required String roomUrl,
    required String token,
  }) {
    return _engine.connectSession(
      callId: callId,
      peerId: peerId,
      roomUrl: roomUrl,
      token: token,
      direction: CallDirection.outgoing,
    );
  }

  @Deprecated('Invitation accept is not owned by VoiceCallController anymore.')
  Future<void> acceptIncoming({
    required String roomUrl,
    required String token,
  }) {
    throw CallLifecycleException(
      'acceptIncoming is removed. Handle invitation externally and call startOutgoing/connectSession.',
    );
  }

  @Deprecated('Invitation reject is not owned by VoiceCallController anymore.')
  Future<void> rejectIncoming({String reason = 'rejected'}) {
    throw CallLifecycleException(
      'rejectIncoming is removed. Handle invitation externally in signaling layer.',
    );
  }

  @Deprecated('Media session becomes connected automatically after connect.')
  void markOutgoingConnected() {
    throw CallLifecycleException('markOutgoingConnected is removed.');
  }

  Future<void> endCall({String reason = 'ended_by_user'}) {
    return _engine.endCall(reason: reason);
  }

  Future<void> toggleMute() async {
    if (_engine.state.phase != CallPhase.connected) {
      return;
    }
    await _engine.setMuted(!_engine.state.isMuted);
  }

  Future<void> toggleSpeaker() async {
    if (_engine.state.phase != CallPhase.connected) {
      return;
    }
    await _engine.setSpeakerOn(!_engine.state.isSpeakerOn);
  }

  void _handleState(CallState state) {
    _uiState = VoiceCallUiState.fromCallState(state);

    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}