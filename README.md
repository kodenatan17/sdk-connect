# SDK Connect

Flutter call SDK with a single `CallEngine` lifecycle, internal media orchestration, and a plug-and-play `SDKConnect` public API.

Production reliability is included: auto reconnect, ICE recovery hooks, silent token refresh, adaptive audio-priority fallback, configurable network thresholds, app lifecycle handling, interruption recovery, and audio route management.

## Update (Media/Session Refactor)

SDKConnect has been refactored into a pure media/session SDK architecture.

### Before vs After

| Area | Before | After |
|---|---|---|
| SDK lifecycle ownership | SDK handled signaling + media lifecycle | SDK handles media/session lifecycle only |
| Lifecycle phases | `idle`, `dialing`, `ringing`, `connected`, `ended` | `idle`, `connecting`, `connected`, `reconnecting`, `disconnected`, `failed` |
| Signaling in SDK API | `signaling`, `signalValidator`, `SDKConnectSignal` in public API | Removed from SDK public API |
| Invite / accept / reject ownership | Owned by SDK / `CallEngine` | External signaling layer owns invitation lifecycle |
| Engine authority | Mixed lifecycle responsibilities | `CallEngine` is strict SSOT for media/session state |
| Transport coupling | Included signaling contract in SDK | Transport-agnostic SDK core |
| Reconnect reliability | Present | Preserved with in-flight dedup and strict transitions |
| P2P enforcement | Present | Preserved (`max 2` participants) |

### Migration Summary

- Keep using `SDKConnect` as the main app facade.
- Remove signaling transport wiring from SDK initialization.
- Handle invite/accept/reject in your app signaling layer.
- Call `startCall` (or `CallEngine.connectSession`) only when you are ready to start/join media.
- Treat SDK lifecycle as media/session lifecycle, not signaling lifecycle.

## Design Goals

- `CallEngine` remains the single source of truth for call lifecycle and controls.
- `SDKConnect` is the main app-facing entry point.
- LiveKit stays fully hidden behind the SDK and media abstraction.
- Voice and video use the same lifecycle model.
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
  tokenProvider: yourTokenProvider,
  reliability: const SDKConnectReliabilityConfig(
    reconnectPolicy: CallReconnectPolicy(),
    networkThresholds: CallNetworkThresholds(),
  ),
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
Future<void> endCall({String reason = 'ended_by_user'})
Future<void> setMuted(bool muted)
Future<void> toggleMute()
Future<void> setSpeakerOn(bool speakerOn)
Future<void> toggleSpeaker()
Future<void> setVideoEnabled(bool enabled)
Future<void> toggleCamera()
Future<void> dispose()
```

Removed from ownership (deprecated/throws):

```dart
Future<void> acceptCall({SDKConnectCallType? callType})
Future<void> rejectCall({String reason = 'rejected'})
```

### Callbacks and Events

```dart
SDKConnectCallbacks(
  onEvent: (SDKConnectEvent event) {},
  onUser: (SDKConnectUserEvent event) {},
  onConnection: (SDKConnectConnectionEvent event) {},
  onError: (SDKConnectErrorEvent event) {},
  onToken: (SDKConnectTokenEvent event) {},
)
```

- `SDKConnectUserEvent`: outgoing started, ended, P2P limit exceeded.
- `SDKConnectConnectionEvent`: initializing, ready, lifecycleChanged, connecting, connected, reconnecting, recovered, disconnected, failed, interruptionStarted, interruptionRecovered, mediaSessionRestored, audioRouteChanged, iceRecoveryStarted, iceRecovered, networkDegraded, networkRecovered, idle.
- `SDKConnectErrorEvent`: operation, sanitized error.
- `SDKConnectTokenEvent`: requested, resolved, refreshRequested, refreshed, refreshFailed, failed.
- `sdk.events`: unified stream of all SDK events.

### Token Input and Reliability Types

```dart
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

class SDKConnectReliabilityConfig {
  final CallReconnectPolicy reconnectPolicy;
  final CallNetworkThresholds networkThresholds;
}

class CallReconnectPolicy {
  final bool enabled;
  final int maxAttempts;
  final Duration initialDelay;
  final Duration maxDelay;
  final Duration graceTimeout;
  final Duration reconnectCooldown;
  final Duration tokenRefreshBeforeExpiry;
  final bool enableIceRecovery;
}

class CallNetworkThresholds {
  final int weakScore;
  final int stableScore;
  final Duration stableDuration;
  final int audioPriorityBitrateKbps;
  final int audioPriorityMaxVideoHeight;
  final int audioPriorityMaxVideoFps;
}
```

## Lifecycle Contract (Media/Session Only)

- `idle`
- `connecting`
- `connected`
- `reconnecting`
- `disconnected`
- `failed`

## Reliability Behavior

- Preserves active `CallEngine` session while reconnecting.
- Uses grace timeout before failing call on sustained network loss.
- Prevents reconnect loops with cooldown + bounded backoff.
- Deduplicates concurrent reconnect attempts and token refresh calls.
- Emits reconnect and recovery events.
- Supports ICE recovery hooks.
- Silently refreshes near-expiry tokens; concurrent refresh calls share a single in-flight future.
- Automatically downgrades to audio-priority on weak network.
- Automatically recovers to balanced profile when network is stable.

## Lifecycle Safety

- All state-mutating operations are serialized through an internal operation queue.
- Strict finite-state transitions are enforced; invalid transitions throw `CallLifecycleException`.
- Repeated identical actions are debounced automatically (350 ms window).
- App lifecycle is observed internally by `VoiceCallSdk` via `WidgetsBindingObserver`.
- On app background transitions, interruption events are emitted.
- On resume, media session state (mute/speaker/camera) is restored automatically.
- Audio route changes are tracked and surfaced as connection events.

## External Signaling Boundary

Signaling is intentionally outside SDK ownership.

- Your app/backend signaling layer validates invite/accept/reject messages.
- Your app decides when media should start/join.
- SDK starts media via `startCall` (or lower-level `CallEngine.connectSession`).
- SDK does not expose LiveKit directly.

## Recommended Reliability Preset

```dart
final sdk = SDKConnect.create(
  localUserId: currentUserId,
  tokenProvider: yourTokenProvider,
  reliability: const SDKConnectReliabilityConfig(
    reconnectPolicy: CallReconnectPolicy(
      enabled: true,
      maxAttempts: 6,
      initialDelay: Duration(seconds: 1),
      maxDelay: Duration(seconds: 12),
      graceTimeout: Duration(seconds: 25),
      reconnectCooldown: Duration(seconds: 15),
      tokenRefreshBeforeExpiry: Duration(minutes: 2),
      enableIceRecovery: true,
    ),
    networkThresholds: CallNetworkThresholds(
      weakScore: 35,
      stableScore: 65,
      stableDuration: Duration(seconds: 8),
      audioPriorityBitrateKbps: 180,
      audioPriorityMaxVideoHeight: 180,
      audioPriorityMaxVideoFps: 12,
    ),
  ),
);
```

## Example Usage

The sample app is available in the `example/` folder with a production-style feature-based structure:

```text
example/
  main.dart                        ← bootstrap + navigation only
  config/
    config_sdk.dart                ← SdkConfig: localUserId, peerId, credential providers
  shared/
    call_id_generator.dart         ← generateCallId() using Random.secure()
  voice/
    voice_call_screen.dart         ← signaling state + RemoteVoiceCallWidget
  video/
    video_call_screen.dart         ← signaling state + RemoteVideoCallWidget
```

What the example demonstrates:

- `main.dart` handles bootstrap and navigation only — no lifecycle logic.
- `config/config_sdk.dart` centralises all SDK configuration (`SdkConfig`). No config is duplicated across screens.
- `shared/call_id_generator.dart` provides a single `generateCallId()` utility used by both screens.
- `voice/voice_call_screen.dart` manages external signaling state (`dialing / ringing / rejected`) and delegates active-call rendering to `RemoteVoiceCallWidget` with all four callbacks wired.
- `video/video_call_screen.dart` mirrors voice but uses `SDKConnectCallType.video` and `RemoteVideoCallWidget`.
- Widget callbacks (`onCallStateChanged`, `onReconnect`, `onDisconnected`, `onEnded`) are wired at screen level. Widgets are pure observers — no lifecycle logic inside widgets.
- Consumer code stays on SDKConnect APIs/widgets only (no direct LiveKit usage).
- P2P contract is preserved (max 2 participants).

### UI State Aggregation

| SDKConnect State | Widget Phase |
|---|---|
| `connecting` | `CALLING` (dialing / ringing) |
| `connected` / `reconnecting` | `CONNECTED` |
| `disconnected` / `failed` | `ENDED` |

### Widget Callbacks

```dart
RemoteVoiceCallWidget(
  sdk: sdk,
  callbacks: SDKConnectWidgetCallbacks(
    onCallStateChanged: (phase) { /* SDKConnectWidgetPhase */ },
    onReconnect: () { /* fired once per reconnect entry */ },
    onDisconnected: (reason) { /* network / remote hang-up */ },
    onEnded: (reason) { /* terminal — fires exactly once */ },
  ),
);
```

The same `SDKConnectWidgetCallbacks` applies to `RemoteVideoCallWidget`.

### Signaling Boundary in Screens

Signaling states (`dialing`, `ringing`, `rejected`) are managed at screen level, external to SDKConnect:

```dart
enum _SignalingState { idle, dialing, ringing, rejected }
```

SDKConnect takes over once `startCall` is invoked and media negotiation begins. The screen switches to the SDK widget automatically when `connectionState` reaches `connecting`.

### Navigation Snippet

```dart
Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => VoiceCallScreen(
      sdk: sdk,
      createCallId: generateCallId,
      peerId: SdkConfig.defaultPeerId,
    ),
  ),
);

Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => VideoCallScreen(
      sdk: sdk,
      createCallId: generateCallId,
      peerId: SdkConfig.defaultPeerId,
    ),
  ),
);
```

### How to Run

1. Use runtime values — do not hardcode secrets in source files.
2. Run with `dart-define`:

```bash
flutter run \
  --dart-define=SDK_CONNECT_ROOM_URL=wss://your-livekit-url \
  --dart-define=SDK_CONNECT_ACCESS_TOKEN=your-short-lived-token
```

### Flow: Init -> Call -> End (Media Session)

1. Create SDK facade:

```dart
final sdk = SDKConnect.create(
  localUserId: 'user-a',
  tokenProvider: yourTokenProvider,
  callbacks: SDKConnectCallbacks(
    onEvent: (event) {},
    onUser: (event) {},
    onConnection: (event) {},
    onError: (event) {},
    onToken: (event) {},
  ),
);
```

2. Start outgoing media session:

```dart
await sdk.startCall(callId: 'call-123', peerId: 'peer-b');
```

3. In-call controls:

```dart
await sdk.setMuted(true);
await sdk.setSpeakerOn(true);
await sdk.endCall(reason: 'ended_by_user');
```

## Notes

- Provide signaling/invitation orchestration in your application/backend layer.
- Provide a short-lived backend token provider that returns `SDKConnectCredentials`.
- Validate signaling sender identity and call ownership before calling SDK media APIs.
- Keep tokens backend-issued and short-lived; never persist token strings to logs or analytics.
- Do not bypass SDK abstractions by using LiveKit directly in UI/application code.
- Group call is intentionally rejected by design (P2P only).

## License

MIT
