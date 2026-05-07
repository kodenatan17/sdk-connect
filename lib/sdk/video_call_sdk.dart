import 'package:sdk_connect/core/models/call_state.dart';
import 'package:sdk_connect/core/enums/call_type.dart';
import 'package:sdk_connect/core/errors/call_lifecycle_exception.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/sdk/video_picture_in_picture.dart';
import 'package:sdk_connect/sdk/voice_call_sdk.dart';

class VideoCallSdk {
  VideoCallSdk({
    required VoiceCallSdk voiceSdk,
    required CallEngine callEngine,
    VideoPictureInPictureController? pictureInPicture,
  })  : _voiceSdk = voiceSdk,
        _callEngine = callEngine,
        pictureInPicture = pictureInPicture ??
            MethodChannelVideoPictureInPictureController();

  final VoiceCallSdk _voiceSdk;
  final CallEngine _callEngine;
  final VideoPictureInPictureController pictureInPicture;

  CallState get state => _voiceSdk.state;
  Stream<CallState> get states => _voiceSdk.states;

  Future<void> initialize({String? localUserId}) {
    return _voiceSdk.initialize(localUserId: localUserId);
  }

  Future<void> startCall({
    required String peerId,
    String? callId,
  }) async {
    await _voiceSdk.startCall(
      peerId: peerId,
      callId: callId,
      callType: CallType.video,
    );
    await _callEngine.setVideoEnabled(true);
  }

  Future<void> acceptCall() async {
    final sessionType = _callEngine.state.session?.callType;
    if (sessionType == CallType.voice) {
      throw CallLifecycleException(
        'Incoming call is voice. Use VoiceCallSdk or SDKConnect.voice to accept it.',
      );
    }
    await _voiceSdk.acceptCall();
    if (sessionType == CallType.video) {
      await _callEngine.setVideoEnabled(true);
    }
  }

  Future<void> rejectCall({String reason = 'rejected'}) {
    return _voiceSdk.rejectCall(reason: reason);
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

  Future<void> setCameraEnabled(bool enabled) {
    return _callEngine.setVideoEnabled(enabled);
  }

  Future<void> toggleCamera() {
    return _callEngine.setVideoEnabled(!_callEngine.state.isVideoEnabled);
  }

  Future<void> enterPictureInPicture({
    VideoPictureInPictureConfig config = const VideoPictureInPictureConfig(),
  }) {
    return pictureInPicture.enable(config: config);
  }

  Future<void> exitPictureInPicture() {
    return pictureInPicture.disable();
  }

  Future<void> dispose() {
    return pictureInPicture.dispose();
  }
}
