# 🧩 sdkconnect-integration-skill

## 🎯 Purpose

Integrate SDKConnect safely into Flutter apps without bypassing SDK abstractions.

---

## Rules

* use SDKConnect as the only communication entry point
* NEVER access LiveKit directly
* NEVER access signaling directly from UI
* use SDK callbacks/events for lifecycle handling
* keep app integration lightweight

---

## Responsibilities

* initialize SDKConnect
* start/end calls
* listen to SDK events
* bind SDK state into UI
* dispose SDK safely

---

## Preferred Usage

```dart
final sdk = SDKConnect.create(...);

await sdk.startCall(peerId: 'user-b');
```

---

## Forbidden

* direct RTC handling
* direct MQTT/WebSocket usage
* custom reconnect logic outside SDK
* duplicate call lifecycle state

---

## Goal

Simple plug-and-play integration experience.