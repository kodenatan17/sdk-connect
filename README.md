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
await sdk.startCall(peerId: 'peer-b', callId: 'call-123');
await sdk.setMuted(true);
await sdk.setSpeakerOn(true);
await sdk.endCall(reason: 'ended_by_user');
await sdk.dispose();
```

## Consumer Integration Reference

### Public states/events (custom UI)

Connection state (`SDKConnectConnectionState`):
- `idle`: no active session.
- `connecting`: session setup in progress.
- `connected`: media active.
- `reconnecting`: temporary recovery.
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
- `onEvent`, `onUser`, `onConnection`, `onToken`, `onError`

### Widgets (plug-and-play)

- `RemoteVoiceCallWidget`
- `RemoteVideoCallWidget`

Widget callbacks (`SDKConnectWidgetCallbacks`):
- `onCallStateChanged(phase)`
- `onReconnect()`
- `onDisconnected(reason)`
- `onEnded(reason)`

Terminal callback rule:
- `onDisconnected` and `onEnded` are fired only on `disconnected`/`failed`.

Fallback handlers:
- Voice widget includes built-in avatar/status fallback UI.
- Video widget shows built-in placeholders when local/remote video widgets are missing or unavailable.

### Ownership boundaries

- Business signaling (invite/accept/reject): your app/backend.
- SDK lifecycle and media session state: `SDKConnect` + `CallEngine`.
- Presentation/widgets: render-only observers of SDK runtime state.

### Security notes

- Use short-lived backend-issued tokens.
- Never log or persist token values in client logs/analytics.

## Example App

See `example/`:
- `main.dart`: SDK bootstrap + navigation.
- `voice/voice_call_screen.dart`: signaling UI + `RemoteVoiceCallWidget`.
- `video/video_call_screen.dart`: signaling UI + `RemoteVideoCallWidget`.

The example keeps signaling ownership outside SDKConnect and uses SDK callbacks for UI reactions.
