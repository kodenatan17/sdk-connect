# 🚀 Call Engine Skill (Core System)

## 🎯 Purpose

Enforce single CallEngine as the core of all call logic.

---

## 🏗️ Core Rules (MANDATORY)

- MUST use single `CallEngine`
- MUST NOT create VoiceEngine / VideoEngine
- MUST use event-driven or state machine
- caller & callee MUST share same flow

---

## 🧠 Responsibilities

CallEngine MUST handle:

- call lifecycle (start, accept, reject, end)
- state transitions
- single active call enforcement
- timer / timeout
- business rules (balance, etc)

---

## 🔒 SSOT

- Call state MUST live ONLY in CallEngine
- UI / SDK MUST NOT store duplicated state

---

## 🚫 Forbidden

- logic in UI / SDK
- duplicated flow (caller vs callee)
- multiple engines

---

## ✅ Goal

Single source of truth for all call behavior