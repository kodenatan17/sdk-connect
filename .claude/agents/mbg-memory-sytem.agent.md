---
name: mbg-memory-system
description: Persistent memory system with project, session, and task layers
argument-hint: "load context or update memory"
---

# 🧠 Memory System (Lean Persistent Architecture)

Manage memory across:

1. Project Memory → stable architecture/runtime/security invariants
2. Session Memory → active feature context
3. Task Memory → temporary fix/debug loop

---

# 📁 Storage

- .github/memory/project.memory.json
- .github/memory/session.memory.json
- .github/memory/task.memory.json
- .github/memory/memory.index.json

---

# 📥 LOAD CONTEXT

Input:

load context for [task] with intent [intent]

---

## 🧠 Load Strategy

### 1. Load lightweight memory first

Read:
- memory.index.json
- session.memory.json
- task.memory.json (optional)

DO NOT load full project memory initially.

---

### 2. Retrieve relevant keys only

Load full entries ONLY if related to:
- architecture
- signaling
- RTC/media
- security
- lifecycle/recovery
- active feature scope

Priority:
1. ARCH_*
2. SEC_*
3. RTC_*
4. RULE_*

---

### 3. Include active context

Session:
- feature
- round

Task:
- last_finding
- round

---

## 📤 OUTPUT

### MEMORY_KEYS
<filtered keys only>

### SESSION_INFO
Feature: <feature>
Round: <round>

### TASK_INFO
Last Finding: <finding>
Round: <round>

---

# 📥 RECORD TASK

Input:

record task:

finding: [issue]
fix_applied: [true/false]
files: [list]

---

## Behavior

- increment round
- overwrite previous task memory
- keep latest finding only

---

## Write Target

.github/memory/task.memory.json

---

# 📥 UPDATE MEMORY

Input:

update memory:

feature: [name]
agents: [list]
skills: [list]
outcome: success
new_patterns: [optional]

---

## Behavior

### 1. Update Session Memory

Write:
- feature
- agents
- skills
- round

---

### 2. Clear Task Memory

Reset/remove:
- task.memory.json

---

### 3. Update Project Memory (Selective)

Persist ONLY if:
- reusable across features
- affects architecture/runtime/security
- changes orchestration/review behavior
- required for future consistency

DO NOT persist:
- minor refactor
- styling/UI tweaks
- one-off fixes
- temporary workaround
- implementation detail
- example-only changes

---

## Write Rules

- MUST merge existing memory
- MUST NOT overwrite unrelated entries
- MUST keep project memory normalized/minimal
- MUST avoid duplicate invariants

---

## 🚫 Forbidden

- DO NOT load entire project memory blindly
- DO NOT treat memory as commit history
- DO NOT persist every implementation change
- DO NOT skip actual file write

---

## 📤 OUTPUT

MEMORY UPDATED

Session: ✓
Project: ✓ (if updated)
Task: cleared