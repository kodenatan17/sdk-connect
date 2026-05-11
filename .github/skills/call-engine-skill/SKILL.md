# 🧩 call-engine-skill

## 🎯 Purpose

Enforce single CallEngine as the deterministic core of all realtime call behavior.

---

## 🧠 Responsibilities

CallEngine MUST handle:

- RTC/media lifecycle ownership
- call lifecycle orchestration
- state transitions
- reconnect consistency
- single active call enforcement
- timeout/timer handling
- business rule orchestration (if owned by engine)

---

## 🏗️ Core Rules (MANDATORY)

- MUST use single `CallEngine`
- MUST NOT create VoiceEngine / VideoEngine
- MUST use event-driven or FSM architecture
- reconnect MUST preserve session consistency
- lifecycle transitions MUST be deterministic
- caller & callee MUST share same engine flow

---

## 🔒 SSOT

- Call state MUST live ONLY in CallEngine
- lifecycle ownership MUST remain inside CallEngine
- UI / SDK MUST NOT duplicate state
- reconnect/recovery MUST NOT bypass engine ownership

---

## 📡 Lifecycle Ownership

CallEngine MUST own:

- connecting
- connected
- reconnecting
- disconnected
- failed

---

## 🔄 Reconnect Rules

- reconnect MUST reuse active session safely
- duplicate reconnect flow MUST be prevented
- reconnect MUST preserve media/session consistency
- reconnect orchestration MUST remain inside CallEngine

---

## 🚫 Forbidden

- multiple engines
- duplicated lifecycle state
- duplicated caller/callee flow
- uncontrolled reconnect flow
- invalid lifecycle transitions
- logic inside UI/SDK
- reconnect orchestration outside engine

---

## ✅ Goal

Single source of truth for deterministic and production-safe realtime lifecycle management.