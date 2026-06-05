# opencode Multi-Agent Workspace

This directory contains the project-local opencode setup for SDK Connect. It defines specialized agents, domain skills, command workflows, and 9Router model routing.

## Directory Layout

```text
.opencode/
├── opencode.json              # Project opencode config and inline agent model/tool mapping
├── agents/
│   ├── core/                  # Primary orchestration agent
│   └── subagents/             # Specialized subagents grouped by capability
├── skills/                    # Project domain skills loaded by opencode
├── package.json               # Local plugin/dev dependency metadata
└── package-lock.json
```

## Agent Model

Agents are split by workflow responsibility. Each agent has a focused prompt, model, and tool permission set.

### Core Agent

| Agent | Purpose |
| --- | --- |
| `orchestrator` | Routes user commands to the correct workflow, selects agents, applies gates, and summarizes results. |

### Research Agents

| Agent | Purpose | Model |
| --- | --- | --- |
| `finder` | Fast repository scout. Finds files, symbols, patterns, and entry points. | `ninerouter/researcher-fast` |
| `analyst` | Analyzes structure, dependencies, execution flow, risks, and change impact. | `ninerouter/researcher-deep` |
| `researcher` | Uses external references and official documentation when needed. | `ninerouter/researcher-deep` |

### Planning Agents

| Agent | Purpose | Model |
| --- | --- | --- |
| `architect` | Designs maintainable mobile architecture, boundaries, and integrations. | configured in agent file/config |
| `planner` | Breaks architecture or feature design into executable tasks. | `ninerouter/researcher-fast` |

### Implementation Agents

| Agent | Purpose | Model |
| --- | --- | --- |
| `coder` | Creates new files, functions, classes, and features from plan/design. | `ninerouter/implementation-high` |
| `editor` | Modifies existing files and integrates changes. | `ninerouter/implementation-low` |
| `fixer` | Applies minimal bug fixes from diagnosis or known reports. | `ninerouter/implementation-low` |
| `refactorer` | Improves structure/readability without behavior changes. | `ninerouter/implementation-low` |

### Quality Agents

| Agent | Purpose | Model |
| --- | --- | --- |
| `reviewer` | Reviews code changes for correctness, maintainability, and consistency. | `ninerouter/quality-high` |
| `tester` | Verifies implementation with project-aligned tests and checks. | `ninerouter/quality-safer` |
| `debugger` | Investigates unknown bugs and identifies root cause. | `ninerouter/quality-high` |
| `security` | Audits security-sensitive code/configuration. | `ninerouter/quality-high` |

### Infrastructure and Documentation Agents

| Agent | Purpose | Model |
| --- | --- | --- |
| `optimizer` | Improves performance, memory usage, startup time, and efficiency. | `ninerouter/infrastructure-low` |
| `devops` | Handles CI/CD, release automation, build pipelines, and deployment workflows. | `ninerouter/infrastructure-high` |
| `documenter` | Creates and updates technical documentation and README files. | `ninerouter/documentation-low` |
| `commenter` | Adds concise code comments and inline documentation. | `ninerouter/documentation-low` |

## Tool Permission Pattern

Agents get only tools needed for their role.

- Discovery agents usually get `read`, `list`, `glob`, and `grep`.
- Analysis agents may get `lsp` for symbol/context lookup.
- Implementation agents get `write`, `edit`, and limited `bash`.
- Review/security agents are read-only.
- Documentation agents can write/edit documentation.
- External web access is restricted to `researcher` unless explicitly needed.

This keeps each agent scoped and reduces accidental edits.

## Skills

Project skills live under:

```text
.opencode/skills/<skill-name>/SKILL.md
```

Current skills:

| Skill | Focus |
| --- | --- |
| `call-engine-skill` | Call engine behavior and lifecycle rules. |
| `call-lifecycle-safety-skill` | Safe call lifecycle transitions and cleanup. |
| `media-engine-skill` | Media engine and LiveKit media integration boundaries. |
| `memory-governance-skill` | Memory cleanup, listener disposal, and resource ownership. |
| `orchestrator-efficiency-skill` | Efficient orchestration, routing, and agent usage. |
| `p2p-session-security-skill` | Peer-to-peer session security concerns. |
| `realtime-signaling-skill` | Realtime signaling architecture and validation. |
| `realtime-token-security-skill` | Token generation, storage, expiry, and security. |
| `sdk-abstraction-skill` | SDK abstraction boundaries and transport isolation. |
| `sdk-architecture-skill` | SDK Connect architecture and infrastructure separation. |
| `signaling-validation-skill` | Signaling payload validation and lifecycle safety. |

Skills should be loaded only when user task matches their domain. Keep skill descriptions specific so opencode selects them only for relevant work.

## Command Workflows

Use slash commands to trigger predictable multi-agent workflows.

| Command | Workflow |
| --- | --- |
| `/feature` | `finder → analyst → researcher → architect → planner → coder → reviewer → tester → documenter` |
| `/bugfix` known issue | `finder → fixer → reviewer → tester` |
| `/bugfix` unknown issue | `finder → debugger → fixer → reviewer → tester` |
| `/refactor` | `finder → analyst → refactorer → reviewer → tester` |
| `/review` | `finder → reviewer` |
| `/security` | `finder → analyst → security → reviewer` |
| `/performance` | `finder → analyst → optimizer → reviewer → tester` |
| `/document` | `finder → documenter` |
| `/comment` | `finder → commenter` |
| `/devops` | `finder → analyst → devops → reviewer` |
| `/analyze` | `finder → analyst` |
| `/analyze deep` | `finder → analyst → researcher` |
| `/analyze architecture` | `finder → analyst → architect` |
| `/help` | Returns command, workflow, and skill help. |

### Workflow Gates

- `finder` always runs first.
- Code changes must pass `reviewer` and `tester`.
- Sensitive domains require `security`.
- Fail if `reviewer`, `tester`, or `security` returns `FAIL`.
- Use repository context only and avoid unrelated context.

## 9Router Setup

This configuration routes opencode agents through 9Router model IDs such as:

```text
ninerouter/researcher-fast
ninerouter/researcher-deep
ninerouter/implementation-low
ninerouter/implementation-high
ninerouter/quality-high
ninerouter/quality-safer
ninerouter/infrastructure-low
ninerouter/infrastructure-high
ninerouter/documentation-low
ninerouter/solo-orchestrator
```

### 1. Install opencode

Follow official opencode installation instructions for your environment.

```sh
npm install -g opencode-ai
```

If your installation uses a different package or binary name, keep that official method.

### 2. Configure 9Router Credentials

Set your 9Router API key in your shell environment. Use your actual key value.

```sh
export NINEROUTER_API_KEY="your-api-key"
```

If your 9Router provider uses OpenAI-compatible environment variables, also set:

```sh
export OPENAI_API_KEY="$NINEROUTER_API_KEY"
export OPENAI_BASE_URL="https://api.9router.ai/v1"
```

Use the exact base URL from your 9Router account/provider documentation if it differs.

### 3. Configure opencode Provider

Keep project agent models prefixed with `ninerouter/` in `.opencode/opencode.json` or agent frontmatter.

Example:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "model": "ninerouter/solo-orchestrator",
  "agent": {
    "finder": {
      "mode": "subagent",
      "model": "ninerouter/researcher-fast",
      "description": "Fast repository scout. Finds files, symbols, patterns, and entry points."
    }
  }
}
```

If opencode requires an explicit custom provider in your environment, add provider settings according to the current opencode schema at:

```text
https://opencode.ai/config.json
```

Do not commit API keys into `.opencode/opencode.json`.

### 4. Install Local Dependencies

From `.opencode/`:

```sh
npm install
```

Type-check local plugin/dev files if needed:

```sh
npm run typecheck
```

### 5. Start opencode From Repository Root

From repository root:

```sh
opencode
```

opencode walks up from the current directory and loads project config from `.opencode/opencode.json`.

### 6. Restart After Config Changes

opencode loads config once at startup. After changing `.opencode/opencode.json`, agent files, skill files, plugins, MCP servers, or permissions, quit and restart opencode.

## Adding an Agent

Prefer file-based agents for non-trivial behavior.

Create:

```text
.opencode/agents/<group>/<agent-name>.md
```

Example:

```markdown
---
name: my-agent
description: Short trigger-focused description.
mode: subagent
model: ninerouter/implementation-low
permission:
  read: allow
  edit: ask
  bash: ask
---

Agent prompt goes here.
```

Rules:

- Use `mode: subagent` for workflow agents.
- Keep description concrete and trigger-focused.
- Grant only tools needed by the role.
- Do not put secrets in agent files.

## Adding a Skill

Create:

```text
.opencode/skills/<skill-name>/SKILL.md
```

Recommended format:

```markdown
---
name: my-skill
description: Use when working on specific domain, files, or keywords.
---

# My Skill

Instructions, rules, examples, and constraints.
```

Rules:

- Folder name and `name` should match.
- Use lowercase hyphen-separated names.
- Description should say when to use the skill.
- Keep skill scope narrow to avoid noisy routing.

## Security Notes

- Never commit API keys, tokens, signing keys, or credentials.
- Prefer environment variables for provider credentials.
- Keep write/edit permissions limited to agents that need them.
- Route auth, token, signaling, and P2P tasks through security-oriented skills and the `security` agent.

## Troubleshooting

### opencode fails to start after config edit

Use one of these escape hatches:

```sh
OPENCODE_DISABLE_PROJECT_CONFIG=1 opencode
```

or:

```sh
OPENCODE_CONFIG=/path/to/known-good-opencode.json opencode
```

Fix invalid config, then restart normally.

### Agents or skills do not update

Restart opencode. Config, agents, skills, plugins, and MCP definitions are loaded once at startup.

### Model not found or provider authentication fails

Check:

1. 9Router API key is exported in the same shell that starts opencode.
2. Model IDs match valid 9Router model aliases.
3. Provider/base URL configuration matches current 9Router documentation.
4. No API key is hardcoded or accidentally committed.
