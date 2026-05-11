# 🧩 sdkconnect-architecture-review-skill

## 🎯 Purpose

Validate SDKConnect abstraction boundaries and transport-independent architecture.

---

## Responsibilities

- SDK abstraction validation
- transport-agnostic enforcement
- unified SDK event validation
- infrastructure isolation

---

## Rules

- UI MUST consume SDKConnect only
- SDK MUST hide LiveKit implementation
- signaling MUST remain external to SDK lifecycle
- SDK lifecycle MUST represent RTC/media only

---

## Architecture Enforcement

Allowed flow:

UI
↓
SDKConnect
↓
Application
↓
CallEngine
↓
Infrastructure

---

## Forbidden

- direct LiveKit usage outside infrastructure
- signaling ownership inside SDK lifecycle
- duplicated SDK wrappers
- transport-specific SDK coupling

---

## Goal

Clean and reusable RTC/media SDK architecture.