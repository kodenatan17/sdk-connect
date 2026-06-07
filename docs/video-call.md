# Video Call Feature

Dokumen ini menjelaskan flow video call saat ini untuk Android dan iOS.

## Komponen utama

| Area | File | Peran |
|---|---|---|
| Android native FCM | `PasConnectMessagingService.kt` | Intercept FCM `START`/`END` sebelum Flutter isolate |
| Android native call | `CallManager.kt` | Orkestrasi ringing, accept, decline, timeout |
| Android service | `IncomingCallService.kt` | Foreground service + ringtone + heads-up notification |
| Android bridge | `MainActivity.kt` | MethodChannel native → Flutter, warm-engine delivery |
| Flutter bridge | `native_call_bridge.dart` | Terima accept/decline Android native |
| CallKit | `voip_service.dart`, `AppDelegate.swift` | iOS CallKit event handling |
| Video state | `video_call_status_bloc.dart` | Incoming, connecting, connected, reconnecting, ended |
| RTC | `agora_helper.dart` | Join/leave Agora video channel |
| UI | `video_call_active_view.dart` | Remote/local video, controls, PiP |

## Payload FCM

```text
data["call"]       = "START" | "END"
data["callId"]     = backend call identifier / Agora channel
data["agoraToken"] = Agora RTC token
data["agoraId"]    = Agora UID
data["callType"]   = "VIDEO"
```

## Android flow

### 1. Foreground incoming call

```text
FCM START arrives
  -> PasConnectMessagingService.onMessageReceived()
  -> isAppForegrounded() = true
  -> native CallManager skipped
  -> super.onMessageReceived()
  -> Flutter handler
  -> _handleIncomingCall()
  -> navigate to CallScreen
  -> VideoIncomingView shown
```

Behavior:

- Tidak memakai native incoming notification saat app terlihat.
- User melihat Flutter video incoming screen langsung.
- Accept dari Flutter UI memicu `InitializeVideoCallEvent`.

### 2. Background / killed incoming call

```text
FCM START arrives
  -> PasConnectMessagingService.onMessageReceived()
  -> isIncomingCallMessage() valid
  -> isAppForegrounded() = false
  -> PasConnectApplication.warmFlutterEngine()
  -> CallManager.handleIncomingCall()
  -> CallPayloadStore.save()
  -> IncomingCallService.start()
  -> heads-up / lock-screen native notification rings
```

Native notification menyediakan:

- Accept button
- Decline button
- ringtone
- 20s timeout auto-decline

### 3. Android accept: incoming -> connecting

```text
User taps Accept
  -> CallActionReceiver
  -> CallManager.acceptCall(callId, directAccept=true)
  -> IncomingCallService.stop()
  -> MainActivity launched with ACTION_ACCEPT
  -> MainActivity loads CallPayloadStore
  -> onCallAcceptedFromNative(payload)
  -> NativeCallBridge._handleAccept()
  -> navigate to CallScreen
  -> InitializeVideoCallEvent
  -> DoCallActionUsecase(START)
  -> AgoraHelper.startVideoCall()
  -> VideoConnectingView shown
```

Notes:

- Warm engine dipakai bila tersedia: `getCachedEngineId()`.
- Cold-start race dicegah dengan `pendingNativeCallData` + `dartReady` handshake.
- `directAccept=true` bisa membuat Flutter langsung connect tanpa memaksa user swipe lagi, sesuai route logic native bridge.

### 4. Android connecting -> call connected

```text
AgoraHelper.startVideoCall()
  -> joinChannel(callId, token, agoraId)
  -> onUserJoined(remoteUid)
  -> VideoCallStatusBloc.VideoUserJoinedEvent
  -> state = connected
  -> FlutterCallkitIncoming.setCallConnected(callId)   Android only
  -> VideoCallActiveView shown
  -> duration timer starts
```

Connected state menyediakan:

- local camera preview
- remote video stream
- camera toggle
- mute
- PiP
- end call
- remote mute/camera state
- connection-quality messages

### 5. Android decline / timeout / remote cancel

```text
Decline or timeout
  -> CallManager.declineCall()
  -> IncomingCallService.stop()
  -> onCallDeclinedFromNative(callId) if engine ready
  -> VoipService.endCallWithReason(userReject/timeout)
  -> DoCallActionUsecase(END)
  -> AgoraHelper.endCall()
```

Remote cancel:

```text
FCM END arrives
  -> PasConnectMessagingService.isEndCallMessage()
  -> CallManager.cancelCallFromRemote()
  -> native ringing UI dismissed
  -> super.onMessageReceived()
  -> Flutter cleanup handles END
```

## iOS flow

### 1. Foreground incoming call

```text
VoIP/FCM incoming payload
  -> AppDelegate reports silent CXProvider call for Apple policy
  -> direct MethodChannel incomingCall to Dart
  -> VoipService._handleCallIncoming()
  -> _isAppInForeground = true
  -> end silent CallKit UI immediately
  -> navigate to CallScreen
  -> VideoIncomingView shown
```

Behavior:

- User melihat Flutter video incoming screen.
- Silent CallKit entry hanya compliance bridge.
- Event dari silent UUID diabaikan oleh `_foregroundSilentCallUuid` guard.

### 2. Background / locked incoming call

```text
VoIP push arrives
  -> AppDelegate.showCallkitIncoming(fromPushKit=true)
  -> native iOS CallKit UI rings
  -> VoipService receives/directly reconstructs incomingCall payload
  -> _isAppInForeground = false
  -> native CallKit owns ringing UI
```

### 3. iOS CallKit accept: incoming -> connecting

```text
User accepts CallKit
  -> FlutterCallkitIncoming actionCallAccept
  -> VoipService._handleCallAccepted()
  -> _callAcceptedFromCallKit = true
  -> DoCallActionUsecase(START)
  -> join Agora video in background as audio-only if possible
  -> buffer/navigate CallScreen
  -> InitializeVideoCallFromCallKitEvent
  -> VideoConnectingView shown
```

Important:

- `START` dikirim oleh `VoipService`, bukan BLoC.
- `InitializeVideoCallFromCallKitEvent` skip duplicate START.
- Background video join memakai audio-only mode: camera disabled sampai app foreground/unlocked.

### 4. iOS connecting -> call connected

Fast path bila Agora video session sudah joined saat background:

```text
VoipService.backgroundVideoAgoraJoined = true
  -> VideoCallStatusBloc reattachVideoCallHandlers()
  -> AgoraHelper.enableLocalCameraAfterBackground()
  -> cached background remoteUid emitted if present
  -> state = connected
  -> VideoCallActiveView shown
  -> duration seeded from backgroundElapsedSeconds
```

Normal path:

```text
InitializeVideoCallFromCallKitEvent
  -> AgoraHelper.startVideoCall()
  -> onUserJoined(remoteUid)
  -> state = connected
  -> VideoCallActiveView shown
```

Note iOS:

- Camera baru diaktifkan setelah app foreground/unlocked untuk menghindari background camera usage.
- `FlutterCallkitIncoming.setCallConnected()` tidak dipanggil dari BLoC di iOS karena iOS membutuhkan UUID CallKit asli, bukan backend `callId`.

## Video call state machine

```text
incoming
  -> connecting      user accept / CallKit accept
  -> ended           decline / timeout / remote cancel

connecting
  -> connected       Agora onUserJoined / background session attached
  -> ended           init failure / token failure

connected
  -> reconnecting    network interrupted / no internet
  -> ended           user ends / remote user offline / token expired

reconnecting
  -> connected       connection restored
  -> ended           20s safety timeout / failed state
```

## Signaling

| Event | Sender | Backend action |
|---|---|---|
| Android Flutter accept | `VideoCallStatusBloc.InitializeVideoCallEvent` | `START` |
| iOS CallKit accept | `VoipService._handleCallAccepted()` | `START` |
| User decline | `VoipService.endCallWithReason(userReject)` | `END` |
| Timeout | `IncomingCallService` / CallKit timeout | `END` |
| User ends active call | `VideoCallControlsBloc` / status BLoC | `END` |
| Remote user leaves | Agora `onUserOffline` / `onUserLeft` | `END` |

Duplicate END guarded by `VoipService._endCallSent`, BLoC `_isEndingCall`, and native ended-call guards.
