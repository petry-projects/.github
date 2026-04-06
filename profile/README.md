# Petry Projects

A collection of open-source tools and experiments spanning terminal UX, market data, AI content tooling, and agent orchestration.

---

## Projects

| Repository | Description | Topics |
| --- | --- | --- |
| [TalkTerm](https://github.com/petry-projects/TalkTerm) | Terminal-based communication tool | terminal, cli |
| [markets](https://github.com/petry-projects/markets) | Market data and analysis tooling | finance, data |
| [ContentTwin](https://github.com/petry-projects/ContentTwin) | AI-powered content generation and management | ai, content |
| [bmad-bgreat-suite](https://github.com/petry-projects/bmad-bgreat-suite) | BMAD agent workflow suite | agents, automation |
| [.github](https://github.com/petry-projects/.github) | Org-wide standards, CI templates, and compliance tooling | standards, devops |

---

## Standards & Practices

All repositories in this org follow shared engineering standards defined in [`.github`](https://github.com/petry-projects/.github):

- **TDD** — tests are written before implementation; coverage gates enforced in CI
- **CodeQL** — static analysis on every PR
- **SonarCloud** — code quality and security scanning
- **Dependabot** — automated dependency updates with automerge for patch-level changes
- **Claude Code** — AI-assisted development via [agent standards](https://github.com/petry-projects/.github/blob/main/AGENTS.md)

---

## Contributing

1. Fork the relevant repository and create a branch off `main`.
2. Follow the [AGENTS.md](https://github.com/petry-projects/.github/blob/main/AGENTS.md) guidelines for commit style, TDD, and CI requirements.
3. Open a pull request — CI must pass before review.

Questions or feedback? Open an issue in the relevant repo.
