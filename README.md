# SDK Connect

Flutter SDK for realtime voice call built with a single `CallEngine` lifecycle and SDK-first integration.

## Key Points

- Single source of truth in `CallEngine`
- SDK abstraction first (no direct LiveKit usage in app layer)
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

1. Initialize SDK scope:

```dart
const setup = SdkSetup();
final scope = await setup.initialize();
final controller = scope.createVoiceCallController();
```

2. Start outgoing call:

```dart
await controller.startOutgoing(
  callId: 'call-123',
  peerId: 'peer-b',
  roomUrl: roomUrl,
  token: token,
);
```

When remote side accepts (via signaling), transition to connected through your
application/controller event handling.

3. Receive incoming call and accept:

```dart
setup.simulateIncomingForDemo(
  scope: scope,
  callId: 'call-456',
  peerId: 'peer-a',
);

await controller.acceptIncoming(
  roomUrl: roomUrl,
  token: token,
);
```

4. In-call controls (mute, speaker, end):

```dart
await controller.toggleMute();
await controller.toggleSpeaker();
await controller.endCall(reason: 'ended_by_user');
```

### Key Snippets

- SDK init only:

```dart
final scope = SdkConnectScope.liveKit();
```

- Incoming UI + in-call UI integration:

```dart
if (controller.callState.phase == CallPhase.ringing) {
  return IncomingCallScreen(...);
}

return VoiceCallScreen(
  controller: controller,
  onEnd: () => controller.endCall(),
);
```

- P2P enforcement handling:

```dart
try {
  await controller.acceptIncoming(roomUrl: roomUrl, token: token);
} on P2PLimitExceededException {
  // Room has more than 2 participants.
}
```

## Notes

- Always validate token and room URL before starting or accepting a call.
- Use short-lived backend-issued access tokens at runtime only.
- Validate incoming signaling events (sender/session ownership) before driving call actions.
- Do not bypass SDK abstractions by using LiveKit directly in UI/application code.
- Group call is intentionally rejected by design (P2P only).

## License

MIT