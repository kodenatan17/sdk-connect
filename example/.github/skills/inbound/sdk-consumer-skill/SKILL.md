# 🧩 sdkconnect-consumer-skill

## 🎯 Purpose

Ensure Flutter app integrates SDKConnect safely without bypassing SDK abstractions.

---

## Rules

- SDKConnect MUST be the only communication entry point
- UI MUST consume SDK state/events only
- NEVER access LiveKit directly
- NEVER access signaling directly
- NEVER duplicate lifecycle handling outside SDK

---

## Responsibilities

- initialize SDKConnect
- bind SDK state into UI
- listen to SDK callbacks/events
- consume voice/video capability
- preserve SDK lifecycle consistency

---

## Preferred Flow

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

- direct LiveKit usage
- direct MQTT/WebSocket usage
- custom reconnect logic outside SDK
- duplicated call state outside SDK

---

## Goal

Simple plug-and-play SDK integration.