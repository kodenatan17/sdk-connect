---
name: mbg-memory-system
description: Persistent memory system with project, session, and task layers
argument-hint: "load context or update memory"
---

# 🧠 Memory System (3-Layer Persistent)

You manage memory across three layers:

1. Project Memory (global patterns & architecture)
2. Session Memory (current feature context)
3. Task Memory (iteration & failure tracking)

---

# 📁 Storage (MANDATORY)

- .github/memory/project.memory.json
- .github/memory/session.memory.json
- .github/memory/task.memory.json

---

# 📥 LOAD CONTEXT

Input:

load context for [task] with intent [intent]

---

## 🧠 Behavior

### 1. Read all memory layers

- Read project.memory.json
- Read session.memory.json
- Read task.memory.json (if exists)

---

### 2. Filter relevant keys

Return ONLY relevant keys based on task.

Priority order:
1. ARCH_*
2. SEC_*
3. SIGNALING / SDK patterns
4. FEATURE / domain

---

### 3. Include session context

From session.memory.json:
- feature
- round

---

### 4. Include task context (if exists)

From task.memory.json:
- last_finding
- round

---

## 📤 OUTPUT FORMAT

### MEMORY KEYS
<filtered keys only>

### SESSION INFO
Feature: <feature>
Round: <round>

### TASK INFO (optional)
Last Finding: <finding>
Round: <round>

---

# 📥 RECORD TASK (FAIL LOOP)

Input:

record task:

finding: [issue]
fix_applied: [true/false]
files: [list]

---

## Behavior

- Increment round
- Store ONLY latest finding
- Overwrite previous task memory

---

## Write Target (MANDATORY)

.github/memory/task.memory.json

---

## Example

```json
{
  "last_finding": "Token not validated before startCall",
  "fix_applied": false,
  "files": ["call_engine.dart"],
  "round": 2
}

OUTPUT

TASK MEMORY UPDATED

Round: <n>

📥 UPDATE MEMORY (SUCCESS ONLY)

Input:

update memory:

feature: [name]
agents: [list]
skills: [list]
outcome: success
new_patterns: [optional]

🧠 Behavior
1. Update Session Memory

Write to:

.github/memory/session.memory.json

Example:
{
  "feature": "<feature>",
  "agents": ["joko-builder", "senior-reviewer", "pakpol-security"],
  "skills": ["flutter-architecture-skill"],
  "round": 1
}

2. Clear Task Memory
Delete or reset task.memory.json
3. Update Project Memory (OPTIONAL)

ONLY if:

reusable pattern
affects architecture
used multiple times
🧾 Write Rules (CRITICAL)
MUST write to actual JSON files
MUST merge with existing data
MUST NOT overwrite entire file blindly
🚫 DO NOT
DO NOT log only
DO NOT use external memory tools
DO NOT skip file write
📤 OUTPUT FORMAT

MEMORY UPDATED

Session: ✓
Project: ✓ (if updated)
Task: cleared