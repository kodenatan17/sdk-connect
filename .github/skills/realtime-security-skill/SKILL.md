# 🔐 Realtime Security Skill

## 🎯 Purpose

Ensure safe call and signaling execution

---

## 🔒 Rules (MANDATORY)

- validate token before:
  - startCall
  - acceptCall
- enforce single active call
- reject incoming if busy

---

## 📡 Signaling Security

- validate session ownership
- prevent cross-session leakage
- reject replay events

---

## 🚫 Forbidden

- exposing token
- trusting client blindly

---

## ✅ Goal

Secure realtime communication