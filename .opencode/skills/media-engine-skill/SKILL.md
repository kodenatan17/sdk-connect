# 🎥 Media Engine Skill (LiveKit/WebRTC)

## 🎯 Purpose

Abstract media layer using MediaEngine

---

## 🏗️ Rules

- MUST wrap LiveKit inside `MediaEngine`
- MUST NOT use LiveKit directly outside infrastructure

---

## 🧠 Responsibilities

- connect / disconnect
- publish tracks
- toggle audio/video

---

## 🚫 Forbidden

- LiveKit usage in UI / Engine
- mixing media logic with signaling

---

## ✅ Goal

Replaceable media layer (LiveKit → other)