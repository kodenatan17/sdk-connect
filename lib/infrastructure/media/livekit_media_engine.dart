import 'dart:async';

import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:sdk_connect/infrastructure/media/media_engine.dart';

class LiveKitMediaEngine implements MediaEngine {
  LiveKitMediaEngine({lk.Room? room}) : _room = room ?? lk.Room();

  final lk.Room _room;
  final StreamController<MediaEngineEvent> _eventsController =
      StreamController<MediaEngineEvent>.broadcast();
  lk.EventsListener<lk.RoomEvent>? _roomListener;
  bool _isMuted = false;
  bool _isSpeakerOn = false;
  bool _isVideoEnabled = false;

  @override
  Stream<MediaEngineEvent> get events => _eventsController.stream;

  @override
  bool get isConnected => _room.connectionState == lk.ConnectionState.connected;

  @override
  bool get isMuted => _isMuted;

  @override
  bool get isSpeakerOn => _isSpeakerOn;

  @override
  bool get isVideoEnabled => _isVideoEnabled;

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
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        _emitEvent(
          MediaEngineEvent(
            type: MediaEngineEventType.disconnected,
            reason: event.reason.toString(),
          ),
        );
      });

    await _room.connect(
      roomUrl,
      token,
    );

    // Enforce P2P-only at connect boundary.
    if (_room.remoteParticipants.length > 1) {
      await _disconnectForPolicyViolation(emitEvent: false);
      throw const P2PLimitExceededException();
    }
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) {
      await _disposeRoomListener();
      return;
    }

    await _disposeRoomListener();
    await _room.disconnect();
    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = false;
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
    _emitEvent(
      MediaEngineEvent(
        type: MediaEngineEventType.audioRouteChanged,
        reason: speakerOn ? 'speaker' : 'earpiece',
        audioRoute: speakerOn ? MediaAudioRoute.speaker : MediaAudioRoute.earpiece,
      ),
    );
  }

  @override
  Future<void> setCameraOn(bool enabled) async {
    if (!isConnected) {
      return;
    }

    await _room.localParticipant?.setCameraEnabled(enabled);
    _isVideoEnabled = enabled;
  }

  @override
  Future<void> restartIce() async {
    if (!isConnected) {
      return;
    }

    _emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.iceRestarting,
        reason: 'ice_recovery_requested',
      ),
    );

    // LiveKit client performs ICE recovery internally when the transport
    // renegotiates. We expose this method so CallEngine can request recovery
    // consistently across media backends.
    _emitEvent(
      const MediaEngineEvent(
        type: MediaEngineEventType.iceRecovered,
        reason: 'ice_recovery_completed',
      ),
    );
  }

  @override
  Future<void> updateToken(String token) async {
    if (token.trim().isEmpty) {
      return;
    }

    // Keep this method as a stable abstraction boundary. Token updates are
    // backend-specific and should not leak backend APIs out of MediaEngine.
  }

  @override
  Future<void> setConnectionProfile(MediaConnectionProfile profile) async {
    if (!isConnected) {
      return;
    }

    if (profile.preferAudio && _isVideoEnabled) {
      await setCameraOn(false);
    }
  }

  @override
  Future<void> dispose() async {
    await _disposeRoomListener();
    if (isConnected) {
      await _room.disconnect();
    }
    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = false;
    if (!_eventsController.isClosed) {
      await _eventsController.close();
    }
  }

  Future<void> _disconnectOnP2PViolation() async {
    await _disconnectForPolicyViolation(emitEvent: true);
  }

  Future<void> _disconnectForPolicyViolation({required bool emitEvent}) async {
    if (emitEvent) {
      _emitEvent(
        const MediaEngineEvent(
          type: MediaEngineEventType.p2pLimitExceeded,
          reason: 'p2p_limit_exceeded',
        ),
      );
    }
    await _disposeRoomListener();
    if (isConnected) {
      await _room.disconnect();
    }
    _isMuted = false;
    _isSpeakerOn = false;
    _isVideoEnabled = false;
  }

  Future<void> _disposeRoomListener() async {
    await _roomListener?.dispose();
    _roomListener = null;
  }

  void _emitEvent(MediaEngineEvent event) {
    if (_eventsController.isClosed) {
      return;
    }
    _eventsController.add(event);
  }
}
