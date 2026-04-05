# Agent Configuration Standards

Standards for repositories that use AI agent configurations (CLAUDE.md,
AGENTS.md, BMAD modules, Claude plugins, MCP server configs).

---

## Required Files

Every repository MUST have:

| File | Purpose | Compliance Check |
|------|---------|-----------------|
| `CLAUDE.md` | Project-level instructions for Claude Code | error if missing |
| `AGENTS.md` | Development standards for AI agents | error if missing |

### CLAUDE.md Requirements

- MUST reference `AGENTS.md` for development standards
- MUST NOT contain secrets, API keys, or credentials
- MUST NOT contain overly permissive tool authorization (e.g., `dangerouslySkipPermissions`)
- SHOULD define project-specific context (tech stack, conventions, key files)

### AGENTS.md Requirements

- MUST reference the org-level standards: `petry-projects/.github/AGENTS.md`
- MUST define project-specific development standards (testing, code style, architecture)
- MUST NOT override org-level security policies

## Agent Configuration Security

Repositories with agent configurations MUST pass the AgentShield CI check,
which validates:

### Security Rules

| Rule | Severity | Status | Description |
|------|----------|--------|-------------|
| `no-secrets` | error | Enforced | No API keys, tokens, passwords, or connection strings in agent config files |
| `no-skip-permissions` | error | Enforced | No `dangerouslySkipPermissions` or equivalent permission bypasses |
| `org-reference` | error | Enforced | AGENTS.md must reference org-level `.github/AGENTS.md` |
| `claude-reference` | error | Enforced | CLAUDE.md must reference AGENTS.md |
| `no-unrestricted-tools` | warning | Planned | Tool authorizations should be scoped, not wildcard |
| `no-prompt-injection-vectors` | warning | Planned | Config files should not include user-controllable template variables in security-sensitive positions |

### Structural Rules

| Rule | Severity | Status | Description |
|------|----------|--------|-------------|
| `valid-yaml-frontmatter` | error | Enforced | All SKILL.md files must have valid YAML frontmatter with `name` and `description` |
| `no-orphan-skills` | warning | Enforced | Every skill directory must be registered in module-help.csv (if applicable) |
| `manifest-consistency` | warning | Planned | Skill manifests must match directory structure |

## AgentShield CI Workflow

Every repository MUST include `.github/workflows/agent-shield.yml`.
See [`workflows/agent-shield.yml`](workflows/agent-shield.yml) for the
standard template.

**Standard triggers:** push to main, pull requests to main.

The workflow validates all agent configuration files and fails the build
if any error-severity rule is violated.

## Agent Ecosystem in Dependabot

Repositories with BMAD modules or Claude plugins should track agent
dependencies. While Dependabot does not have a native "agents" ecosystem,
the AgentShield CI workflow performs equivalent version and security checks
on agent configuration files.

For repos with `package.json` referencing BMAD modules (e.g., `bmad-method`,
`bmad-bgreat-suite`), the `npm` ecosystem already covers version tracking.
The AgentShield check adds the agent-specific security layer on top.
