# 🔄 Call Lifecycle Safety Skill

## 🎯 Purpose

Ensure SDKConnect maintains safe, deterministic, and production-grade realtime lifecycle behavior.

---

## 🧠 Core Responsibilities

- validate CallEngine state transitions
- prevent invalid lifecycle operations
- serialize critical async operations
- handle reconnect and recovery safely
- preserve media/session consistency
- handle platform lifecycle interruptions

---

## 🔒 State Safety Rules (MANDATORY)

- CallEngine is the single source of truth (SSOT)
- invalid state transitions MUST be rejected
- repeated operations MUST be debounced
- ended sessions MUST reject further actions

Examples:
- reject acceptCall() after connected
- reject toggleMute() after ended
- reject duplicated reconnect attempts

---

## 🔁 Operation Serialization

Critical operations MUST NOT run concurrently:

- connect
- reconnect
- token refresh
- accept/reject/end
- media recovery

Use:
- operation queue
- mutex
- serialized execution

Goal:
- prevent race conditions
- preserve deterministic flow

---

## 📱 App Lifecycle Handling

SDK MUST internally handle:

- foreground/background
- inactive/resumed
- temporary interruption

Behavior:
- preserve active call session
- restore media safely after resume
- avoid unnecessary disconnects

Consumers MUST NOT manage realtime lifecycle manually.

---

## 🔊 Audio Interruption Handling

SDK MUST handle:

- GSM calls
- alarms
- Siri/assistant interruption
- Bluetooth changes

Behavior:
- pause/resume media safely
- restore audio session automatically
- preserve CallEngine consistency

---

## 🎧 Audio Route Management

SDK MUST support:

- speaker
- earpiece
- wired headset
- Bluetooth audio

Behavior:
- detect route changes automatically
- preserve user-selected route
- recover routes after reconnect/interruption

---

## 🚫 Forbidden

- concurrent reconnect loops
- invalid lifecycle transitions
- exposing platform lifecycle handling to consumers
- direct platform/media handling outside SDK

---

## ✅ Goal

SDKConnect behaves as a stable production-grade realtime communication SDK under unstable network, lifecycle interruption, and user interaction edge cases.