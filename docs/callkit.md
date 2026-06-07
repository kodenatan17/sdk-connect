# CallKit Integration

Dokumen ini menjelaskan integrasi CallKit untuk Android dan iOS.

## Overview

CallKit adalah layer bridging untuk menyediakan incoming-call UX native yang sesuai standar OS.

| Platform | Library | Function |
|---|---|---|
| Android | `flutter_callkit_incoming` | Heads-up notification + Android call notification API |
| iOS | CallKit native framework + `flutter_callkit_incoming` plugin | Native iOS calling interface + lock-screen UI |

## Android: flutter_callkit_incoming

### Role

`flutter_callkit_incoming` di Android **tidak** dipakai untuk ringing screen utama.

Integrasi native baru:

- `IncomingCallService` (foreground service) menampilkan heads-up notification langsung.
- Notification memakai `CATEGORY_CALL` + `IMPORTANCE_HIGH` untuk lock-screen + heads-up style.
- `CallManager` handle accept/decline/timeout.
- Tidak bergantung pada plugin `activeCalls()` untuk navigation logic.

Flutter side:

- `FlutterCallkitIncoming.setCallConnected(callId)` digunakan di BLoC saat `UserJoined` untuk update Android call notification menjadi "Connected" state, bukan ringing.
- `FlutterCallkitIncoming.endAllCalls()` digunakan saat cleanup untuk memastikan tidak ada ghost notification.

### Limitations Android

- `FlutterCallkitIncoming.showCallkitIncoming()` tidak dipanggil dari native path (app killed/background). Notification native langsung tampil.
- `FlutterCallkitIncoming.activeCalls()` hanya tersisa untuk iOS (lihat section iOS).
- `canUseFullScreenIntent()` / `requestFullIntentPermission()` sekarang iOS-only — di Android permission ini sudah dihandle native manifest + service.

## iOS: CallKit native framework

### Role

iOS CallKit adalah requirement Apple untuk semua VoIP app. Framework ini:

- Menyediakan native lock-screen incoming call UI.
- Integrate dengan sistem phone history.
- Dispatch events saat user accept, decline, atau call ended.

`flutter_callkit_incoming` menjadi wrapper Dart untuk CXProvider / CXCallController native.

### AppDelegate integration

`AppDelegate.swift` menghandle:

| Function | Purpose |
|---|---|
| `didReceiveIncomingPushWith` | Terima VoIP push, report ke CXProvider, end jika ghost call |
| `showCallkitIncoming()` | Call `flutter_callkit_incoming` untuk menampilkan CallKit UI |
| `setupCallKitChannel()` | MethodChannel direct iOS → Dart untuk `incomingCall` + `endCall` event |
| `isGhostCall()` | Deteksi incoming-call FCM yang sudah tidak valid (delay server / race duplicate) |

### Foreground incoming

```text
VoIP push arrives
  -> AppDelegate.didReceiveIncomingPushWith()
  -> UIApplication.state = .active  (foreground)
  -> report silent CXProvider call for Apple policy
  -> direct MethodChannel.invokeMethod("incomingCall", ...) to Dart
  -> VoipService._handleCallIncoming() sees _isAppInForeground = true
  -> end silent CXProvider call immediately
  -> navigate to Flutter incoming screen
```

Silent call purpose:

- Apple policy requires CXProvider entry when receiving VoIP push.
- Dart flow wants custom Flutter UI for foreground.
- Silent call dismissed fast via `FlutterCallkitIncoming.endCall(uuid)`.
- Events dari silent UUID diabaikan oleh `_foregroundSilentCallUuid` guard.

### Background / locked incoming

```text
VoIP push arrives
  -> AppDelegate.didReceiveIncomingPushWith()
  -> UIApplication.state != .active
  -> showCallkitIncoming(fromPushKit=true)
  -> flutter_callkit_incoming.Data + reportNewIncomingCall
  -> native CallKit lock-screen UI rings
```

User melihat:

- Native iOS ringing screen (fullscreen saat locked).
- Contact name "Pas Connect".
- Accept / Decline button (native iOS style).

### Accept flow

```text
User accepts CallKit
  -> CXProvider.performAnswerCallAction
  -> flutter_callkit_incoming plugin fires event
  -> FlutterCallkitIncoming.onEvent stream
  -> VoipService receives actionCallAccept
  -> _handleCallAccepted()
  -> _callAcceptedFromCallKit = true
  -> DoCallActionUsecase(START)
  -> join Agora in background (voice/video)
  -> buffer payload for Flutter UI
  -> when app foreground: navigate CallScreen
```

Important:

- `START` backend signal dikirim dari `VoipService`, bukan BLoC.
- `InitializeVoiceCallFromCallKitEvent` / `InitializeVideoCallFromCallKitEvent` skip duplicate START.
- Background Agora join allows inbound audio to be live before Flutter UI appears.
- Timer seeded dari `_backgroundCallAcceptedAt` supaya durasi match native CallKit timer.

### Decline flow

```text
User declines CallKit
  -> CXProvider.performEndCallAction
  -> flutter_callkit_incoming fires event
  -> VoipService actionCallDecline
  -> _handleCallDeclined()
  -> VoipService.endCallWithReason(userReject)
  -> DoCallActionUsecase(END)
```

### Remote cancel (caller ended before answer)

```text
FCM END arrives
  -> AppDelegate.endCall method (direct channel)
  -> saveEndCall(uuid, reason=remoteEnded)
  -> CXProvider.reportCall(uuid, endedAt:, reason:remoteEnded)
  -> MethodChannel.invokeMethod("endCall", callId)
  -> VoipService direct channel handler
  -> if ringing unanswered: show missed call notification
  -> if answered: endCallWithReason(userReject)
```

### CallKit vs backend callId

iOS CallKit membutuhkan UUID standard (RFC 4122), tapi backend `callId` bukan format UUID.

Flow translation:

1. **VoIP push diterima:** backend `callId` + extra payload.
2. **AppDelegate generate:** RFC 4122 UUID baru.
3. **CXProvider reportNewIncomingCall:** UUID (required).
4. **ExtraData persist:** `{"callId": backend_callId, "agoraToken": ..., ...}` attached to CallKit UUID.
5. **Events:** `actionCallAccept` fires with CallKit UUID.
6. **Dart:** `VoipService` read extra data, extract backend `callId`, pass to BLoC/Agora.

Backend `callId` tidak pernah ditampilkan ke CallKit, hanya UUID auto-generated.

### Ghost-call prevention

Ghost call: late/duplicate VoIP push untuk call yang sudah ended di backend.

Guards:

| Stage | Mechanism |
|---|---|
| AppDelegate incoming | `isGhostCall()` checks CallDenyRegistry + active calls |
| AppDelegate actionCallAccept | Check `hasConnected` or `isAccepted` flag untuk dedup repeat accept |
| VoipService incoming | `_callAcceptedFromCallKit` guard, `_lastForegroundIncomingCallId` guard |

Jika ghost detected:

```text
AppDelegate.isGhostCall() = true
  -> report CXProvider call (policy requirement)
  -> immediately endCall(uuid)
  -> do NOT send to Dart
```

Flutter tidak pernah lihat ghost call.

### iOS-only flutter_callkit_incoming calls

Karena Android pakai native `IncomingCallService` path, beberapa API `flutter_callkit_incoming` sekarang iOS-only:

| Function | Caller | Platform |
|---|---|---|
| `FlutterCallkitIncoming.showCallkitIncoming()` | `NotificationHandleBackground` | iOS only (Android uses native service) |
| `FlutterCallkitIncoming.endAllCalls()` | BLoC error path + end path | iOS-only guard di BLoC, Android skipped |
| `FlutterCallkitIncoming.activeCalls()` | `GoRouter` incoming call redirect | iOS only (Android uses `getPendingIncomingCall`) |

### WeakArray issue workaround

`flutter_callkit_incoming` v3 internal bug:

```text
shareHandlers() stores EventCallbackHandler in WeakArray.
EventCallbackHandler is local var in shareHandlers().
Swift deallocates handler before reportNewIncomingCall completion fires.
actionCallIncoming never reaches Dart regardless of app state.
```

Workaround:

- AppDelegate sends duplicate payload via direct MethodChannel `com.lapasconnect.app/callkit`.
- `VoipService` receives `incomingCall` method, reconstructs same event body, calls `_handleCallIncoming()` directly.
- Plugin event stream tetap listened, tapi MethodChannel direct message menjadi primary delivery.

Channel methods:

| Method | Caller | Purpose |
|---|---|---|
| `incomingCall` | AppDelegate VoIP handler | Deliver incoming payload to Dart when plugin stream drops |
| `endCall` | AppDelegate END push handler | Notify Dart of remote cancel/caller ended |

## Comparison Android vs iOS

| Aspect | Android | iOS |
|---|---|---|
| Incoming notification | `IncomingCallService` foreground service | Native CallKit CXProvider |
| Accept button | `CallActionReceiver` BroadcastReceiver | CallKit performAnswerCallAction |
| Ringtone | MediaPlayer in IncomingCallService | System CallKit ringtone |
| Lock screen | FLAG_SHOW_WHEN_LOCKED + CATEGORY_CALL | CallKit built-in |
| Timeout | IncomingCallService 20s timer | CallKit default timeout (manual if needed) |
| Navigation | `getPendingIncomingCall()` MethodChannel | `activeCalls()` + UUID extraData |
| START signal | Flutter BLoC (regular accept) | VoipService (CallKit accept) |
| Connected update | `setCallConnected()` on Android only | not called (iOS no active CXCall after foreground) |

## CallKit deduplication

| Layer | Mechanism | Scope |
|---|---|---|
| Native Android | `CallManager.activeCallId` + `endedCallIds` | Android only, in-memory |
| iOS AppDelegate | `currentActiveCallKitUuid` + `isGhostCall()` | iOS only, in-memory |
| Flutter | `CallDenyRegistry` JSON TTL | Both platforms, cross-isolate, persistent |
| VoipService | `_currentActiveCallId` + accept guards | Both platforms, in-memory |

All layers independent and complementary.
