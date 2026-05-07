import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sdk_connect/infrastructure/media/media_engine.dart';
import 'package:sdk_connect/sdk_connect.dart';

import 'call_screen.dart';
import 'sdk_setup.dart';

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
  final SdkSetup _setup = const SdkSetup();

  SDKConnect? _sdk;
  InMemorySDKConnectSignalingTransport? _signaling;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSdk());
  }

  Future<void> _initializeSdk() async {
    try {
      final signaling = _setup.createDemoSignaling();
      final sdk = SDKConnect.create(
        localUserId: SdkSetup.localUserId,
        signaling: signaling,
        tokenProvider: _setup.createTokenProvider(),
        signalValidator: _setup.createSignalValidator(),
        callbacks: SDKConnectCallbacks(
          onUser: (event) {
            if (!mounted) {
              return;
            }
            switch (event.type) {
              case SDKConnectUserEventType.incomingReceived:
              case SDKConnectUserEventType.outgoingStarted:
              case SDKConnectUserEventType.accepted:
                break;
              case SDKConnectUserEventType.rejected:
                _showMessage('Call rejected: ${event.reason ?? 'rejected'}');
              case SDKConnectUserEventType.ended:
                _showMessage('Call ended: ${event.reason ?? 'ended'}');
              case SDKConnectUserEventType.p2pLimitExceeded:
                _showMessage('P2P only: max 2 participants per room.');
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
        _signaling = signaling;
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

  Future<void> _startOutgoingCall() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.startCall(callId: _randomCallId(), peerId: 'peer-b');
    } on P2PLimitExceededException {
      _showMessage('P2P only: max 2 participants per room.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to start outgoing call.');
    }
  }

  void _simulateIncomingCall() {
    final signaling = _signaling;
    if (signaling == null) {
      return;
    }

    try {
      _setup.simulateIncomingForDemo(
        signaling: signaling,
        localUserId: SdkSetup.localUserId,
        callId: _randomCallId(),
        peerId: 'peer-a',
      );
    } catch (_) {
      _showMessage('Cannot receive incoming call right now.');
    }
  }

  Future<void> _acceptIncoming() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.acceptCall();
    } on P2PLimitExceededException {
      _showMessage('P2P only: room already has more than 2 participants.');
    } on StateError {
      _showMessage('Missing SDK runtime configuration.');
    } catch (_) {
      _showMessage('Failed to accept incoming call.');
    }
  }

  Future<void> _rejectIncoming() async {
    final sdk = _sdk;
    if (sdk == null) {
      return;
    }

    try {
      await sdk.rejectCall(reason: 'rejected_by_user');
    } catch (_) {
      _showMessage('Failed to reject incoming call.');
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
            onStartOutgoing: _startOutgoingCall,
            onSimulateIncoming: _simulateIncomingCall,
          );
        }

        return CallScreen(
          state: state,
          onAccept: _acceptIncoming,
          onReject: _rejectIncoming,
          onEnd: _endCall,
          onToggleMute: sdk.toggleMute,
          onToggleSpeaker: sdk.toggleSpeaker,
        );
      },
    );
  }
}

class _IdleScreen extends StatelessWidget {
  const _IdleScreen({
    required this.onStartOutgoing,
    required this.onSimulateIncoming,
  });

  final Future<void> Function() onStartOutgoing;
  final VoidCallback onSimulateIncoming;

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
                  'Voice Call SDK Demo',
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
                  onPressed: () => onStartOutgoing(),
                  icon: const Icon(Icons.call),
                  label: const Text('Start Outgoing Call'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: onSimulateIncoming,
                  icon: const Icon(Icons.ring_volume),
                  label: const Text('Simulate Incoming Call'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
