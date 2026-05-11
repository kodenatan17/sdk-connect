import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk_connect.dart';

import 'config/config_sdk.dart';

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

  final List<String> _timeline = <String>[];
  SDKConnectCallType _preferredWidgetMode = SDKConnectCallType.voice;

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
          onConnectionStateChanged: (state, callState) {
            _addTimeline('connection: ${state.name} (${callState.reason ?? 'ok'})');
          },
          onReconnecting: (_) {
            _addTimeline('reconnecting...');
            _showMessage('Trying to recover connection...');
          },
          onReconnected: (_) {
            _addTimeline('reconnected');
            _showMessage('Connection recovered');
          },
          onConnectionLost: (state, reason) {
            _addTimeline('connection_lost: ${reason ?? 'unknown'}');
            _showMessage('Connection lost: ${reason ?? 'unknown'}');
            if (state.reason == 'remote_participant_left') {
              _showMessage('Remote participant left the call.');
            }
          },
          onParticipantJoined: (participantId) {
            _addTimeline('participant_joined: $participantId');
          },
          onParticipantLeft: (participantId) {
            _addTimeline('participant_left: $participantId');
            _showMessage('Participant left: $participantId');
          },
          onCallWarning: (warning, _) {
            _addTimeline('warning: $warning');
          },
          onCallRecovered: (reason, _) {
            _addTimeline('recovered: $reason');
          },
          onNetworkQualityChanged: (network) {
            _addTimeline('network: score=${network.score ?? -1}, weak=${network.isWeak}');
          },
          onAudioRouteChanged: (route) {
            _addTimeline('audio_route: ${route.name}');
          },
          onError: (event) {
            _addTimeline('error: ${event.operation}');
            _showMessage('SDK error on ${event.operation}.');
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

  Future<void> _startOutgoing(SDKConnectCallType callType) async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.startCall(
        callId: _randomCallId(),
        peerId: 'peer-b',
        callType: callType,
      );
    } on P2PLimitExceededException {
      _showMessage('P2P only: max 2 participants per room.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to start outgoing call.');
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _addTimeline(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _timeline.insert(0, '${DateTime.now().toIso8601String()}  $message');
      if (_timeline.length > 25) {
        _timeline.removeRange(25, _timeline.length);
      }
    });
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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('SDK Connect Example'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: 'SDK Only'),
              Tab(text: 'Plug-and-Play Widget'),
            ],
          ),
        ),
        body: TabBarView(
          children: <Widget>[
            _SdkOnlyDemo(
              sdk: sdk,
              timeline: _timeline,
              onStartVoice: () => _startOutgoing(SDKConnectCallType.voice),
              onStartVideo: () => _startOutgoing(SDKConnectCallType.video),
              onEnd: _endCall,
            ),
            _WidgetDemo(
              sdk: sdk,
              preferredMode: _preferredWidgetMode,
              onModeChanged: (mode) {
                setState(() {
                  _preferredWidgetMode = mode;
                });
              },
              onStart: () => _startOutgoing(_preferredWidgetMode),
            ),
          ],
        ),
      ),
    );
  }
}

class _SdkOnlyDemo extends StatelessWidget {
  const _SdkOnlyDemo({
    required this.sdk,
    required this.timeline,
    required this.onStartVoice,
    required this.onStartVideo,
    required this.onEnd,
  });

  final SDKConnect sdk;
  final List<String> timeline;
  final Future<void> Function() onStartVoice;
  final Future<void> Function() onStartVideo;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      stream: sdk.runtimeStates,
      initialData: sdk.runtimeState,
      builder: (context, snapshot) {
        final runtime = snapshot.data ?? sdk.runtimeState;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Connection: ${runtime.connectionState.name}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Participant: ${runtime.participants.remoteParticipantId ?? '-'}'),
              Text('Audio route: ${runtime.media.audioRoute.name}'),
              Text('Weak network: ${runtime.network.isWeak}'),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  FilledButton(
                    onPressed: onStartVoice,
                    child: const Text('Start Voice'),
                  ),
                  FilledButton(
                    onPressed: onStartVideo,
                    child: const Text('Start Video'),
                  ),
                  OutlinedButton(
                    onPressed: sdk.toggleMute,
                    child: Text(runtime.media.localAudioEnabled ? 'Mute' : 'Unmute'),
                  ),
                  OutlinedButton(
                    onPressed: sdk.toggleSpeaker,
                    child: const Text('Toggle Speaker'),
                  ),
                  OutlinedButton(
                    onPressed: sdk.video.toggleCamera,
                    child: Text(runtime.media.localVideoEnabled ? 'Camera Off' : 'Camera On'),
                  ),
                  FilledButton.tonal(
                    onPressed: onEnd,
                    child: const Text('End Call'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text('Lifecycle/Recovery Timeline', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: timeline.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(timeline[index]),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _WidgetDemo extends StatelessWidget {
  const _WidgetDemo({
    required this.sdk,
    required this.preferredMode,
    required this.onModeChanged,
    required this.onStart,
  });

  final SDKConnect sdk;
  final SDKConnectCallType preferredMode;
  final ValueChanged<SDKConnectCallType> onModeChanged;
  final Future<void> Function() onStart;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SDKConnectRuntimeState>(
      stream: sdk.runtimeStates,
      initialData: sdk.runtimeState,
      builder: (context, snapshot) {
        final runtime = snapshot.data ?? sdk.runtimeState;

        if (runtime.connectionState == SDKConnectConnectionState.idle) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SegmentedButton<SDKConnectCallType>(
                    segments: const <ButtonSegment<SDKConnectCallType>>[
                      ButtonSegment<SDKConnectCallType>(
                        value: SDKConnectCallType.voice,
                        icon: Icon(Icons.call),
                        label: Text('Voice Widget'),
                      ),
                      ButtonSegment<SDKConnectCallType>(
                        value: SDKConnectCallType.video,
                        icon: Icon(Icons.videocam),
                        label: Text('Video Widget'),
                      ),
                    ],
                    selected: <SDKConnectCallType>{preferredMode},
                    onSelectionChanged: (selection) {
                      onModeChanged(selection.first);
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start Plug-and-Play Call'),
                  ),
                ],
              ),
            ),
          );
        }

        final isVideo = runtime.callState.session?.callType == CallType.video;
        if (isVideo) {
          return RemoteVideoCallWidget(sdk: sdk);
        }

        return RemoteVoiceCallWidget(sdk: sdk);
      },
    );
  }
}
