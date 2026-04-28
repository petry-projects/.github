# OneNote → GitHub Markdown Migration Tool

Fully automated migration of Microsoft OneNote (personal account) to a Git
repository of Markdown files. Uses the Microsoft Graph API to export every
notebook, section, page, and subpage — preserving attachments, images, and
version history as backdated Git commits.

---

## Features

| Feature | Detail |
|---|---|
| **Full hierarchy** | Notebooks → Sections → Pages → Subpages (recursive) |
| **Attachments** | Images and files downloaded to `assets/` alongside each page |
| **Version history** | One Git commit per page, backdated to `lastModifiedDateTime` |
| **Resume / skip** | Re-running skips already-migrated pages via `git log` inspection |
| **Rate limit handling** | Exponential back-off on HTTP 429 / 503 (up to 6 retries, 60s cap) |
| **Dry-run mode** | Preview what would be migrated without writing anything |
| **YAML front matter** | Every `index.md` includes title, dates, notebook, and section metadata |
| **Personal accounts** | Works with outlook.com / hotmail.com / live.com — no org tenant needed |

---

## Output Structure

```
onenote-vault/
├── personal-notebook/
│   ├── recipes/
│   │   ├── smoked-brisket/
│   │   │   ├── index.md
│   │   │   └── assets/
│   │   │       └── photo.jpg
│   └── beekeeping/
│       ├── hive-inspection-spring-2024/
│       │   ├── index.md
│       │   └── assets/
│       │       └── hive-photo.jpg
└── work-notebook/
    └── ...
```

Each `index.md` begins with YAML front matter:

```yaml
---
title: "Hive Inspection — Spring 2024"
created: 2024-03-01T09:00:00Z
modified: 2024-03-15T10:30:00Z
notebook: "Beekeeping"
section: "Inspections"
---
```

---

## Prerequisites

- Python 3.10+
- [Pandoc](https://pandoc.org/installing.html)
- A personal Microsoft account (outlook.com, hotmail.com, live.com)
- An Azure App Registration (free — see setup below)

---

## Azure App Registration

One-time setup, ~5 minutes.

1. Go to [portal.azure.com](https://portal.azure.com) → **App registrations** → **New registration**
2. Name: anything. Supported account types: **"Personal Microsoft accounts only"**. Redirect URI: leave blank.
3. Click **Register**. Copy the **Application (client) ID**.
4. Go to **API permissions** → **Add a permission** → **Microsoft Graph** → **Delegated**
5. Add `Notes.Read.All` and `User.Read`. Click **Add permissions**.

No client secret or admin consent needed.

---

## Installation

```bash
pip install -r requirements.txt
```

---

## Configuration

```bash
export ONENOTE_CLIENT_ID="your-client-id-here"   # macOS / Linux / Termux
```

Or pass inline: `python onenote_migrate.py --client-id your-id`

---

## Usage

```bash
# Preview without writing anything (recommended first step)
python onenote_migrate.py --dry-run

# Full migration
python onenote_migrate.py --repo ./onenote-vault

# Resume after interruption — already-migrated pages are skipped automatically
python onenote_migrate.py --repo ./onenote-vault
```

On first run, a device-code prompt appears. Open https://microsoft.com/devicelogin,
enter the code, sign in with your personal Microsoft account, and grant permissions.

---

## Push to GitHub

```bash
cd onenote-vault
gh repo create petry-projects/onenote-vault --private
git remote add origin git@github.com:petry-projects/onenote-vault.git
git push -u origin main
```

Commits are backdated to each page's original OneNote modification date.

---

## Running the Tests

```bash
python -m unittest test_migrate -v
# Ran 62 tests in ~0.2s — OK
```

No external test dependencies. All network, MSAL, and Git calls are mocked.

---

## Known Limitations

| Item | Status |
|---|---|
| Images | ✅ Downloaded and linked locally |
| File attachments (PDF, xlsx) | ⚠️ Graph API exposes some but not all |
| OneNote page version history | ⚠️ Single snapshot per page — Graph API does not expose internal history |
| Section groups (nested) | ⚠️ Not currently traversed |
| Password-protected sections | ❌ Inaccessible via Graph API |

---

## Architecture

```
Microsoft Graph API (Notes.Read.All)
  → MSAL device-code auth
  → Enumerate notebooks → sections → pages → subpages
      → Fetch page HTML
      → Download embedded assets → assets/
      → Rewrite Graph URLs → relative paths
      → Strip <script>/<style>
      → HTML → Markdown (markdownify)
      → Prepend YAML front matter
      → Write index.md
  → Git commit (backdated to lastModifiedDateTime)
  → GitHub repo (git push)
```

---

## Dependencies

| Package | Purpose |
|---|---|
| `msal` | Microsoft Authentication Library — device-code OAuth |
| `requests` | HTTP client for Graph API calls |
| `markdownify` | HTML → Markdown conversion |
| `gitpython` | Git commits with custom author/committer dates |
| `pandoc` | System binary for complex HTML structures |
