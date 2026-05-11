import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sdk_connect/sdk_connect.dart';

import 'config/config_sdk.dart';
import 'shared/call_id_generator.dart';
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

// ── Bootstrap ─────────────────────────────────────────────────────────────────

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
        localUserId: SdkConfig.localUserId,
        tokenProvider: _tokenProvider,
      );

      if (!mounted) {
        await sdk.dispose();
        return;
      }

      setState(() => _sdk = sdk);
    } catch (error) {
      if (!mounted) return;
      setState(() => _bootstrapError = error);
    }
  }

  Future<SDKConnectCredentials> _tokenProvider(SDKConnectTokenRequest _) async {
    return SDKConnectCredentials(
      roomUrl: SdkConfig.requireValidRoomUrl(),
      token: SdkConfig.requireValidToken(),
    );
  }

  @override
  void dispose() {
    final sdk = _sdk;
    if (sdk != null) unawaited(sdk.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _bootstrapError;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('SDK Connect Example')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Initialization failed: $error'),
          ),
        ),
      );
    }

    final sdk = _sdk;
    if (sdk == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return _HomeScreen(sdk: sdk);
  }
}

// ── Home ──────────────────────────────────────────────────────────────────────

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.sdk});

  final SDKConnect sdk;

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
                'Choose a feature screen. The SDK instance is initialised once and reused.',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _navigate(
                  context,
                  VoiceCallScreen(
                    sdk: sdk,
                    createCallId: generateCallId,
                    peerId: SdkConfig.defaultPeerId,
                  ),
                ),
                icon: const Icon(Icons.call),
                label: const Text('Voice Call'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _navigate(
                  context,
                  VideoCallScreen(
                    sdk: sdk,
                    createCallId: generateCallId,
                    peerId: SdkConfig.defaultPeerId,
                  ),
                ),
                icon: const Icon(Icons.videocam),
                label: const Text('Video Call'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }
}
