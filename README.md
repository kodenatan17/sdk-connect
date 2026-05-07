# SDK Connect

Flutter voice-call SDK with a single `CallEngine` lifecycle, internal connection orchestration, and an SDK-only public API.

## Key Points

- Single source of truth in `CallEngine`
- SDK abstraction first (no direct LiveKit usage in app layer)
- Self-contained `VoiceCallSdk` facade for init, signaling, token resolution, and media connection
- Unified callbacks for user, connection, error, and token events
- Voice call lifecycle: `idle -> dialing/ringing -> connected -> ended -> idle`
- P2P only policy (maximum 2 participants)

## Installation

Add dependency:

```yaml
dependencies:
  sdk_connect:
    git:
      url: https://github.com/kodenatan17/sdk-connect.git
```

Then run:

```bash
flutter pub get
```

## Example Usage

The sample app is available in the `example/` folder with this structure:

```text
example/
  main.dart
  app.dart
  call_screen.dart
  incoming_call_screen.dart
  sdk_setup.dart
```

### How To Run

1. Use runtime values (do not hardcode secrets in source files).
2. Start a Flutter app that uses these `example/` files as entry source.
3. Run with `dart-define`:

```bash
flutter run \
  --dart-define=SDK_CONNECT_ROOM_URL=wss://your-livekit-url \
  --dart-define=SDK_CONNECT_ACCESS_TOKEN=your-short-lived-token
```

### Flow: Init -> Call -> End

1. Create the self-contained SDK facade:

```dart
const setup = SdkSetup();
final signaling = setup.createDemoSignaling();

final sdk = VoiceCallSdk.liveKit(
  localUserId: 'user-a',
  signaling: signaling,
  tokenProvider: setup.createTokenProvider(),
  signalValidator: setup.createSignalValidator(),
  callbacks: VoiceCallCallbacks(
    onUser: (event) {},
    onConnection: (event) {},
    onError: (event) {},
    onToken: (event) {},
  ),
);
```

2. Start outgoing call with SDK-only input:

```dart
await sdk.startCall(callId: 'call-123', peerId: 'peer-b');
```

The SDK requests credentials internally through `tokenProvider`, connects media,
and handles the remote accept signal internally.

3. Receive incoming call through signaling and accept:

```dart
setup.simulateIncomingForDemo(
  signaling: signaling,
  localUserId: 'user-a',
  callId: 'call-456',
  peerId: 'peer-a',
);

await sdk.acceptCall();
```

4. In-call controls (mute, speaker, end):

```dart
await sdk.toggleMute();
await sdk.toggleSpeaker();
await sdk.endCall(reason: 'ended_by_user');
```

### Key Snippets

- Self-contained SDK init:

```dart
final sdk = VoiceCallSdk.liveKit(
  localUserId: currentUserId,
  signaling: yourSignalingTransport,
  tokenProvider: yourTokenProvider,
  signalValidator: yourSignalValidator,
);
```

- Unified callback surface:

```dart
VoiceCallCallbacks(
  onUser: (event) {
    // incoming, accepted, rejected, ended, p2p-limit
  },
  onConnection: (event) {
    // ready, dialing, ringing, connected, ended, idle
  },
  onError: (event) {
    // operation + error payload
  },
  onToken: (event) {
    // requested, resolved, failed
  },
);
```

- Trusted signaling validation:

```dart
final yourSignalValidator = (VoiceCallSignal signal) async {
  return signal.toUserId == currentUserId &&
      trustedPeerIds.contains(signal.fromUserId);
};
```

- Optional SDK-provided UI controller over the same `CallEngine`:

```dart
final controller = sdk.createController();

return VoiceCallScreen(
  controller: controller,
  onAccept: sdk.acceptCall,
  onReject: () => sdk.rejectCall(),
  onEnd: () => sdk.endCall(),
);
```

- P2P enforcement handling:

```dart
try {
  await sdk.startCall(peerId: 'peer-b');
} on P2PLimitExceededException {
  // Room has more than 2 participants.
}
```

## Notes

- Provide a signaling transport implementation that carries `VoiceCallSignal` messages.
- Provide a short-lived backend token provider that returns `VoiceCallCredentials`.
- Validate signaling sender identity and call ownership before the SDK processes events.
- Do not bypass SDK abstractions by using LiveKit directly in UI/application code.
- Group call is intentionally rejected by design (P2P only).

## License

MIT