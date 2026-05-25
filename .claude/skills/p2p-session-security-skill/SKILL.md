# 🧩 p2p-session-security-skill

## 🎯 Purpose

Protect P2P session integrity and single-call consistency.

---

## Responsibilities

- single active call enforcement
- P2P participant validation
- duplicate participant rejection
- busy-state protection

---

## Rules

- maximum 2 participants per session
- reject additional participants immediately
- reject incoming call when already busy
- preserve single active CallEngine session

---

## Session Safety

- reconnect MUST preserve same session ownership
- duplicate session attachment MUST be rejected
- stale participant MUST be removed safely

---

## Forbidden

- multiple active calls
- group-call behavior
- duplicated participant attachment
- parallel CallEngine sessions

---

## Goal

Stable and secure P2P realtime communication.