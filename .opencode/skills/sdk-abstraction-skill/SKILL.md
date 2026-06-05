# 🧩 SDK Abstraction Skill

## 🎯 Purpose

Ensure SDK fully abstracts underlying systems (LiveKit, signaling, connection).

---

## 🏗️ Core Rules (MANDATORY)

- SDK MUST handle initialization internally
- SDK MUST NOT require external setup for connection or signaling
- SDK MUST expose simple public API

---

## 🧠 Event System

SDK MUST provide unified callbacks:

- onUserJoined
- onUserLeft
- onConnectionStateChanged
- onConnectionLost
- onNetworkQuality
- onError
- onTokenExpire

All events MUST be unified and exposed from SDK layer

---

## 🔒 Abstraction Rules

- NO direct LiveKit usage outside SDK
- NO signaling usage outside SDK
- UI MUST interact ONLY via SDK

---

## 🔁 Responsibilities

SDK MUST handle:

- connection setup
- reconnection / fallback
- signaling flow
- event mapping (LiveKit → SDK events)

---

## 🚫 Forbidden

- exposing LiveKit objects to UI
- requiring manual init outside SDK
- scattered event handling
- leaking infrastructure layer

---

## ✅ Goal

SDK behaves like a plug-and-play system (similar to Agora)