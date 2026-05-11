# 🧩 realtime-lifecycle-safety-skill

## 🎯 Purpose

Ensure SDKConnect maintains deterministic, production-grade realtime lifecycle and recovery behavior.

---

## 🧠 Responsibilities

- signaling/media lifecycle separation validation
- reconnect and recovery validation
- lifecycle restoration consistency
- duplicate realtime flow prevention
- state transition validation
- operation serialization
- interruption and app lifecycle recovery

---

## 🔒 Core Rules (MANDATORY)

- signaling lifecycle MUST remain outside SDKConnect
- media lifecycle MUST remain inside CallEngine
- CallEngine MUST remain SSOT
- reconnect/recovery MUST remain deterministic
- session consistency MUST survive reconnect/recovery
- invalid lifecycle transitions MUST be rejected

---

## 📡 Realtime Lifecycle Validation

Validate:

- reconnect safety
- recovery consistency
- interruption recovery
- lifecycle restoration
- duplicate flow prevention
- reconnect race-condition prevention

---

## 🔁 Operation Serialization

Critical operations MUST NOT run concurrently:

- connect
- reconnect
- token refresh
- media recovery
- accept/reject/end

Use:
- mutex
- serialized execution
- operation queue

Goal:
- deterministic flow
- race-condition prevention

---

## 🔄 Recovery Rules

- reconnect MUST restore active media session safely
- reconnect MUST preserve participant/session consistency
- reconnect MUST NOT create parallel sessions
- recovery MUST remain under CallEngine ownership

---

## 📱 App Lifecycle Handling

SDK MUST internally handle:

- foreground/background
- inactive/resumed
- temporary interruption

Behavior:
- preserve active media session
- restore media safely after resume
- avoid unnecessary disconnects

Consumers MUST NOT manage realtime lifecycle manually.

---

## 🔊 Audio Interruption Handling

SDK MUST handle:

- GSM interruption
- alarms
- assistant interruption
- Bluetooth route changes

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
- restore routes after reconnect/interruption

---

## 🚫 Forbidden

- mixed signaling/media lifecycle
- duplicated reconnect orchestration
- reconnect race conditions
- recovery outside CallEngine ownership
- duplicated realtime lifecycle handling
- invalid lifecycle transitions
- concurrent reconnect loops
- direct platform/media handling outside SDK
- exposing platform lifecycle handling to consumers

---

## ✅ Goal

Stable and production-grade realtime lifecycle architecture under unstable network, interruption, reconnect, and user interaction edge cases.