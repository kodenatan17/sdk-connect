import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

class IncomingCallScreen extends StatelessWidget {
  const IncomingCallScreen({
    super.key,
    required this.peerId,
    required this.callType,
    required this.onAccept,
    required this.onReject,
  });

  final String peerId;
  final CallType callType;
  final Future<void> Function() onAccept;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          callType == CallType.video
              ? 'Incoming Video Call'
              : 'Incoming Voice Call',
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  callType == CallType.video
                      ? Icons.video_call
                      : Icons.ring_volume,
                  size: 56,
                ),
                const SizedBox(height: 16),
                Text(
                  'Incoming ${callType.name} call from $peerId',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => onReject(),
                      icon: const Icon(Icons.call_end),
                      label: const Text('Reject'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => onAccept(),
                      icon: Icon(
                        callType == CallType.video
                            ? Icons.videocam
                            : Icons.call,
                      ),
                      label: const Text('Accept'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
