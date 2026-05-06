import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:sdk_connect/infrastructure/media/media_engine.dart';

class LiveKitMediaEngine implements MediaEngine {
  LiveKitMediaEngine({lk.Room? room}) : _room = room ?? lk.Room();

  final lk.Room _room;

  @override
  bool get isConnected => _room.connectionState == lk.ConnectionState.connected;

  @override
  Future<void> connect({
    required String roomUrl,
    required String token,
  }) async {
    if (isConnected) {
      return;
    }

    await _room.connect(
      roomUrl,
      token,
    );
  }

  @override
  Future<void> disconnect() async {
    if (!isConnected) {
      return;
    }

    await _room.disconnect();
  }
}
