# 🧩 memory-governance-skill

## 🎯 Purpose

Keep memory normalized, reusable, and architecture-focused.

---

## Responsibilities

- selective persistence
- invariant-only persistence
- anti-commit-history memory
- memory normalization

---

## Persist ONLY

- reusable architecture invariant
- reusable runtime invariant
- reusable lifecycle/security invariant
- cross-feature orchestration rule

---

## DO NOT Persist

- implementation detail
- widget/UI tweak
- temporary workaround
- one-off fix
- example-only change
- README-only update
- code-level micro behavior

---

## Memory Rules

- project memory = architecture brain
- session memory = active feature context
- task memory = temporary debug/fix loop

---

## Retrieval Rules

- load minimal relevant memory only
- avoid full project-memory retrieval
- prioritize:
  - ARCH_*
  - SEC_*
  - RTC_*
  - RULE_*

---

## Normalization Rules

- merge existing memory safely
- avoid duplicated invariants
- keep memory concise/minimal
- avoid stale implementation-derived memory

---

## Forbidden

- treating memory as commit history
- persisting every implementation change
- architecture duplication
- broad memory dumping

---

## Goal

Lean, reusable, and scalable persistent memory architecture.