import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

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
      home: const _SdkBootstrapScreen(),
    );
  }
}

class _SdkBootstrapScreen extends StatefulWidget {
  const _SdkBootstrapScreen();

  @override
  State<_SdkBootstrapScreen> createState() => _SdkBootstrapScreenState();
}

class _SdkBootstrapScreenState extends State<_SdkBootstrapScreen> {
  SDKConnect? _sdk;
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeSdk());
  }

  Future<void> _initializeSdk() async {
    try {
      final sdk = SDKConnect.create(
        localUserId: _ExampleConfig.localUserId,
        tokenProvider: _createTokenProvider(),
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
        _bootstrapError = error;
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

  SDKConnectTokenProvider _createTokenProvider() {
    return (_) async => SDKConnectCredentials(
      roomUrl: _ExampleConfig.requireValidRoomUrl(),
      token: _ExampleConfig.requireValidToken(),
    );
  }

  String _createCallId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'call_$hex';
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SDK Connect Example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Initialization failed: $_bootstrapError'),
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

    return _ExampleHomeScreen(
      sdk: sdk,
      createCallId: _createCallId,
    );
  }
}

class _ExampleHomeScreen extends StatelessWidget {
  const _ExampleHomeScreen({
    required this.sdk,
    required this.createCallId,
  });

  final SDKConnect sdk;
  final String Function() createCallId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SDK Connect Example')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Plug-and-Play SDKConnect demo',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Choose a feature screen. The SDK instance is initialized once and reused.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VoiceCallScreen(
                        sdk: sdk,
                        createCallId: createCallId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.call),
                label: const Text('Voice Feature'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoCallScreen(
                        sdk: sdk,
                        createCallId: createCallId,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.videocam),
                label: const Text('Video Feature'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleConfig {
  static const String localUserId = 'demo-user-a';

  static const String _roomUrl = String.fromEnvironment(
    'SDK_CONNECT_ROOM_URL',
    defaultValue: '',
  );

  static const String _token = String.fromEnvironment(
    'SDK_CONNECT_ACCESS_TOKEN',
    defaultValue: '',
  );

  static String requireValidRoomUrl() {
    final value = _roomUrl.trim();
    if (value.isEmpty) {
      throw StateError('Missing SDK_CONNECT_ROOM_URL');
    }
    return value;
  }

  static String requireValidToken() {
    final value = _token.trim();
    if (value.isEmpty) {
      throw StateError('Missing SDK_CONNECT_ACCESS_TOKEN');
    }
    return value;
  }
}
