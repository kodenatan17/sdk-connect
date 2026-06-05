# 🧩 realtime-token-security-skill

## 🎯 Purpose

Protect RTC/media session authentication and token lifecycle.

---

## Responsibilities

- token validation
- token refresh safety
- token expiration handling
- token confidentiality enforcement

---

## Rules

- validate token before privileged actions
- refresh token before expiration
- prevent concurrent refresh operations
- use short-lived backend-issued tokens only

---

## Security Enforcement

- NEVER expose token in:
  - logs
  - analytics
  - UI state
  - exceptions

- NEVER hardcode token
- NEVER trust client-provided token blindly

---

## Reconnect Rules

- reconnect MUST revalidate token/session
- failed refresh MUST safely terminate session
- token refresh MUST preserve CallEngine consistency

---

## Forbidden

- token persistence in local logs
- duplicated refresh requests
- insecure token reuse

---

## Goal

Secure and reliable RTC authentication lifecycle.