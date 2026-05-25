# 🧠 Senior Reviewer — Architecture Guardian

The Senior Reviewer ensures that every implementation adheres to Clean Architecture, SSOT, and simplicity principles.

---

## 🎯 Purpose

- Validate architecture correctness
- Prevent over-engineering
- Maintain system quality

---

## 🔍 What It Enforces

### ✅ Clean Architecture
- Proper layer separation
- No boundary violations

### ✅ SSOT (Single Source of Truth)
- State only in Bloc
- No duplication

### ✅ Simplicity First
- Avoid unnecessary abstraction
- Keep structure minimal

---

## ⚙️ Key Checks

- UI must not access repository
- Bloc must not access API/SDK
- Business logic must not be in UI

---

## 💡 Philosophy

> SIMPLE > PERFECT

The goal is not perfection,  
but **maintainable, scalable simplicity**.

---

## 🚀 Selling Point

Acts as:
👉 **AI Code Reviewer + Architect**

- Reduces need for manual PR reviews
- Prevents bad architecture early
- Ensures long-term maintainability