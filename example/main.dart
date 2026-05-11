import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk_connect.dart';

import 'config/config_sdk.dart';
import 'video/video_call_screen.dart';
import 'voice/voice_call_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SDK Connect Example',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const ExampleHomePage(),
    );
  }
}

class ExampleHomePage extends StatefulWidget {
  const ExampleHomePage({super.key});

  @override
  State<ExampleHomePage> createState() => _ExampleHomePageState();
}

class _ExampleHomePageState extends State<ExampleHomePage> {
  final ConfigSdk _config = const ConfigSdk();

  SDKConnect? _sdk;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSdk());
  }

  Future<void> _initializeSdk() async {
    try {
      final sdk = SDKConnect.create(
        localUserId: ConfigSdk.localUserId,
        tokenProvider: _config.createTokenProvider(),
        callbacks: SDKConnectCallbacks(
          onUser: (event) {
            if (!mounted) {
              return;
            }
            switch (event.type) {
              case SDKConnectUserEventType.outgoingStarted:
                break;
              case SDKConnectUserEventType.ended:
                _showMessage('Call ended: ${event.reason ?? 'ended'}');
              case SDKConnectUserEventType.p2pLimitExceeded:
                _showMessage('P2P only: max 2 participants per room.');
              case SDKConnectUserEventType.incomingReceived:
              case SDKConnectUserEventType.accepted:
              case SDKConnectUserEventType.rejected:
                break;
            }
          },
          onError: (event) {
            if (!mounted) {
              return;
            }
            _showMessage('SDKConnect error on ${event.operation}.');
          },
        ),
      );

      if (!mounted) {
        await sdk.dispose();
        return;
      }

      setState(() {
        _sdk = sdk;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
  }

  @override
  void dispose() {
    final sdk = _sdk;
    if (sdk != null) {
      unawaited(sdk.dispose());
    }
    super.dispose();
  }

  Future<void> _startOutgoingVoiceCall() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.voice.startCall(callId: _randomCallId(), peerId: 'peer-b');
    } on P2PLimitExceededException {
      _showMessage('P2P only: max 2 participants per room.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to start outgoing voice call.');
    }
  }

  Future<void> _startOutgoingVideoCall() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.video.startCall(callId: _randomCallId(), peerId: 'peer-b');
    } on P2PLimitExceededException {
      _showMessage('P2P only: max 2 participants per room.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to start outgoing video call.');
    }
  }

  Future<void> _endCall() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.endCall(reason: 'ended_by_user');
    } catch (_) {
      _showMessage('Failed to end call.');
    }
  }

  String _randomCallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'call_$hex';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SDK Connect Example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Initialization failed: $_error'),
          ),
        ),
      );
    }

    final sdk = _sdk;
    if (sdk == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SDK Connect Example')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<CallState>(
      initialData: sdk.state,
      stream: sdk.states,
      builder: (context, snapshot) {
        final state = snapshot.data ?? sdk.state;
        if (state.phase == CallPhase.idle) {
          return _IdleScreen(
            onStartOutgoingVoice: _startOutgoingVoiceCall,
            onStartOutgoingVideo: _startOutgoingVideoCall,
          );
        }

        final callType = state.session?.callType ?? CallType.voice;
        if (callType == CallType.video) {
          return VideoCallScreen(
            state: state,
            onEnd: _endCall,
            onToggleMute: sdk.video.toggleMute,
            onToggleSpeaker: sdk.video.toggleSpeaker,
            onToggleCamera: sdk.video.toggleCamera,
          );
        }

        return VoiceCallScreen(
          state: state,
          onEnd: _endCall,
          onToggleMute: sdk.voice.toggleMute,
          onToggleSpeaker: sdk.voice.toggleSpeaker,
        );
      },
    );
  }
}

class _IdleScreen extends StatelessWidget {
  const _IdleScreen({
    required this.onStartOutgoingVoice,
    required this.onStartOutgoingVideo,
  });

  final Future<void> Function() onStartOutgoingVoice;
  final Future<void> Function() onStartOutgoingVideo;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SDK Connect Example')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  'Voice & Video Call SDK Demo',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Flow: init -> call -> end\nPolicy: P2P only (max 2 participants)',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => onStartOutgoingVoice(),
                  icon: const Icon(Icons.call),
                  label: const Text('Start Outgoing Voice Call'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => onStartOutgoingVideo(),
                  icon: const Icon(Icons.videocam),
                  label: const Text('Start Outgoing Video Call'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
