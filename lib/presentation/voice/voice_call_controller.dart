import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sdk_connect/core/enums/call_direction.dart';
import 'package:sdk_connect/core/enums/call_phase.dart';
import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/engine/call_engine.dart';

enum VoiceCallUiMode {
  idle,
  outgoing,
  incoming,
  inCall,
  ended,
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
      case CallPhase.dialing:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.outgoing,
          title: 'Calling $peer',
          subtitle: 'Outgoing',
          showAccept: false,
          showReject: false,
          showEnd: true,
          controlsEnabled: false,
          isMuted: false,
          isSpeakerOn: false,
        );
      case CallPhase.ringing:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.incoming,
          title: 'Incoming call',
          subtitle: 'From $peer',
          showAccept: true,
          showReject: true,
          showEnd: false,
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
              : 'Connected (incoming)',
          showAccept: false,
          showReject: false,
          showEnd: true,
          controlsEnabled: true,
          isMuted: state.isMuted,
          isSpeakerOn: state.isSpeakerOn,
        );
      case CallPhase.ended:
        return VoiceCallUiState(
          mode: VoiceCallUiMode.ended,
          title: 'Call ended',
          subtitle: state.reason ?? 'Finished',
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
    return _engine.startOutgoing(
      callId: callId,
      peerId: peerId,
      roomUrl: roomUrl,
      token: token,
    );
  }

  Future<void> acceptIncoming({
    required String roomUrl,
    required String token,
  }) {
    return _engine.acceptIncoming(roomUrl: roomUrl, token: token);
  }

  Future<void> rejectIncoming({String reason = 'rejected'}) {
    return _engine.rejectIncoming(reason: reason);
  }

  void markOutgoingConnected() {
    _engine.markOutgoingConnected();
  }

  Future<void> endCall({String reason = 'ended_by_user'}) {
    return _engine.endCall(reason: reason);
  }

  Future<void> toggleMute() async {
    if (!_uiState.controlsEnabled) {
      return;
    }
    await _engine.setMuted(!_uiState.isMuted);
  }

  Future<void> toggleSpeaker() async {
    if (!_uiState.controlsEnabled) {
      return;
    }
    await _engine.setSpeakerOn(!_uiState.isSpeakerOn);
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