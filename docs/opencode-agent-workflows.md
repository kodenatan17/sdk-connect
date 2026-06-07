# OpenCode Agent Workflows

This document contains sequence diagrams and flowcharts explaining the OpenCode multi-agent orchestration system, command workflows, and agent routing used in this project.

## Table of Contents

- [Overall Orchestrator Flow](#overall-orchestrator-flow)
- [Command Workflow Router](#command-workflow-router)
- [Available Command Workflows](#available-command-workflows)
- [Skill Routing Sequence](#skill-routing-sequence)
- [Gate Handling Flow](#gate-handling-flow)
- [Agent Categories](#agent-categories)
- [Presentation Notes](#presentation-notes)

---

## Overall Orchestrator Flow

This diagram shows the high-level flow from user command to final output, including skill routing and gate handling.

```mermaid
sequenceDiagram
    autonumber

    actor Developer

    participant OpenCode
    participant Orchestrator
    participant SkillRouter
    participant Finder

    box Agent Layer
    participant WorkerAgents
    participant Reviewer
    participant Tester
    participant Security
    end

    Developer->>OpenCode: /feature /bugfix /refactor /review ...

    OpenCode->>Orchestrator: Request + repo context

    Orchestrator->>Orchestrator: Detect command
    Orchestrator->>Orchestrator: Select workflow

    Orchestrator->>SkillRouter: Resolve required skills
    SkillRouter-->>Orchestrator: Skill set

    Orchestrator->>Finder: Discover codebase context
    Finder-->>Orchestrator: Files, symbols, patterns

    Orchestrator->>WorkerAgents: Execute workflow
    WorkerAgents-->>Orchestrator: Results

    alt Code Modification Workflow
        Orchestrator->>Reviewer: Review changes
        Reviewer-->>Orchestrator: PASS / FAIL

        Orchestrator->>Tester: Validate changes
        Tester-->>Orchestrator: PASS / FAIL
    end

    alt Security-Sensitive Changes
        Orchestrator->>Security: Security audit
        Security-->>Orchestrator: PASS / FAIL
    end

    alt Validation Failed
        Orchestrator-->>OpenCode: Failure report
    else Validation Passed
        Orchestrator-->>OpenCode: Final result
    end

    OpenCode-->>Developer: Summary + Files + Findings
```

---

## Command Workflow Router

This diagram shows how each slash command is routed to its specific agent workflow sequence.

```mermaid
sequenceDiagram
    autonumber

    actor User
    participant OR as orchestrator-agent
    participant F as finder
    participant A as analyst
    participant R as researcher
    participant AR as architect
    participant P as planner
    participant C as coder
    participant FX as fixer
    participant D as debugger
    participant RF as refactorer
    participant RV as reviewer
    participant T as tester
    participant S as security
    participant O as optimizer
    participant DO as documenter
    participant CM as commenter
    participant DV as devops

    User->>OR: Slash command
    OR->>F: Always first

    alt /feature
        F-->>OR: Repo context
        OR->>A: Analyze impact
        OR->>R: Research docs/references
        OR->>AR: Design architecture
        OR->>P: Create implementation plan
        OR->>C: Implement feature
        OR->>RV: Review
        OR->>T: Test
        OR->>DO: Document
    else /bugfix known
        F-->>OR: Bug location/context
        OR->>FX: Apply minimal fix
        OR->>RV: Review
        OR->>T: Test
    else /bugfix unknown
        F-->>OR: Bug context
        OR->>D: Diagnose root cause
        OR->>FX: Apply fix
        OR->>RV: Review
        OR->>T: Test
    else /refactor
        F-->>OR: Refactor target context
        OR->>A: Analyze dependencies/impact
        OR->>RF: Refactor safely
        OR->>RV: Review
        OR->>T: Test
    else /review
        F-->>OR: Change/context discovery
        OR->>RV: Review only
    else /security
        F-->>OR: Security-relevant context
        OR->>A: Analyze risk/impact
        OR->>S: Security audit
        OR->>RV: Review
    else /performance
        F-->>OR: Performance target context
        OR->>A: Analyze bottleneck/impact
        OR->>O: Optimize
        OR->>RV: Review
        OR->>T: Test
    else /document
        F-->>OR: Documentation context
        OR->>DO: Create/update docs
    else /comment
        F-->>OR: Code context
        OR->>CM: Add concise comments
    else /devops
        F-->>OR: CI/CD/build context
        OR->>A: Analyze pipeline impact
        OR->>DV: DevOps change
        OR->>RV: Review
    else /analyze
        F-->>OR: Repo context
        OR->>A: Analyze
    else /analyze deep
        F-->>OR: Repo context
        OR->>A: Analyze
        OR->>R: External/reference research
    else /analyze architecture
        F-->>OR: Repo context
        OR->>A: Analyze
        OR->>AR: Architecture review/design
    else /help
        OR-->>User: Return commands, workflows, skills
    end
```

---

## Available Command Workflows

This flowchart shows all available slash commands and their corresponding agent workflows.

```mermaid
flowchart TD
    U[User] --> O[orchestrator-agent<br/>ninerouter/solo-orchestrator]

    O --> CMD{Command}

    CMD -->|/feature| F1[finder]
    F1 --> A1[analyst]
    A1 --> R1[researcher]
    R1 --> AR1[architect]
    AR1 --> P1[planner]
    P1 --> C1[coder]
    C1 --> RV1[reviewer]
    RV1 --> T1[tester]
    T1 --> D1[documenter]

    CMD -->|/bugfix known| F2[finder]
    F2 --> FX2[fixer]
    FX2 --> RV2[reviewer]
    RV2 --> T2[tester]

    CMD -->|/bugfix unknown| F3[finder]
    F3 --> DBG3[debugger]
    DBG3 --> FX3[fixer]
    FX3 --> RV3[reviewer]
    RV3 --> T3[tester]

    CMD -->|/refactor| F4[finder]
    F4 --> A4[analyst]
    A4 --> RF4[refactorer]
    RF4 --> RV4[reviewer]
    RV4 --> T4[tester]

    CMD -->|/review| F5[finder]
    F5 --> RV5[reviewer]

    CMD -->|/security| F6[finder]
    F6 --> A6[analyst]
    A6 --> S6[security]
    S6 --> RV6[reviewer]

    CMD -->|/performance| F7[finder]
    F7 --> A7[analyst]
    A7 --> O7[optimizer]
    O7 --> RV7[reviewer]
    RV7 --> T7[tester]

    CMD -->|/document| F8[finder]
    F8 --> DOC8[documenter]

    CMD -->|/comment| F9[finder]
    F9 --> CM9[commenter]

    CMD -->|/devops| F10[finder]
    F10 --> A10[analyst]
    A10 --> DV10[devops]
    DV10 --> RV10[reviewer]

    CMD -->|/analyze| F11[finder]
    F11 --> A11[analyst]

    CMD -->|/analyze deep| F12[finder]
    F12 --> A12[analyst]
    A12 --> R12[researcher]

    CMD -->|/analyze architecture| F13[finder]
    F13 --> A13[analyst]
    A13 --> AR13[architect]

    CMD -->|/help| H[Return commands, workflows, skills]
```

---

## Skill Routing Sequence

This diagram shows how the orchestrator loads domain-specific skills based on the task context.

```mermaid
sequenceDiagram
    autonumber

    actor User
    participant OR as orchestrator-agent
    participant SR as Skill Router
    participant SK as Matching Skills
    participant WF as Workflow Agents

    User->>OR: Request with domain context
    OR->>SR: Detect domain need

    SR->>SR: Match task to skill descriptions
    SR->>SR: Keep minimum required skills
    SR->>SR: Preferred 1-3 skills
    SR->>SR: Maximum 5 skills

    alt incoming-call task
        SR->>SK: Load ios
        SR->>SK: Load pushkit
        SR->>SK: Load callkit
    else firebase-auth task
        SR->>SK: Load firebase-auth
    else deep-link task
        SR->>SK: Load deep-linking
        SR->>SK: Load flutter-navigation
    else no matching domain
        SR-->>OR: No skill loaded
    end

    SK-->>OR: Domain instructions injected
    OR->>WF: Run selected command workflow
    WF-->>OR: Result grounded by loaded skills
```

---

## Gate Handling Flow

This diagram shows how quality gates (reviewer, tester, security) control workflow completion.

```mermaid
sequenceDiagram
    autonumber

    participant OR as orchestrator-agent
    participant A as Workflow Agents
    participant RV as reviewer
    participant TS as tester
    participant SC as security
    participant OUT as Output

    OR->>A: Execute selected workflow
    A-->>OR: Work result

    alt Code change exists
        OR->>RV: Required review gate
        RV-->>OR: PASS / FAIL

        OR->>TS: Required test gate
        TS-->>OR: PASS / FAIL
    end

    alt Sensitive domain exists
        OR->>SC: Required security gate
        SC-->>OR: PASS / FAIL
    end

    alt reviewer FAIL
        OR->>OUT: Fail condition<br/>stop and report reviewer issues
    else tester FAIL
        OR->>OUT: Fail condition<br/>stop and report test issues
    else security FAIL
        OR->>OUT: Fail condition<br/>stop and report security issues
    else all gates passed or not required
        OR->>OUT: Final summary
    end
```

---

## Agent Categories

This flowchart organizes all available agents by their role categories.

```mermaid
flowchart LR

    Developer --> OpenCode

    OpenCode --> Orchestrator

    Orchestrator --> Finder

    Orchestrator --> Planning
    Orchestrator --> Execution
    Orchestrator --> Quality

    subgraph Planning
        Analyst
        Researcher
        Architect
        Planner
    end

    subgraph Execution
        Coder
        Fixer
        Debugger
        Refactorer
        Optimizer
        DevOps
    end

    subgraph Quality
        Reviewer
        Tester
        Security
    end

    Quality --> Result
```

---

## Presentation Notes

### Key Points

- **`orchestrator-agent`** is the central routing coordinator
- User interacts via **slash commands** (`/feature`, `/bugfix`, `/refactor`, etc.)
- **`finder`** always runs first in every workflow
- Workflow is selected from command mapping
- **Skills** are loaded only when domain matches task context
- Code changes **must pass** `reviewer` + `tester` gates
- Sensitive domains **must pass** `security` gate
- If `reviewer`, `tester`, or `security` returns `FAIL`, workflow stops immediately

### Output Format

Every workflow returns:

- `command` - slash command used
- `workflow` - agent sequence executed
- `skills` - domain skills loaded
- `summary` - task result
- `files changed` - modified files
- `review` - review gate result
- `test` - test gate result
- `security` - security gate result

### Agent Models (9Router)

| Agent Category | Model ID |
| --- | --- |
| Orchestrator | `ninerouter/solo-orchestrator` |
| Research (fast) | `ninerouter/researcher-fast` |
| Research (deep) | `ninerouter/researcher-deep` |
| Implementation (low) | `ninerouter/implementation-low` |
| Implementation (high) | `ninerouter/implementation-high` |
| Quality (high) | `ninerouter/quality-high` |
| Quality (safer) | `ninerouter/quality-safer` |
| Infrastructure (low) | `ninerouter/infrastructure-low` |
| Infrastructure (high) | `ninerouter/infrastructure-high` |
| Documentation | `ninerouter/documentation-low` |

### Available Commands

| Command | Purpose |
| --- | --- |
| `/feature` | Full feature implementation workflow |
| `/bugfix` | Bug fix workflow (known or unknown) |
| `/refactor` | Safe refactoring workflow |
| `/review` | Code review only |
| `/security` | Security audit workflow |
| `/performance` | Performance optimization workflow |
| `/document` | Documentation creation/update |
| `/comment` | Add inline code comments |
| `/devops` | CI/CD and deployment workflow |
| `/analyze` | Repository analysis (standard/deep/architecture) |
| `/help` | Show available commands and workflows |
