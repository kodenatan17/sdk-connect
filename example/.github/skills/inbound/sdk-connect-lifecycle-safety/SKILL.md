# 🧩 call-lifecycle-safety-skill

## 🎯 Purpose

Protect SDKConnect from realtime lifecycle instability and race conditions.

---

## Responsibilities

- reconnect safety
- operation serialization
- interruption recovery
- app lifecycle recovery
- audio route recovery

---

## Rules

- validate CallEngine transitions
- prevent repeated lifecycle operations
- serialize critical operations:
  - reconnect
  - token refresh
  - media recovery
  - accept/reject/end
- preserve session consistency during interruption/recovery

---

## App Lifecycle

SDK MUST internally handle:
- foreground/background
- interruption
- resume/recovery
- audio focus

Consumers MUST NOT manage realtime lifecycle manually.

---

## Audio Route Support

- speaker
- earpiece
- wired headset
- Bluetooth

---

## Forbidden

- concurrent reconnect loops
- invalid CallEngine transitions
- duplicated async lifecycle operations
- exposing platform lifecycle handling to consumers

---

## Goal

Production-grade realtime lifecycle resilience.