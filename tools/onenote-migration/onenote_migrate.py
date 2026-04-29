"""
onenote_migrate.py
──────────────────
Fully automated migration of Microsoft OneNote (personal account) to a
Git repository of Markdown files.

Features
--------
• Device-code OAuth flow  (personal Microsoft accounts / consumers tenant)
• Notebooks → Sections → Pages → Subpages  (full hierarchy)
• Attachments and images downloaded to assets/ folders
• YAML front matter on every page
• One Git commit per page, backdated to lastModifiedDateTime
• Resume / skip: already-committed pages are skipped on re-run
• Rate-limit handling: exponential back-off on HTTP 429 / 503
• Dry-run mode: prints what would happen without writing anything
• Rich progress output with counts and timing

Usage
-----
    pip install msal requests markdownify gitpython
    python onenote_migrate.py [--dry-run] [--repo ./onenote-vault]

Configuration
-------------
Set AZURE_CLIENT_ID and AZURE_TENANT in the Config class below,
or pass them as environment variables ONENOTE_CLIENT_ID / ONENOTE_TENANT.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
import textwrap
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

# ── Optional heavy imports (mocked in tests) ─────────────────────────────────
try:
    import requests as _requests
except ImportError:                          # pragma: no cover
    _requests = None                         # type: ignore

try:
    from markdownify import markdownify as _markdownify
except ImportError:                          # pragma: no cover
    _markdownify = None                      # type: ignore

try:
    import git as _git
except ImportError:                          # pragma: no cover
    _git = None                              # type: ignore

try:
    from msal import PublicClientApplication as _MSAL
except ImportError:                          # pragma: no cover
    _MSAL = None                             # type: ignore


# ╔══════════════════════════════════════════════════════════════╗
# ║  Config                                                      ║
# ╚══════════════════════════════════════════════════════════════╝

class Config:
    CLIENT_ID:  str = os.getenv("ONENOTE_CLIENT_ID", "YOUR_AZURE_CLIENT_ID")
    TENANT:     str = os.getenv("ONENOTE_TENANT",    "consumers")
    SCOPES:     list[str] = ["Notes.Read.All", "User.Read"]
    GRAPH_BASE: str = "https://graph.microsoft.com/v1.0/me/onenote"
    AUTHORITY:  str = "https://login.microsoftonline.com/consumers"

    # Back-off: first retry after BACKOFF_BASE seconds, doubles each time
    BACKOFF_BASE:    float = 2.0
    BACKOFF_MAX:     float = 60.0
    BACKOFF_RETRIES: int   = 6


# ╔══════════════════════════════════════════════════════════════╗
# ║  Text / path helpers                                         ║
# ╚══════════════════════════════════════════════════════════════╝

def slugify(name: str) -> str:
    """Convert a display name to a safe directory / filename slug."""
    if not name:
        return "untitled"
    name = name.strip()
    name = re.sub(r"[^\w\s\-]", "", name)   # strip special chars
    name = re.sub(r"[\s_]+", "-", name)      # spaces → hyphens
    name = re.sub(r"-{2,}", "-", name)       # collapse multiple hyphens
    return name.strip("-").lower() or "untitled"


def build_front_matter(page: dict, notebook_name: str, section_name: str) -> str:
    """Return a YAML front-matter block for a page dict from the Graph API."""
    def q(s: str) -> str:
        return s.replace('"', '\\"')

    title    = page.get("title") or "Untitled"
    created  = page.get("createdDateTime", "")
    modified = page.get("lastModifiedDateTime", "")

    return textwrap.dedent(f"""\
        ---
        title: "{q(title)}"
        created: {created}
        modified: {modified}
        notebook: "{q(notebook_name)}"
        section: "{q(section_name)}"
        ---
    """)


def extract_resource_urls(html: str) -> list[str]:
    """Return all Graph API resource URLs embedded in page HTML."""
    pattern = re.compile(r'(?:src|href)="(https://graph\.microsoft\.com[^"]+)"')
    return pattern.findall(html)


def rewrite_resource_urls(html: str, url_to_local: dict[str, str]) -> str:
    """Replace Graph API URLs in HTML with local relative paths."""
    def replace(match: re.Match) -> str:
        attr, url = match.group(1), match.group(2)
        local = url_to_local.get(url, url)
        return f'{attr}="{local}"'
    return re.sub(r'(src|href)="(https://graph\.microsoft\.com[^"]+)"', replace, html)


def html_to_markdown(html: str) -> str:
    """Convert HTML to Markdown using markdownify."""
    if _markdownify is None:                 # pragma: no cover
        raise RuntimeError("markdownify is not installed")
    # Remove script/style blocks entirely (content + tags) before converting.
    # markdownify's strip= removes tags but keeps inner text, which leaks JS.
    html = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", html,
                  flags=re.DOTALL | re.IGNORECASE)
    return _markdownify(html, heading_style="ATX", bullets="-")


def local_asset_name(url: str, index: int) -> str:
    """Derive a local filename from a Graph API resource URL."""
    path = urlparse(url).path
    name = Path(path).name
    # Graph API resource URLs often end in /content — not a useful filename.
    # Require a real file extension; otherwise fall back to a numbered asset.
    if not name or "." not in name or name == "content":
        name = f"asset-{index:04d}.bin"
    # Sanitise remaining chars
    name = re.sub(r"[^\w.\-]", "_", name)
    return name


def format_commit_date(iso: str) -> str:
    """
    Ensure an ISO 8601 date string is formatted exactly as Git expects:
    'YYYY-MM-DDTHH:MM:SS+00:00'
    Accepts strings with or without milliseconds / timezone.
    """
    # Strip milliseconds if present
    iso = re.sub(r"\.\d+", "", iso)
    # Normalise Z → +00:00
    if iso.endswith("Z"):
        iso = iso[:-1] + "+00:00"
    # Validate by parsing
    try:
        dt = datetime.fromisoformat(iso)
    except ValueError:
        dt = datetime.now(tz=timezone.utc)
    return dt.isoformat()


# ╔══════════════════════════════════════════════════════════════╗
# ║  Network helpers                                             ║
# ╚══════════════════════════════════════════════════════════════╝

def retry_with_backoff(
    fn,
    *args,
    retries: int = Config.BACKOFF_RETRIES,
    base: float  = Config.BACKOFF_BASE,
    max_wait: float = Config.BACKOFF_MAX,
    **kwargs,
):
    """
    Call fn(*args, **kwargs). On HTTP 429 or 503 (or requests.Timeout),
    wait and retry with exponential back-off.
    Raises on final failure.
    """
    wait = base
    for attempt in range(retries + 1):
        try:
            response = fn(*args, **kwargs)
        except Exception as exc:
            if attempt == retries:
                raise
            print(f"    ⚠  Network error ({exc}), retrying in {wait:.0f}s …")
            time.sleep(wait)
            wait = min(wait * 2, max_wait)
            continue

        if response.status_code in (429, 503):
            retry_after = int(response.headers.get("Retry-After", wait))
            actual_wait = max(wait, retry_after)
            if attempt == retries:
                response.raise_for_status()
            print(f"    ⚠  Rate limited (HTTP {response.status_code}), "
                  f"waiting {actual_wait:.0f}s …")
            time.sleep(actual_wait)
            wait = min(wait * 2, max_wait)
            continue

        return response

    raise RuntimeError("retry_with_backoff: exhausted retries")  # pragma: no cover


def get_all(url: str, session) -> list[dict]:
    """Fetch all pages of a Graph API collection (handles @odata.nextLink)."""
    items: list[dict] = []
    while url:
        resp = retry_with_backoff(session.get, url)
        resp.raise_for_status()
        data = resp.json()
        items.extend(data.get("value", []))
        url = data.get("@odata.nextLink", "")
    return items


# ╔══════════════════════════════════════════════════════════════╗
# ║  Auth                                                        ║
# ╚══════════════════════════════════════════════════════════════╝

def authenticate(cfg: Config) -> str:
    """
    Run MSAL device-code flow and return an access token.
    Prints the user-facing device-code message.
    """
    if _MSAL is None:                        # pragma: no cover
        raise RuntimeError("msal is not installed. Run: pip install msal")
    app  = _MSAL(cfg.CLIENT_ID, authority=cfg.AUTHORITY)
    flow = app.initiate_device_flow(scopes=cfg.SCOPES)
    if "user_code" not in flow:
        raise RuntimeError(f"Device flow failed: {flow.get('error_description', flow)}")
    print(f"\n{flow['message']}\n")
    result = app.acquire_token_by_device_flow(flow)
    if "access_token" not in result:
        raise RuntimeError(f"Auth failed: {result.get('error_description', result)}")
    return result["access_token"]


def make_session(token: str):
    """Return a requests.Session pre-configured with the Bearer token."""
    if _requests is None:                    # pragma: no cover
        raise RuntimeError("requests is not installed")
    s = _requests.Session()
    s.headers.update({"Authorization": f"Bearer {token}"})
    return s


# ╔══════════════════════════════════════════════════════════════╗
# ║  Graph API queries                                           ║
# ╚══════════════════════════════════════════════════════════════╝

def get_notebooks(session, cfg: Config) -> list[dict]:
    return get_all(f"{cfg.GRAPH_BASE}/notebooks", session)


def get_sections(notebook_id: str, session, cfg: Config) -> list[dict]:
    return get_all(f"{cfg.GRAPH_BASE}/notebooks/{notebook_id}/sections", session)


def get_section_groups(notebook_id: str, session, cfg: Config) -> list[dict]:
    return get_all(f"{cfg.GRAPH_BASE}/notebooks/{notebook_id}/sectionGroups", session)


def get_pages(section_id: str, session, cfg: Config) -> list[dict]:
    url = f"{cfg.GRAPH_BASE}/sections/{section_id}/pages"
    return get_all(url, session)


def get_page_html(page_id: str, session, cfg: Config) -> str:
    url  = f"{cfg.GRAPH_BASE}/pages/{page_id}/content"
    resp = retry_with_backoff(session.get, url)
    resp.raise_for_status()
    return resp.text


def download_resource(url: str, dest: Path, session) -> None:
    """Download a Graph API resource (image / attachment) to dest."""
    resp = retry_with_backoff(session.get, url)
    resp.raise_for_status()
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(resp.content)


# ╔══════════════════════════════════════════════════════════════╗
# ║  Resume / skip logic                                         ║
# ╚══════════════════════════════════════════════════════════════╝

def load_migrated_ids(repo_path: Path) -> set[str]:
    """
    Parse Git log for commit messages that embed a page ID.
    Commit messages use the format: 'page:<PAGE_ID> <title>'
    Returns a set of already-migrated page IDs.
    """
    migrated: set[str] = None
    log_path = repo_path / ".git"
    if not log_path.exists():
        return set()

    try:
        import subprocess
        result = subprocess.run(
            ["git", "-C", str(repo_path), "log", "--format=%s"],
            capture_output=True, text=True, check=True
        )
        migrated = set()
        for line in result.stdout.splitlines():
            m = re.match(r"page:(\S+)", line)
            if m:
                migrated.add(m.group(1))
    except Exception:
        migrated = set()

    return migrated or set()


def should_skip(page_id: str, migrated: set[str]) -> bool:
    return page_id in migrated


# ╔══════════════════════════════════════════════════════════════╗
# ║  Git helpers                                                 ║
# ╚══════════════════════════════════════════════════════════════╝

def init_or_open_repo(repo_path: Path):
    """Init a new repo or open an existing one."""
    if _git is None:                         # pragma: no cover
        raise RuntimeError("gitpython is not installed. Run: pip install gitpython")
    repo_path.mkdir(parents=True, exist_ok=True)
    if (repo_path / ".git").exists():
        return _git.Repo(repo_path)
    repo = _git.Repo.init(repo_path)
    # Initial empty commit so HEAD exists
    repo.index.commit("chore: init onenote migration repo")
    return repo


def commit_page(repo, rel_paths: list[str], page_id: str,
                title: str, modified_iso: str) -> None:
    """Stage files and commit with backdated author / committer dates."""
    date_str = format_commit_date(modified_iso)
    for p in rel_paths:
        repo.index.add([p])
    message = f"page:{page_id} {title}"
    repo.index.commit(
        message,
        author_date=date_str,
        commit_date=date_str,
    )


# ╔══════════════════════════════════════════════════════════════╗
# ║  Page migration                                              ║
# ╚══════════════════════════════════════════════════════════════╝

def migrate_page(
    page:          dict,
    page_dir:      Path,
    notebook_name: str,
    section_name:  str,
    session,
    cfg:           Config,
    dry_run:       bool,
) -> list[str]:
    """
    Download and convert a single page.
    Returns list of paths (relative to repo root) that were written.
    """
    page_id  = page["id"]
    title    = page.get("title") or "Untitled"
    modified = page.get("lastModifiedDateTime", "")

    if dry_run:
        print(f"      [dry-run] would migrate: {title!r}")
        return []

    page_dir.mkdir(parents=True, exist_ok=True)
    asset_dir = page_dir / "assets"

    # Fetch HTML
    html = get_page_html(page_id, session, cfg)

    # Download embedded resources
    resource_urls = extract_resource_urls(html)
    url_to_local: dict[str, str] = {}
    for i, url in enumerate(resource_urls):
        fname = local_asset_name(url, i)
        dest  = asset_dir / fname
        try:
            download_resource(url, dest, session)
            url_to_local[url] = f"assets/{fname}"
        except Exception as exc:
            print(f"        ⚠  Could not download asset ({exc}): {url[:60]}…")

    # Rewrite URLs then convert
    html_local = rewrite_resource_urls(html, url_to_local)
    body_md    = html_to_markdown(html_local)
    front      = build_front_matter(page, notebook_name, section_name)

    md_path = page_dir / "index.md"
    md_path.write_text(front + "\n" + body_md, encoding="utf-8")

    # Collect relative paths for git staging
    written = [str(md_path)]
    if asset_dir.exists():
        written += [str(p) for p in asset_dir.iterdir()]

    return written


# ╔══════════════════════════════════════════════════════════════╗
# ║  Section migration (recursive for subpages)                  ║
# ╚══════════════════════════════════════════════════════════════╝

def migrate_section(
    section:       dict,
    section_dir:   Path,
    notebook_name: str,
    repo,
    repo_path:     Path,
    session,
    cfg:           Config,
    migrated:      set[str],
    dry_run:       bool,
    counters:      dict,
) -> None:
    section_name = section["displayName"]
    pages        = get_pages(section["id"], session, cfg)

    # Build parent→children map using level field (0 = root, 1+ = subpage)
    children: dict[str, list[dict]] = {}
    roots: list[dict] = []
    parent_stack: list[dict] = []  # track most recent page at each level
    for p in pages:
        level = p.get("level", 0)
        if level == 0:
            roots.append(p)
            parent_stack = [p]
        else:
            # parent is the last page seen at level-1
            if len(parent_stack) >= level:
                parent = parent_stack[level - 1]
                children.setdefault(parent["id"], []).append(p)
            else:
                roots.append(p)
            # trim stack to current level and push current page
            parent_stack = parent_stack[:level] + [p]

    def process_page(page: dict, parent_dir: Path, depth: int = 0) -> None:
        pid   = page["id"]
        slug  = slugify(page.get("title") or pid)
        pdir  = parent_dir / slug

        if should_skip(pid, migrated):
            print(f"      {'  '*depth}↩ skip (already migrated): {page.get('title')!r}")
            counters["skipped"] += 1
            return

        indent = "  " * depth
        print(f"      {indent}↳ {page.get('title')!r}")

        written = migrate_page(
            page, pdir, notebook_name, section_name,
            session, cfg, dry_run,
        )

        if written and not dry_run:
            rel = [str(Path(w).relative_to(repo_path)) for w in written]
            commit_page(
                repo, rel, pid,
                page.get("title") or "Untitled",
                page.get("lastModifiedDateTime", ""),
            )

        counters["pages"] += 1

        # Recurse into subpages
        for child in children.get(pid, []):
            process_page(child, pdir, depth + 1)

    section_dir.mkdir(parents=True, exist_ok=True)
    for root_page in roots:
        process_page(root_page, section_dir)


# ╔══════════════════════════════════════════════════════════════╗
# ║  Main orchestrator                                           ║
# ╚══════════════════════════════════════════════════════════════╝

def migrate(repo_path: Path, cfg: Config, dry_run: bool = False) -> None:
    t0 = time.time()
    counters = {"notebooks": 0, "sections": 0, "pages": 0, "skipped": 0}

    print("🔐 Authenticating …")
    token   = authenticate(cfg)
    session = make_session(token)

    repo = None if dry_run else init_or_open_repo(repo_path)
    migrated = set() if dry_run else load_migrated_ids(repo_path)
    if migrated:
        print(f"  ↩  {len(migrated)} pages already migrated, will skip\n")

    notebooks = get_notebooks(session, cfg)
    print(f"📓 Found {len(notebooks)} notebook(s)\n")

    for nb in notebooks:
        nb_name = nb["displayName"]
        nb_dir  = repo_path / slugify(nb_name)
        print(f"  📓 {nb_name}")
        counters["notebooks"] += 1

        sections = get_sections(nb["id"], session, cfg)
        for sec in sections:
            sec_name = sec["displayName"]
            sec_dir  = nb_dir / slugify(sec_name)
            print(f"    📄 {sec_name}")
            counters["sections"] += 1

            migrate_section(
                sec, sec_dir, nb_name,
                repo, repo_path, session, cfg,
                migrated, dry_run, counters,
            )

    elapsed = time.time() - t0
    print(f"\n✅ Done in {elapsed:.1f}s — "
          f"{counters['notebooks']} notebook(s), "
          f"{counters['sections']} section(s), "
          f"{counters['pages']} page(s) migrated, "
          f"{counters['skipped']} skipped.")


# ╔══════════════════════════════════════════════════════════════╗
# ║  CLI entry point                                             ║
# ╚══════════════════════════════════════════════════════════════╝

def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Migrate OneNote (personal account) to a Git repo of Markdown files."
    )
    p.add_argument("--repo",    default="./onenote-vault",
                   help="Path to output Git repository (default: ./onenote-vault)")
    p.add_argument("--dry-run", action="store_true",
                   help="Preview what would be migrated without writing any files")
    p.add_argument("--client-id", default=None,
                   help="Azure app client ID (overrides ONENOTE_CLIENT_ID env var)")
    return p.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    cfg  = Config()
    if args.client_id:
        cfg.CLIENT_ID = args.client_id

    if cfg.CLIENT_ID == "YOUR_AZURE_CLIENT_ID":
        print("❌  Set ONENOTE_CLIENT_ID env var or pass --client-id <your-id>")
        sys.exit(1)

    migrate(Path(args.repo), cfg, dry_run=args.dry_run)
