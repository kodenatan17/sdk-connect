# Voice Call Feature

Dokumen ini menjelaskan flow voice call saat ini untuk Android dan iOS.

## Komponen utama

| Area | File | Peran |
|---|---|---|
| Android native FCM | `PasConnectMessagingService.kt` | Intercept FCM `START`/`END` sebelum Flutter isolate |
| Android native call | `CallManager.kt` | Orkestrasi ringing, accept, decline, timeout |
| Android service | `IncomingCallService.kt` | Foreground service + ringtone + heads-up notification |
| Android bridge | `MainActivity.kt` | MethodChannel native → Flutter, warm-engine delivery |
| Flutter bridge | `native_call_bridge.dart` | Terima accept/decline Android native |
| CallKit | `voip_service.dart`, `AppDelegate.swift` | iOS CallKit event handling |
| Voice state | `voice_call_status_bloc.dart` | Incoming, connecting, connected, reconnecting, ended |
| RTC | `agora_helper.dart` | Join/leave Agora voice channel |

## Payload FCM

```text
data["call"]       = "START" | "END"
data["callId"]     = backend call identifier / Agora channel
data["agoraToken"] = Agora RTC token
data["agoraId"]    = Agora UID
data["callType"]   = "VOICE"
```

## Android flow

### 1. Foreground incoming call

```text
FCM START arrives
  -> PasConnectMessagingService.onMessageReceived()
  -> isAppForegrounded() = true
  -> native CallManager skipped
  -> super.onMessageReceived()
  -> Flutter background/foreground handler
  -> _handleIncomingCall()
  -> navigate to CallScreen
  -> VoiceCallIncomingView shown
```

Behavior:

- Tidak memakai native incoming notification saat app terlihat.
- User lihat Flutter incoming screen langsung.
- Accept dari Flutter UI memicu `InitializeVoiceCallEvent`.

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
  -> InitializeVoiceCallEvent
  -> DoCallActionUsecase(START)
  -> AgoraHelper.startVoiceCall()
  -> VoiceCallConnectingView shown
```

Notes:

- Warm engine dipakai bila tersedia: `getCachedEngineId()`.
- Cold-start race dicegah dengan `pendingNativeCallData` + `dartReady` handshake.
- Payload tetap di `CallPayloadStore` sampai Flutter clear state.

### 4. Android connecting -> call connected

```text
AgoraHelper.startVoiceCall()
  -> joinChannel(callId, token, agoraId)
  -> onUserJoined(remoteUid)
  -> VoiceCallStatusBloc.UserJoinedEvent
  -> state = connected
  -> FlutterCallkitIncoming.setCallConnected(callId)   Android only
  -> VoiceCallActiveView shown
  -> duration timer starts
```

Connected state menyediakan:

- mute
- speaker / audio route
- end call
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
  -> VoiceCallIncomingView shown
```

Behavior:

- User melihat Flutter incoming screen.
- Silent CallKit entry hanya compliance bridge, bukan UI utama.
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
  -> join voice Agora in background if possible
  -> buffer/navigate CallScreen
  -> InitializeVoiceCallFromCallKitEvent
  -> VoiceCallConnectingView shown
```

Important:

- `START` dikirim oleh `VoipService`, bukan BLoC.
- `InitializeVoiceCallFromCallKitEvent` skip duplicate START.
- Timer seeded dari `_backgroundCallAcceptedAt` supaya durasi tidak reset saat UI terbuka.

### 4. iOS connecting -> call connected

Fast path bila Agora sudah joined saat background:

```text
VoipService.backgroundAgoraJoined = true
  -> VoiceCallStatusBloc reattachVoiceCallHandlers()
  -> cached background remoteUid emitted if present
  -> state = connected
  -> VoiceCallActiveView shown
  -> duration seeded from backgroundElapsedSeconds
```

Normal path:

```text
InitializeVoiceCallFromCallKitEvent
  -> AgoraHelper.startVoiceCall()
  -> onUserJoined(remoteUid)
  -> state = connected
  -> VoiceCallActiveView shown
```

Note iOS:

- `FlutterCallkitIncoming.setCallConnected()` tidak dipanggil dari BLoC di iOS karena iOS membutuhkan UUID CallKit asli, bukan backend `callId`.

## Voice call state machine

```text
incoming
  -> connecting      user accept / CallKit accept
  -> ended           decline / timeout / remote cancel

connecting
  -> connected       Agora onUserJoined / background session attached
  -> ended           init failure / token failure

connected
  -> reconnecting    network interrupted / audio frozen / no internet
  -> ended           user ends / remote user offline / token expired

reconnecting
  -> connected       connection restored
  -> ended           20s safety timeout / failed state
```

## Signaling

| Event | Sender | Backend action |
|---|---|---|
| Android Flutter accept | `VoiceCallStatusBloc.InitializeVoiceCallEvent` | `START` |
| iOS CallKit accept | `VoipService._handleCallAccepted()` | `START` |
| User decline | `VoipService.endCallWithReason(userReject)` | `END` |
| Timeout | `IncomingCallService` / CallKit timeout | `END` |
| User ends active call | `VoiceCallControlsBloc` / status BLoC | `END` |
| Remote user leaves | Agora `onUserOffline` / `onUserLeft` | `END` |

Duplicate END guarded by `VoipService._endCallSent`, BLoC `_isEndingCall`, and native ended-call guards.
