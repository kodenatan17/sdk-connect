# 🧩 sdkconnect-event-handling-skill

## 🎯 Purpose

Handle SDKConnect realtime events safely and consistently.

---

## Rules

* use unified SDK events/callbacks
* avoid scattered realtime listeners
* preserve deterministic UI state

---

## Responsibilities

Handle:

* connection events
* reconnect events
* token events
* interruption events
* route/device events
* P2P enforcement events

---

## Preferred Usage

```dart
sdk.events.listen((event) {
  // handle SDK lifecycle
});
```

---

## Forbidden

* duplicated listeners
* direct infrastructure event subscriptions
* unmanaged stream subscriptions

---

## Goal

Reliable realtime UI synchronization.

---