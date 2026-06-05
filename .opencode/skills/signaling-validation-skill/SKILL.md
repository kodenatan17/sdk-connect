# 🧩 signaling-validation-skill

## 🎯 Purpose

Protect signaling integrity and prevent unauthorized realtime events.

---

## Responsibilities

- sender validation
- session ownership validation
- stale event rejection
- replay protection

---

## Rules

- validate sender identity before processing
- validate call/session ownership
- reject stale or duplicated signaling events
- reject malformed signaling payloads

---

## Replay Protection

- signaling events MUST include:
  - unique sessionId
  - unique eventId
  - timestamp/version

- duplicate events MUST be ignored safely

---

## Session Integrity

- signaling MUST belong to active session
- session ownership MUST remain consistent during reconnect

---

## Forbidden

- blind trust to incoming events
- processing unknown session events
- accepting duplicated signaling

---

## Goal

Deterministic and secure signaling lifecycle.