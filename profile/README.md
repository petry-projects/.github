# Petry Projects

A collection of open-source tools and experiments spanning terminal UX, market data, AI content tooling,
beekeeping tech, and agent orchestration.

---

## Projects

| Repository | Description | Language |
| --- | --- | --- |
| [TalkTerm](https://github.com/petry-projects/TalkTerm) | Terminal-based communication tool | HTML |
| [markets](https://github.com/petry-projects/markets) | Market data and analysis tooling (dual-licensed AGPL / Commercial) | HTML |
| [broodly](https://github.com/petry-projects/broodly) | A test implementation of the BMAD method | HTML |
| [broodminder-export](https://github.com/petry-projects/broodminder-export) | Extract all of your data from the BroodMinder API into portable files — resumable, rate-limit-aware. | Python |
| [ContentTwin](https://github.com/petry-projects/ContentTwin) | AI-powered Social Media Agent for small organizations — enterprise-quality social presence at non-profit pricing | Shell |
| [bmad-bgreat-suite](https://github.com/petry-projects/bmad-bgreat-suite) | BMad Operations Suite — SRE and DevOps agents and workflows for the BMad Method ecosystem | Shell |
| [google-app-scripts](https://github.com/petry-projects/google-app-scripts) | A collection of Google Apps Scripts for personal productivity automation | JavaScript |
| [incubator](https://github.com/petry-projects/incubator) | Product incubator: pre-product idea Discussions, decision briefs/PRD-lite, and disposable POCs. Ideas graduate to their own product repo once a POC proves out. | Shell |
| [repo-template](https://github.com/petry-projects/repo-template) | Org template repository: one-click scaffold for new petry-projects repos. Files via 'Use this template'; non-file standards via bootstrap. | Shell |
| [.github-private](https://github.com/petry-projects/.github-private) | Org-wide Copilot custom agents, Claude Code skills, and agentic workflow infrastructure | Shell |
| [.github](https://github.com/petry-projects/.github) | Organization-wide GitHub configuration, CI templates, and engineering standards | Shell |

---

## Standards & Practices

All repositories in this org follow shared engineering standards defined in
[`.github`](https://github.com/petry-projects/.github):

- **CI Standards** — Reusable workflow versioning via the `stable` channel; staged promotion through
  concentric rings; action pinning policy; permissions policy; workflow patterns by tech stack
  (Node.js, Go, Python, Electron).

- **Advanced Security** — Code Security Configurations for the org fleet; push-protection live-fire
  canary test; custom secret scanning patterns; compliance audit checks.

- **Push Protection** — GitHub push protection (primary enforcement); local pre-commit prevention;
  CI secret scanning (secondary defense); incident response runbook.

- **Agent Standards** — AgentShield deep security scan; required agent files and compliance
  exemptions; BMAD Method workflows; decision-making reusables.

- **Dependabot Policy** — Stack-specific templates (npm, Go, Rust, Python, Terraform, Actions);
  auto-merge workflow; vulnerability audit CI check; CODEOWNERS approval timing.

- **GitHub Settings** — Repository rulesets (`pr-quality`, `code-quality`); auto-merge
  configuration; bypass actors; labels — standard set; org-level secrets.

- **CODEOWNERS Standard** — Branch protection; team composition; required setup for new bots.

- **Copilot Instructions Standard** — Canonical instruction files (source of truth in `.github`);
  adding a new language; content quality rules.

- **Persona Standards** — Trigger matrix (the onboarding checklist); canary onboarding (the last
  step); trust, permissions, and safety.

- **PR Limits** — Exempt actors; operator runbook; reconciliation with the Dependabot cap.

---

## Contributing

1. Fork the relevant repository and create a branch off `main`.
2. Follow the [AGENTS.md](https://github.com/petry-projects/.github/blob/main/AGENTS.md) guidelines
   for commit style, TDD, and CI requirements.
3. Open a pull request — CI must pass before review.

Questions or feedback? Open an issue in the relevant repo.
