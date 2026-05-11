import 'package:sdk_connect/core/utils/structured_logger.dart';
import 'package:sdk_connect/engine/call_engine.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/presentation/voice/voice_call_controller.dart';
import 'package:sdk_connect/sdk/livekit_media_engine_factory.dart';
import 'package:sdk_connect/sdk/voice_call_sdk.dart';

class SdkConnectScope {
  SdkConnectScope._({
    required this.mediaEngine,
    required this.callEngine,
  });

  factory SdkConnectScope.liveKit({
    MediaEngine? mediaEngine,
    StructuredLogger? logger,
    DateTime Function()? clock,
  }) {
    final resolvedMediaEngine = mediaEngine ?? createLiveKitMediaEngine();
    final callEngine = CallEngine(
      mediaEngine: resolvedMediaEngine,
      logger: logger,
      clock: clock,
    );

    return SdkConnectScope._(
      mediaEngine: resolvedMediaEngine,
      callEngine: callEngine,
    );
  }

  final MediaEngine mediaEngine;
  final CallEngine callEngine;

  VoiceCallController createVoiceCallController() {
    return VoiceCallController(engine: callEngine);
  }

  VoiceCallSdk createVoiceCallSdk({
    required String localUserId,
    required VoiceCallTokenProvider tokenProvider,
    VoiceCallCallbacks callbacks = const VoiceCallCallbacks(),
  }) {
    return VoiceCallSdk(
      localUserId: localUserId,
      callEngine: callEngine,
      tokenProvider: tokenProvider,
      callbacks: callbacks,
    );
  }

  Future<void> dispose() {
    return callEngine.dispose();
  }
}