# 🧩 sdkconnect-ui-skill

## 🎯 Purpose

Build realtime call UI using SDKConnect lifecycle and callbacks.

---

## Rules

* UI must react to SDK events only
* UI must not own call lifecycle state
* use SDK-provided controller/widgets if available
* preserve P2P call UX

---

## Responsibilities

* incoming call UI
* in-call UI
* mute/speaker/camera controls
* video layout handling
* PIP integration

---

## Preferred Behavior

* WhatsApp-like call UX
* auto fullscreen remote video
* draggable local preview
* auto hide controls during active video

---

## Forbidden

* manual media lifecycle handling
* direct renderer management outside SDK
* duplicated reconnect/loading state

---

## Goal

Consistent production-grade call experience.

---