# 🏗️ Flutter Architecture Skill (SDK Mode)

## 🎯 Purpose

Enforce SDK-based architecture (NOT full Clean Architecture)

---

## 🏗️ Architecture

SDK / UI  
→ Application  
→ Engine  
→ Infrastructure  

---

## 🔒 Rules

- UI MUST NOT access infrastructure
- Application MUST be thin
- Engine MUST contain core logic
- Infrastructure handles external systems

---

## 🧠 State (SSOT)

- state MUST be in Engine (NOT Bloc)
- UI MUST NOT duplicate state

---

## 🚫 Forbidden

- forcing UseCase layer
- forcing Repository abstraction
- Bloc as core logic
- Clean Architecture overkill

---

## ⚙️ Mode

### SIMPLE

- UI + SDK only

### COMPLEX (DEFAULT)

- use Engine-based architecture

---

## ✅ Goal

Simple, scalable SDK architecture