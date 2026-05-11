# 🧩 sdkconnect-video-ui-skill

## 🎯 Purpose

Implement video call experience using SDKConnect VideoCall capability.

---

## Rules

* use SDK video components only
* preserve same lifecycle as voice call
* support LocalVideo + RemoteVideo abstraction

---

## Responsibilities

* LocalVideo preview
* RemoteVideo fullscreen
* camera toggle
* PIP support
* orientation handling
* renderer lifecycle safety

---

## Preferred UX

* WhatsApp-like layout
* smooth video transition
* stable resume/reconnect behavior

---

## Forbidden

* direct LiveKit renderer usage
* duplicated camera lifecycle logic
* unmanaged texture/render cleanup

---

## Goal

Production-grade mobile video call experience.
