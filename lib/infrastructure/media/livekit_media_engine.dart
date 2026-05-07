import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:sdk_connect/infrastructure/media/media_engine.dart';

class LiveKitMediaEngine implements MediaEngine {
  LiveKitMediaEngine({lk.Room? room}) : _room = room ?? lk.Room();

  final lk.Room _room;
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  bool _isMuted = false;
  bool _isSpeakerOn = false;

  @override
  bool get isConnected => _room.connectionState == lk.ConnectionState.connected;

  @override
  bool get isMuted => _isMuted;

  @override
  bool get isSpeakerOn => _isSpeakerOn;

  @override
  Future<void> connect({
    required String roomUrl,
    required String token,
  }) async {
    if (isConnected) {
      return;
    }

    _roomListener ??= _room.createListener()
      ..on<lk.ParticipantConnectedEvent>((_) {
        if (_room.remoteParticipants.length > 1) {
          unawaited(_disconnectOnP2PViolation());
        }
      });

    await _room.connect(
      roomUrl,
      token,
    );

    // Enforce P2P-only at connect boundary.
    if (_room.remoteParticipants.length > 1) {
      await _disconnectOnP2PViolation();
      throw StateError('P2P only: group call is not supported.');
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) {
      return;
    }

    await _roomListener?.dispose();
    _roomListener = null;
    await _room.disconnect();
    _isMuted = false;
    _isSpeakerOn = false;
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (!isConnected) {
      return;
    }

    await _room.localParticipant?.setMicrophoneEnabled(!muted);
    _isMuted = muted;
  }

  @override
  Future<void> setSpeakerOn(bool speakerOn) async {
    if (!isConnected) {
      return;
    }

    await lk.Hardware.instance.setSpeakerphoneOn(speakerOn);
    _isSpeakerOn = speakerOn;
  }

  Future<void> _disconnectOnP2PViolation() async {
    await _roomListener?.dispose();
    _roomListener = null;
    if (isConnected) {
      await _room.disconnect();
    }
  }
}
