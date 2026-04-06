# petry-projects

A collection of open-source projects built with quality, security, and developer experience in mind.

## Projects

| Repository | Description |
|------------|-------------|
| [TalkTerm](https://github.com/petry-projects/TalkTerm) | Terminal-based communication tool |
| [markets](https://github.com/petry-projects/markets) | Market data and analysis tooling |
| [ContentTwin](https://github.com/petry-projects/ContentTwin) | Content management and duplication tooling |
| [bmad-bgreat-suite](https://github.com/petry-projects/bmad-bgreat-suite) | BMAD methodology and agent suite |
| [broodly](https://github.com/petry-projects/broodly) | Broodly project |
| [google-app-scripts](https://github.com/petry-projects/google-app-scripts) | Google Apps Script utilities and automations |

## Standards & Practices

All repositories follow organization-wide standards defined in [`.github`](https://github.com/petry-projects/.github):

- **Test-driven development** — tests are written before implementation; coverage gates enforced on every PR
- **Security-first** — CodeQL SAST, OpenSSF Scorecard, and `npm audit` / `govulncheck` on every build
- **AI-assisted reviews** — Claude Code Action and CodeRabbit review every pull request
- **Code quality** — SonarCloud analysis with maintainability and security hotspot tracking
- **Dependency hygiene** — Dependabot security updates with automated merging

## Contributing

1. Fork the repository you want to contribute to
2. Create a branch from `main`
3. Write tests for your changes first (TDD)
4. Open a pull request — CI, CodeQL, SonarCloud, and AI review run automatically
5. Address review feedback; all threads must be resolved before merge

See the [organization standards](https://github.com/petry-projects/.github/blob/main/AGENTS.md) for full contribution guidelines.
