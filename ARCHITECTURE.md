# SDKConnect Architecture

> Version 0.0.3 · Flutter P2P call SDK (voice + video) · LiveKit-backed

---

## Layer Overview

```
┌─────────────────────────────────────────────────────────┐
│  Public SDK  (lib/sdk/)          ← consumer boundary    │
│  SDKConnect · SDKConnectVoiceApi · SDKConnectVideoApi   │
├─────────────────────────────────────────────────────────┤
│  Presentation  (lib/presentation/)                       │
│  Widgets: RemoteVoiceCallWidget · RemoteVideoCallWidget  │
├─────────────────────────────────────────────────────────┤
│  Engine  (lib/engine/)           ← SSOT                 │
│  CallEngine                                             │
├─────────────────────────────────────────────────────────┤
│  Core  (lib/core/)                                      │
│  CallState · CallSession · CallPhase · enums · errors   │
├─────────────────────────────────────────────────────────┤
│  Infrastructure  (lib/infrastructure/)                   │
│  MediaEngine (abstract) · LiveKitMediaEngine (concrete) │
└─────────────────────────────────────────────────────────┘
              ↕ wired by
┌─────────────────────────────────────────────────────────┐
│  DI  (lib/di/)                                          │
│  SdkConnectScope                                        │
└─────────────────────────────────────────────────────────┘
```

---

## Layer Responsibilities

### `core/`
- **Owns**: enums (`CallPhase`, `CallType`, `CallDirection`), immutable models (`CallState`, `CallSession`), `CallLifecycleException`, `StructuredLogger`.
- **Rule**: No dependencies on any other SDK layer. Pure Dart.

### `infrastructure/`
- **Owns**: `MediaEngine` abstract interface and `LiveKitMediaEngine` concrete implementation.
- **Rule**: The only layer that imports `livekit_client`. LiveKit must never be exposed above this layer.
- Emits typed `MediaEngineEvent` objects translated from LiveKit room events.
- Enforces P2P constraint: disconnects on `>1` remote participant (`P2PLimitExceededException`).

### `engine/`
- **Owns**: `CallEngine` — the single source of truth (SSOT) for all call state.
- All state mutations (connect, disconnect, mute, speaker, video, ICE recovery, token refresh, lifecycle) run through a single serialized `_operationQueue`.
- Drives the `CallPhase` state machine; guards invalid transitions.
- Translates `MediaEngineEvent` → `CallEngineEvent` → public event bus.
- Manages exponential reconnect backoff, network quality adaptation, app lifecycle observation.

### `di/`
- **Owns**: `SdkConnectScope` — wires `MediaEngine` + `CallEngine`.
- Factory: `SdkConnectScope.liveKit(...)` is the canonical creation path.
- Exposes `createVoiceCallSdk(...)` and `createVoiceCallController()` for consumers that manage their own DI.

### `presentation/`
- **Owns**: observer-only widgets (`RemoteVoiceCallWidget`, `RemoteVideoCallWidget`, `VoiceCallScreen`, `VideoCallLayout`).
- **Rule**: No lifecycle authority. Widgets subscribe to `sdk.runtimeStates` and render; they never mutate call state.
- `VoiceCallController` (ChangeNotifier) maps `CallState` → `VoiceCallUiState` for `VoiceCallScreen`.

### `sdk/` (Public SDK)
- **Owns**: `SDKConnect`, `VoiceCallSdk`, `VideoCallSdk`, `sdk_connect_api.dart` types.
- `SDKConnect` is the **sole documented consumer entry point**. `VoiceCallSdk` / `VideoCallSdk` are internal.
- Translates internal engine events to the public event hierarchy (`SDKConnectEvent` subtypes).
- Sanitizes JWT from error messages before surfacing to consumers.
- `VideoCallSdk` composes `VoiceCallSdk`; it does not extend it.

---

## Signaling vs RTC/Media Ownership

| Concern | Owner | Notes |
|---|---|---|
| Signaling transport (MQTT / WebSocket / push) | **Consumer / backend** | SDK has no signaling layer. `infrastructure/signaling/` is intentionally empty. |
| Signal validation | `VoiceCallSdk._handleSignal` | Validates envelope before forwarding to `CallEngine`. Invalid signals emit `SDKConnectErrorEvent` — never silently dropped. |
| RTC / media session | `MediaEngine` → `LiveKitMediaEngine` | Owns WebRTC, ICE, audio/video tracks, room events. |
| ICE recovery | `CallEngine` orchestrates, `MediaEngine` executes | `restartIce()` called inside reconnect loop. |
| Token refresh | `CallEngine` triggers, consumer-supplied `CallTokenRefresher` executes | Deduplicates in-flight refresh requests. Validates JWT expiry before connect. |

---

## CallEngine — SSOT Rules

1. **All state mutations are serialized.** No facade layer may call two engine methods concurrently.
2. **Phase guard before side effects.** Any invalid transition (e.g. `connecting → connecting`) throws `CallLifecycleException` before touching media.
3. **Consumers observe, never mutate.** `SDKConnect` / widgets read `CallState` via `Stream<CallState>`; they do not write it.
4. **One active session.** A second `connectSession` call while not idle is rejected.

---

## Public Entrypoints

### Bootstrap (SDK owns engine)
```dart
final sdk = SDKConnect.create(
  tokenProvider: (req) async => SDKConnectCredentials(
    roomUrl: ...,
    token: ...,
  ),
);
await sdk.initialize(localUserId: 'alice');
```

### Bootstrap (consumer owns engine — advanced)
```dart
final scope = SdkConnectScope.liveKit();
final sdk = SDKConnect(
  callEngine: scope.callEngine,
  tokenProvider: ...,
);
```

### Start a call
```dart
await sdk.startCall('bob', callType: SDKConnectCallType.voice);
// or video:
await sdk.video.startCall('bob');
```

### Accept / reject (signaling drives this)
```dart
await sdk.startCall(peerId, callId: incomingCallId,
    callType: SDKConnectCallType.voice); // accept
// reject is consumer-side only — no SDK method needed
```

### Media controls
```dart
await sdk.setMuted(true);
await sdk.setSpeakerOn(true);
await sdk.video.setCameraEnabled(false);
```

### Widget integration
```dart
RemoteVoiceCallWidget(
  sdk: sdk,
  callbacks: SDKConnectWidgetCallbacks(
    onCallStateChanged: (phase) { ... },
    onEnded: (reason) { Navigator.pop(context); },
  ),
)
```

---

## Lifecycle / Data Flow

```
Consumer calls sdk.startCall()
  │
  ▼
VoiceCallSdk.startCall()
  │  ① generates callId (crypto-random)
  │  ② invokes tokenProvider(request) → credentials
  │  ③ emits SDKConnectTokenEvent.requested / resolved
  │
  ▼
CallEngine.connectSession(callId, peerId, roomUrl, token, ...)
  │  ④ validates JWT expiry
  │  ⑤ transitions idle → connecting (CallState emitted)
  │  ⑥ calls MediaEngine.connect(roomUrl, token)
  │
  ▼
LiveKitMediaEngine  (infrastructure boundary)
  │  ⑦ joins LiveKit room, sets up room listeners
  │  ⑧ emits MediaEngineEvent.participantJoined / connected
  │
  ▼
CallEngine (event handler)
  │  ⑨ transitions connecting → connected
  │  ⑩ emits CallEngineEvent.lifecycleChanged
  │
  ▼
VoiceCallSdk (event listener)
  │  ⑪ maps to SDKConnectConnectionEvent.connected
  │
  ▼
SDKConnect (bridge)
  │  ⑫ updates SDKConnectRuntimeState
  │  ⑬ broadcasts via runtimeStates stream
  │
  ▼
RemoteVoiceCallWidget / consumer callbacks
     ⑭ re-renders UI, fires onCallStateChanged(connected)
```

### Reconnect branch (steps ⑦–⑭ vary)
```
MediaEngineEvent.disconnected
  → CallEngine: connected → reconnecting
  → exponential backoff loop
  → token refresh if near expiry
  → MediaEngine.connect(newToken)
  → on success: reconnecting → connected (SDKConnectConnectionEvent.recovered)
  → on max attempts exceeded: → failed
```

---

## Tracing & Debug Flow

| Signal | Where to look |
|---|---|
| Call started / token requested | `SDKConnectTokenEvent.requested` via `onToken` callback |
| Phase changes | `SDKConnectConnectionEvent` via `onConnection` callback or `sdk.states` stream |
| Engine-level state | `CallEngine` emits `CallEngineEvent` with `callId`, `reason`, `reconnectAttempt` |
| Media events | `MediaEngineEvent` logged inside `LiveKitMediaEngine` via injected `StructuredLogger` |
| P2P violation | `P2PLimitExceededException` → `SDKConnectUserEvent.p2pLimitExceeded` |
| Token refresh | `SDKConnectTokenEvent.refreshRequested` / `refreshed` / `refreshFailed` |
| ICE recovery | `SDKConnectConnectionEvent.iceRecoveryStarted` / `iceRecovered` |
| Network degradation | `SDKConnectConnectionEvent.networkDegraded` / `networkRecovered` |
| Structured logging | Inject custom `StructuredLogger` into `SDKConnect.create(logger: ...)` |

### Enabling verbose logging
```dart
SDKConnect.create(
  logger: ConsoleStructuredLogger(), // built-in
  // or implement StructuredLogger for remote/structured output
  ...
)
```

---

## Architecture Rules (non-negotiable)

| Rule | Enforcement |
|---|---|
| No LiveKit import outside `infrastructure/` | `analysis_options.yaml` / code review |
| `CallEngine` is the only mutable state authority | No direct `CallState` writes outside engine |
| Signaling is consumer responsibility | `infrastructure/signaling/` empty by design |
| P2P only — max 2 participants | `LiveKitMediaEngine` disconnects on violation |
| No partial commits — all tests must pass | CI gate |
| `SDKConnect.create` is the documented public API | `VoiceCallSdk` / `SdkConnectScope` are internal |

---

## Key Types Reference

| Type | Layer | Purpose |
|---|---|---|
| `SDKConnect` | `sdk/` | Consumer entry point |
| `SDKConnectRuntimeState` | `sdk/` | Aggregated observable snapshot |
| `SDKConnectEvent` (+ subtypes) | `sdk/` | Typed event bus |
| `VoiceCallSdk` | `sdk/` | Internal voice session manager |
| `VideoCallSdk` | `sdk/` | Internal video wrapper (composes VoiceCallSdk) |
| `CallEngine` | `engine/` | SSOT state machine + orchestrator |
| `CallState` | `core/` | Immutable state snapshot |
| `CallSession` | `core/` | Session identity (callId, peerId, type, direction) |
| `MediaEngine` | `infrastructure/` | Abstract RTC interface |
| `LiveKitMediaEngine` | `infrastructure/` | LiveKit-backed implementation |
| `SdkConnectScope` | `di/` | DI wiring |
| `RemoteVoiceCallWidget` | `presentation/` | Plug-and-play voice UI observer |
| `RemoteVideoCallWidget` | `presentation/` | Plug-and-play video UI observer |
