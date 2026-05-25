# 📡 Realtime Signaling Skill (MQTT/WebRTC)

## 🎯 Purpose

Handle signaling flow safely and consistently.

---

## 🏗️ Rules

- MUST use `SignalingService`
- MUST NOT access MQTT directly from UI or Engine
- ALL events must be validated

---

## 🔁 Flow

Offer → Answer → ICE → Connected

---

## 🔒 Validation (MANDATORY)

- validate sessionId
- validate sender identity
- reject invalid events

---

## 🚫 Forbidden

- blind trust client events
- direct MQTT usage outside infrastructure

---

## ✅ Goal

Safe and deterministic signaling flow