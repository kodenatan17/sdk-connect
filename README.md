# SDK Connect

SDK Connect is a transport-agnostic Flutter call SDK for P2P media sessions.

It keeps a strict separation of ownership:
- Business signaling: your app/backend (invite, reject, call intent).
- SDK lifecycle: SDKConnect + CallEngine (media/session state).
- Presentation/widgets: your UI and SDK widgets (render + callbacks only).

## Core Contract

- `CallEngine` is the single source of truth for call lifecycle.
- Lifecycle phases are fixed and consistent across voice/video:
  - `idle`
  - `connecting`
  - `connected`
  - `reconnecting`
  - `disconnected`
  - `failed`
- SDK Connect does not own signaling transport.
- P2P only: maximum 2 participants per session.

## Install

```yaml
dependencies:
  sdk_connect:
    git:
      url: https://github.com/kodenatan17/sdk-connect.git
```

```bash
flutter pub get
```

## Public SDK API

Create once and reuse:

```dart
final sdk = SDKConnect.create(
  localUserId: currentUserId,
  tokenProvider: tokenProvider,
  callbacks: SDKConnectCallbacks(
    onEvent: (event) {},
    onConnectionStateChanged: (state, callState) {},
  ),
);
```

Main operations:

```dart
await sdk.initialize();

// Start a voice call
await sdk.startCall(peerId: 'peer-b', callId: createCallId());

// Start a video call
await sdk.startCall(
  peerId: 'peer-b',
  callId: createCallId(),
  callType: SDKConnectCallType.video,
);

// Media controls
await sdk.setMuted(true);
await sdk.setSpeakerOn(true);
await sdk.setVideoEnabled(true);
await sdk.toggleCamera();

await sdk.endCall(reason: 'ended_by_user');
await sdk.dispose();
```

> Use `createCallId()` (from `example/shared/call_id_generator.dart`) to generate a secure random call ID. Never use timestamps as call IDs.

## Consumer Integration Reference

### Voice & Video Call Types

`SDKConnectCallType`:
- `voice`: audio-only session.
- `video`: audio + video; camera is enabled automatically on `startCall`.

Pass `callType` to `startCall` to select the session type. The type propagates from facade → `CallEngine` → media engine.

### Public states/events (custom UI)

Connection state (`SDKConnectConnectionState`):
- `idle`: no active session.
- `connecting`: session setup in progress.
- `connected`: media active.
- `reconnecting`: temporary recovery in progress.
- `disconnected`: terminal end.
- `failed`: terminal error.

Event stream (`sdk.events`) categories:
- `SDKConnectEventKind.user`
- `SDKConnectEventKind.connection`
- `SDKConnectEventKind.token`
- `SDKConnectEventKind.error`

Useful callbacks (`SDKConnectCallbacks`):
- `onConnectionStateChanged`
- `onReconnecting`, `onReconnected`, `onConnectionLost`
- `onParticipantJoined`, `onParticipantLeft`
- `onNetworkQualityChanged`, `onAudioRouteChanged`
- `onLocalVideoChanged`, `onRemoteVideoChanged`
- `onEvent`, `onUser`, `onConnection`, `onToken`, `onError`

### Runtime State

`sdk.runtimeState` (and `sdk.runtimeStates` stream) exposes a unified snapshot:

```dart
sdk.runtimeStates.listen((state) {
  print(state.connectionState);       // SDKConnectConnectionState
  print(state.participants.hasRemoteParticipant);
  print(state.media.localVideoEnabled);
  print(state.network.isWeak);
});
```

`hasRemoteParticipant` is `true` only during `connected` or `reconnecting`; it is `false` during `connecting` and after termination.

### Production Reliability

Configure via `SDKConnectReliabilityConfig`:

```dart
SDKConnect.create(
  // ...
  reliability: SDKConnectReliabilityConfig(
    reconnectPolicy: CallReconnectPolicy(...),
    networkThresholds: CallNetworkThresholds(...),
  ),
);
```

Built-in reliability features:
- **Auto-reconnect**: transient disconnects trigger automatic session recovery.
- **ICE recovery hook**: ICE failure is detected and renegotiated without tearing down the call.
- **Silent token refresh**: token rotation on reconnect without user-visible teardown.
- **Adaptive audio-priority fallback**: reduces media quality gracefully when network degrades.
- **Media session restoration**: after an interruption, mute/speaker/video state is fully restored (`_restoreMediaSession` triggers on both `connected` and `reconnecting` phases).

### Lifecycle Safety

- All `CallEngine` operations are serialized through an operation queue.
- Strict FSM phase transitions prevent invalid state changes.
- App lifecycle (foreground/background) and audio interruption events are handled automatically.
- Terminal events (`disconnected`, `failed`) are deduplicated — safe to drive navigation.
- Action debounce: 350 ms per-action window prevents double-trigger.

### Widgets (plug-and-play)

- `RemoteVoiceCallWidget`
- `RemoteVideoCallWidget`

Widget callbacks (`SDKConnectWidgetCallbacks`):
- `onCallStateChanged(phase)`
- `onReconnect()`
- `onDisconnected(reason)`
- `onEnded(reason)`

Widget phase (`SDKConnectWidgetPhase`):
- `calling`   → SDK `connecting`
- `connected` → SDK `connected` or `reconnecting`
- `ended`     → SDK `idle`, `disconnected`, or `failed`

Terminal callback rule:
- `onDisconnected` and `onEnded` are fired only on `disconnected`/`failed`, and are deduplicated — safe to use for navigation/cleanup.

Fallback handlers:
- Voice widget includes built-in avatar/status fallback UI.
- Video widget shows built-in placeholders when local/remote video tracks are missing or unavailable.

### Ownership boundaries

- Business signaling (invite/accept/reject): your app/backend.
- SDK lifecycle and media session state: `SDKConnect` + `CallEngine`.
- Presentation/widgets: render-only observers of SDK runtime state.

### Security notes

- Call IDs must be generated with a secure random source. Never use timestamps.
- Token provider receives a short-lived backend-issued token per session.
- JWT `exp` claim is validated before media connect; expired tokens are rejected.
- `callType` mismatch between caller and callee is rejected before media join.
- Sanitized errors only — raw exceptions and token payloads are never exposed publicly.
- Never log or persist token values in client logs/analytics.

## Example App

See `example/`:
- `main.dart`: SDK bootstrap + navigation.
- `shared/call_id_generator.dart`: secure random `createCallId()` utility.
- `voice/voice_call_screen.dart`: signaling UI + `RemoteVoiceCallWidget`.
- `video/video_call_screen.dart`: signaling UI + `RemoteVideoCallWidget`.

The example keeps signaling ownership outside SDKConnect and uses SDK callbacks for UI reactions.
