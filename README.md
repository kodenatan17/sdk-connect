# SDK Connect

Flutter call SDK with a single `CallEngine` lifecycle, internal media orchestration, and a plug-and-play `SDKConnect` public API.

## Design Goals

- `CallEngine` remains the single source of truth for call lifecycle and controls.
- `SDKConnect` is the main app-facing entry point.
- LiveKit stays fully hidden behind the SDK and media abstraction.
- Voice works now; video fits the same API shape later.
- P2P only: maximum 2 participants per room.

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

## Public API

### Main Entry

```dart
final sdk = SDKConnect.create(
  localUserId: currentUserId,
  signaling: yourSignalingTransport,
  tokenProvider: yourTokenProvider,
  signalValidator: yourSignalValidator,
  callbacks: SDKConnectCallbacks(
    onEvent: (event) {},
    onUser: (event) {},
    onConnection: (event) {},
    onError: (event) {},
    onToken: (event) {},
  ),
);
```

### Methods

```dart
Future<void> initialize({String? localUserId})
Future<void> startCall({required String peerId, String? callId, SDKConnectCallType callType = SDKConnectCallType.voice})
Future<void> acceptCall({SDKConnectCallType callType = SDKConnectCallType.voice})
Future<void> rejectCall({String reason = 'rejected'})
Future<void> endCall({String reason = 'ended_by_user'})
Future<void> setMuted(bool muted)
Future<void> toggleMute()
Future<void> setSpeakerOn(bool speakerOn)
Future<void> toggleSpeaker()
Future<void> dispose()
```

### Callbacks And Events

```dart
SDKConnectCallbacks(
  onEvent: (SDKConnectEvent event) {},
  onUser: (SDKConnectUserEvent event) {},
  onConnection: (SDKConnectConnectionEvent event) {},
  onError: (SDKConnectErrorEvent event) {},
  onToken: (SDKConnectTokenEvent event) {},
)
```

- `SDKConnectUserEvent`: outgoing started, incoming received, accepted, rejected, ended, P2P limit exceeded.
- `SDKConnectConnectionEvent`: initializing, ready, dialing, ringing, connected, ended, idle.
- `SDKConnectErrorEvent`: operation, error, stack trace.
- `SDKConnectTokenEvent`: requested, resolved, failed.
- `sdk.events`: unified stream of all SDK events.

### Signals And Token Input

```dart
class SDKConnectSignal {
  final SDKConnectSignalType type;
  final String callId;
  final String fromUserId;
  final String toUserId;
  final SDKConnectCallType callType;
  final String? reason;
}

class SDKConnectTokenRequest {
  final String callId;
  final String peerId;
  final CallDirection direction;
  final SDKConnectCallType callType;
}

class SDKConnectCredentials {
  final String roomUrl;
  final String token;
}
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

final sdk = SDKConnect.create(
  localUserId: 'user-a',
  signaling: signaling,
  tokenProvider: setup.createTokenProvider(),
  signalValidator: setup.createSignalValidator(),
  callbacks: SDKConnectCallbacks(
    onEvent: (event) {},
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
await sdk.setMuted(true);
await sdk.setSpeakerOn(true);
await sdk.endCall(reason: 'ended_by_user');
```

### Key Snippets

- Self-contained SDK init:

```dart
final sdk = SDKConnect.create(
  localUserId: currentUserId,
  signaling: yourSignalingTransport,
  tokenProvider: yourTokenProvider,
  signalValidator: yourSignalValidator,
);
```

- Unified callback surface:

```dart
SDKConnectCallbacks(
  onEvent: (event) {
    // unified stream callback for analytics or logging
  },
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
final yourSignalValidator = (SDKConnectSignal signal) async {
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

## Voice To Video Mapping

- Keep `SDKConnect` as the only entry point.
- Keep `startCall`, `acceptCall`, callbacks, and `sdk.events` unchanged.
- Use `SDKConnectCallType.voice` today and add `SDKConnectCallType.video` later.
- Keep `SDKConnectSignal`, `SDKConnectTokenRequest`, and `SDKConnectUserEvent` media-type aware now so video support lands without renaming methods or event channels.
- Add video-specific controls as additive APIs only when needed; existing voice flows remain valid.

## Notes

- Provide a signaling transport implementation that carries `SDKConnectSignal` messages.
- Provide a short-lived backend token provider that returns `SDKConnectCredentials`.
- Validate signaling sender identity and call ownership before the SDK processes events.
- Do not bypass SDK abstractions by using LiveKit directly in UI/application code.
- Group call is intentionally rejected by design (P2P only).

## License

MIT