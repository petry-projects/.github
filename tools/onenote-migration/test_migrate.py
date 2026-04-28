"""
test_migrate.py
───────────────
Full test suite for onenote_migrate.py.
All network / MSAL / Git calls are mocked.
"""

import sys
import types
import unittest
import tempfile
import subprocess
from pathlib import Path
from unittest.mock import MagicMock, patch, PropertyMock, call

# ── Stub out unavailable heavy modules before importing the script ─────────────

def _make_stub(name):
    mod = types.ModuleType(name)
    sys.modules[name] = mod
    return mod

msal_mod = _make_stub("msal")
msal_mod.PublicClientApplication = MagicMock()

git_mod = _make_stub("git")
git_mod.Repo = MagicMock()

import onenote_migrate as M   # noqa: E402 — must come after stubs


class TestSlugify(unittest.TestCase):
    def test_basic(self):
        self.assertEqual(M.slugify("Hello World"), "hello-world")
    def test_special_chars(self):
        self.assertEqual(M.slugify("Recipe: Smoked Brisket!"), "recipe-smoked-brisket")
    def test_consecutive_spaces(self):
        self.assertEqual(M.slugify("a   b"), "a-b")
    def test_consecutive_hyphens(self):
        self.assertEqual(M.slugify("a--b"), "a-b")
    def test_leading_trailing(self):
        self.assertEqual(M.slugify("  --hello-- "), "hello")
    def test_empty(self):
        self.assertEqual(M.slugify(""), "untitled")
    def test_none_like(self):
        self.assertEqual(M.slugify("   "), "untitled")
    def test_unicode_stripped(self):
        result = M.slugify("Bee 🐝 Hive")
        self.assertIn("bee", result)
        self.assertIn("hive", result)
    def test_numbers_preserved(self):
        self.assertEqual(M.slugify("Q3 2024"), "q3-2024")
    def test_already_slugged(self):
        self.assertEqual(M.slugify("already-fine"), "already-fine")


class TestBuildFrontMatter(unittest.TestCase):
    def _page(self, title="My Page", created="2024-01-01T00:00:00Z",
              modified="2024-06-01T12:00:00Z"):
        return {"id": "abc123", "title": title,
                "createdDateTime": created, "lastModifiedDateTime": modified}
    def test_contains_title(self):
        self.assertIn('title: "My Page"', M.build_front_matter(self._page(), "NB", "Sec"))
    def test_contains_dates(self):
        fm = M.build_front_matter(self._page(), "NB", "Sec")
        self.assertIn("2024-01-01T00:00:00Z", fm)
        self.assertIn("2024-06-01T12:00:00Z", fm)
    def test_contains_notebook_section(self):
        fm = M.build_front_matter(self._page(), "Beekeeping", "Spring 2024")
        self.assertIn('notebook: "Beekeeping"', fm)
        self.assertIn('section: "Spring 2024"', fm)
    def test_starts_with_triple_dash(self):
        self.assertTrue(M.build_front_matter(self._page(), "NB", "Sec").startswith("---"))
    def test_ends_with_triple_dash(self):
        self.assertIn("---\n", M.build_front_matter(self._page(), "NB", "Sec"))
    def test_quote_escaping(self):
        self.assertIn('\\"hello\\"', M.build_front_matter(self._page(title='Say "hello"'), "NB", "Sec"))
    def test_missing_title_defaults(self):
        self.assertIn('title: "Untitled"', M.build_front_matter(
            {"id": "x", "createdDateTime": "", "lastModifiedDateTime": ""}, "NB", "Sec"))


class TestExtractResourceUrls(unittest.TestCase):
    def test_finds_src_urls(self):
        html = '<img src="https://graph.microsoft.com/v1.0/me/onenote/resources/abc/content">'
        self.assertEqual(len(M.extract_resource_urls(html)), 1)
    def test_finds_href_urls(self):
        html = '<a href="https://graph.microsoft.com/v1.0/me/onenote/resources/xyz/content">f</a>'
        self.assertEqual(len(M.extract_resource_urls(html)), 1)
    def test_ignores_non_graph_urls(self):
        self.assertEqual(M.extract_resource_urls('<img src="https://example.com/image.png">'), [])
    def test_multiple_resources(self):
        html = '<img src="https://graph.microsoft.com/img1"><img src="https://graph.microsoft.com/img2">'
        self.assertEqual(len(M.extract_resource_urls(html)), 2)
    def test_empty_html(self):
        self.assertEqual(M.extract_resource_urls(""), [])


class TestRewriteResourceUrls(unittest.TestCase):
    def test_replaces_src(self):
        url = "https://graph.microsoft.com/v1.0/me/onenote/resources/abc"
        result = M.rewrite_resource_urls(f'<img src="{url}">', {url: "assets/abc.png"})
        self.assertIn('src="assets/abc.png"', result)
        self.assertNotIn("graph.microsoft.com", result)
    def test_unknown_url_unchanged(self):
        url = "https://graph.microsoft.com/unknown"
        self.assertIn(url, M.rewrite_resource_urls(f'<img src="{url}">', {}))
    def test_multiple_replacements(self):
        u1, u2 = "https://graph.microsoft.com/a", "https://graph.microsoft.com/b"
        result = M.rewrite_resource_urls(f'<img src="{u1}"><img src="{u2}">',
                                          {u1: "assets/a.png", u2: "assets/b.png"})
        self.assertIn("assets/a.png", result)
        self.assertIn("assets/b.png", result)


class TestHtmlToMarkdown(unittest.TestCase):
    def test_heading_conversion(self):
        self.assertIn("# Hello", M.html_to_markdown("<h1>Hello</h1>"))
    def test_paragraph(self):
        self.assertIn("Some text", M.html_to_markdown("<p>Some text</p>"))
    def test_bold(self):
        self.assertIn("Bold", M.html_to_markdown("<b>Bold</b>"))
    def test_list(self):
        md = M.html_to_markdown("<ul><li>Item A</li><li>Item B</li></ul>")
        self.assertIn("Item A", md); self.assertIn("Item B", md)
    def test_link(self):
        md = M.html_to_markdown('<a href="https://example.com">Click</a>')
        self.assertIn("https://example.com", md); self.assertIn("Click", md)
    def test_strips_scripts(self):
        md = M.html_to_markdown("<script>alert(1)</script><p>Safe</p>")
        self.assertNotIn("alert", md); self.assertIn("Safe", md)
    def test_image_tag(self):
        self.assertIn("assets/img.png", M.html_to_markdown('<img src="assets/img.png" alt="photo">'))


class TestLocalAssetName(unittest.TestCase):
    def test_extracts_filename(self):
        url = "https://graph.microsoft.com/v1.0/me/onenote/resources/abc/content"
        self.assertEqual(M.local_asset_name(url, 0), "asset-0000.bin")
    def test_extracts_real_filename(self):
        url = "https://graph.microsoft.com/v1.0/me/onenote/resources/abc/photo.png"
        self.assertEqual(M.local_asset_name(url, 0), "photo.png")
    def test_fallback_on_no_extension(self):
        self.assertIn("asset-0003", M.local_asset_name(
            "https://graph.microsoft.com/v1.0/me/onenote/resources/abc", 3))
    def test_sanitises_special_chars(self):
        name = M.local_asset_name("https://graph.microsoft.com/resources/my file (1).png", 0)
        self.assertNotIn(" ", name); self.assertNotIn("(", name)


class TestFormatCommitDate(unittest.TestCase):
    def test_z_becomes_utc_offset(self):
        result = M.format_commit_date("2024-06-01T12:00:00Z")
        self.assertIn("+00:00", result); self.assertNotIn("Z", result)
    def test_strips_milliseconds(self):
        self.assertNotIn(".000", M.format_commit_date("2024-06-01T12:00:00.000Z"))
    def test_already_offset(self):
        self.assertIn("+00:00", M.format_commit_date("2024-06-01T12:00:00+00:00"))
    def test_invalid_falls_back(self):
        result = M.format_commit_date("not-a-date")
        self.assertIsInstance(result, str); self.assertGreater(len(result), 0)


class TestRetryWithBackoff(unittest.TestCase):
    def _ok(self, status=200):
        r = MagicMock(); r.status_code = status; return r
    def test_success_first_try(self):
        fn = MagicMock(return_value=self._ok(200))
        self.assertEqual(M.retry_with_backoff(fn, "url", retries=3, base=0).status_code, 200)
        fn.assert_called_once_with("url")
    @patch("onenote_migrate.time.sleep")
    def test_retries_on_429(self, mock_sleep):
        ok = self._ok(200); throttled = self._ok(429); throttled.headers = {"Retry-After": "0"}
        fn = MagicMock(side_effect=[throttled, throttled, ok])
        self.assertEqual(M.retry_with_backoff(fn, "url", retries=3, base=0).status_code, 200)
        self.assertEqual(fn.call_count, 3)
    @patch("onenote_migrate.time.sleep")
    def test_retries_on_503(self, mock_sleep):
        ok = self._ok(200); err = self._ok(503); err.headers = {}
        fn = MagicMock(side_effect=[err, ok])
        self.assertEqual(M.retry_with_backoff(fn, "url", retries=3, base=0).status_code, 200)
    @patch("onenote_migrate.time.sleep")
    def test_raises_after_max_retries(self, mock_sleep):
        throttled = self._ok(429); throttled.headers = {"Retry-After": "0"}
        throttled.raise_for_status = MagicMock(side_effect=Exception("too many"))
        with self.assertRaises(Exception):
            M.retry_with_backoff(MagicMock(return_value=throttled), "url", retries=2, base=0)
    @patch("onenote_migrate.time.sleep")
    def test_retries_on_network_exception(self, mock_sleep):
        ok = self._ok(200)
        fn = MagicMock(side_effect=[ConnectionError("down"), ok])
        self.assertEqual(M.retry_with_backoff(fn, "url", retries=3, base=0).status_code, 200)


class TestGetAll(unittest.TestCase):
    def _resp(self, value, next_link=None):
        r = MagicMock(); r.status_code = 200; r.raise_for_status = MagicMock()
        data = {"value": value}
        if next_link: data["@odata.nextLink"] = next_link
        r.json.return_value = data; return r
    def test_single_page(self):
        session = MagicMock(); session.get.return_value = self._resp([{"id": "1"}, {"id": "2"}])
        self.assertEqual(len(M.get_all("https://graph.microsoft.com/notebooks", session)), 2)
    def test_follows_next_link(self):
        session = MagicMock()
        session.get.side_effect = [
            self._resp([{"id": "1"}], next_link="https://graph.microsoft.com/page2"),
            self._resp([{"id": "2"}, {"id": "3"}])
        ]
        items = M.get_all("https://graph.microsoft.com/page1", session)
        self.assertEqual(len(items), 3); self.assertEqual(session.get.call_count, 2)
    def test_empty_result(self):
        session = MagicMock(); session.get.return_value = self._resp([])
        self.assertEqual(M.get_all("https://graph.microsoft.com/empty", session), [])


class TestResumeLogic(unittest.TestCase):
    def test_skip_known_id(self):
        self.assertTrue(M.should_skip("abc", {"abc", "def"}))
    def test_no_skip_unknown_id(self):
        self.assertFalse(M.should_skip("xyz", {"abc", "def"}))
    def test_load_migrated_ids_no_git(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(M.load_migrated_ids(Path(tmp)), set())
    def test_load_migrated_ids_from_git_log(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            subprocess.run(["git", "init", str(tmp)], capture_output=True)
            subprocess.run(["git", "-C", str(tmp), "config", "user.email", "t@t.com"], capture_output=True)
            subprocess.run(["git", "-C", str(tmp), "config", "user.name", "T"], capture_output=True)
            (tmp / "dummy.txt").write_text("x")
            subprocess.run(["git", "-C", str(tmp), "add", "."], capture_output=True)
            subprocess.run(["git", "-C", str(tmp), "commit", "-m", "page:PAGE-ID-001 My Note"], capture_output=True)
            self.assertIn("PAGE-ID-001", M.load_migrated_ids(tmp))


class TestMigratePage(unittest.TestCase):
    def _page(self):
        return {"id": "PAGE-123", "title": "Hive Inspection",
                "createdDateTime": "2024-03-01T09:00:00Z",
                "lastModifiedDateTime": "2024-03-15T10:30:00Z"}
    def _mock_session(self, html="<h1>Hive</h1><p>All good.</p>"):
        session = MagicMock()
        r = MagicMock(); r.status_code = 200; r.text = html; r.raise_for_status = MagicMock()
        session.get.return_value = r; return session
    def test_creates_index_md(self):
        with tempfile.TemporaryDirectory() as tmp:
            M.migrate_page(self._page(), Path(tmp)/"p", "NB", "Sec",
                           self._mock_session(), M.Config(), dry_run=False)
            self.assertTrue((Path(tmp)/"p"/"index.md").exists())
    def test_index_md_has_front_matter(self):
        with tempfile.TemporaryDirectory() as tmp:
            M.migrate_page(self._page(), Path(tmp)/"p", "Beekeeping", "Spring",
                           self._mock_session(), M.Config(), dry_run=False)
            content = (Path(tmp)/"p"/"index.md").read_text()
            self.assertIn("title:", content); self.assertIn("Hive Inspection", content)
    def test_index_md_has_body(self):
        with tempfile.TemporaryDirectory() as tmp:
            M.migrate_page(self._page(), Path(tmp)/"p", "NB", "Sec",
                           self._mock_session(), M.Config(), dry_run=False)
            content = (Path(tmp)/"p"/"index.md").read_text()
            self.assertIn("Hive", content); self.assertIn("All good", content)
    def test_dry_run_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            pdir = Path(tmp)/"p"
            written = M.migrate_page(self._page(), pdir, "NB", "Sec",
                                     self._mock_session(), M.Config(), dry_run=True)
            self.assertEqual(written, []); self.assertFalse(pdir.exists())
    def test_returns_list_of_written_paths(self):
        with tempfile.TemporaryDirectory() as tmp:
            written = M.migrate_page(self._page(), Path(tmp)/"p", "NB", "Sec",
                                     self._mock_session(), M.Config(), dry_run=False)
            self.assertGreater(len(written), 0)
            self.assertTrue(any("index.md" in w for w in written))
    def test_downloads_embedded_assets(self):
        url  = "https://graph.microsoft.com/v1.0/me/onenote/resources/img1"
        html = f'<img src="{url}"><p>body</p>'
        with tempfile.TemporaryDirectory() as tmp:
            session = MagicMock()
            hr = MagicMock(); hr.status_code=200; hr.text=html; hr.raise_for_status=MagicMock()
            ir = MagicMock(); ir.status_code=200; ir.content=b"\x89PNG\r\n"; ir.raise_for_status=MagicMock()
            session.get.side_effect = [hr, ir]
            M.migrate_page(self._page(), Path(tmp)/"p", "NB", "Sec", session, M.Config(), dry_run=False)
            self.assertEqual(len(list((Path(tmp)/"p"/"assets").iterdir())), 1)


class TestParseArgs(unittest.TestCase):
    def test_defaults(self):
        args = M.parse_args([])
        self.assertEqual(args.repo, "./onenote-vault"); self.assertFalse(args.dry_run)
    def test_custom_repo(self):
        self.assertEqual(M.parse_args(["--repo", "/tmp/mynotes"]).repo, "/tmp/mynotes")
    def test_dry_run_flag(self):
        self.assertTrue(M.parse_args(["--dry-run"]).dry_run)
    def test_client_id(self):
        self.assertEqual(M.parse_args(["--client-id", "abc-123"]).client_id, "abc-123")


if __name__ == "__main__":
    unittest.main(verbosity=2)
