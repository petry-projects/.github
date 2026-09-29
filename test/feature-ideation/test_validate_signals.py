#!/usr/bin/env python3
"""Unit tests for validate-signals.py."""

import sys
from pathlib import Path
from datetime import datetime

# Add the script directory to the path so we can import validate_signals
# This allows the test to import the validate-signals.py module
repo_root = Path(__file__).resolve().parent.parent.parent
script_dir = repo_root / ".github" / "scripts" / "feature-ideation"
sys.path.insert(0, str(script_dir))

import pytest

# Import the function under test
from validate_signals import _check_date_time


class TestCheckDateTime:
    """Tests for the _check_date_time format checker."""

    def test_valid_iso8601_uppercase_t_z(self):
        """Valid ISO-8601 with uppercase T and Z."""
        assert _check_date_time("2026-09-29T12:34:56Z") is True

    def test_valid_iso8601_uppercase_t_offset(self):
        """Valid ISO-8601 with uppercase T and numeric offset."""
        assert _check_date_time("2026-09-29T12:34:56+00:00") is True

    def test_valid_iso8601_lowercase_t_uppercase_z(self):
        """Valid RFC-3339 with lowercase t and uppercase Z."""
        assert _check_date_time("2026-09-29t12:34:56Z") is True

    def test_valid_iso8601_lowercase_t_lowercase_z(self):
        """Valid RFC-3339 with lowercase t and z."""
        assert _check_date_time("2026-09-29t12:34:56z") is True

    def test_valid_iso8601_lowercase_t_offset(self):
        """Valid RFC-3339 with lowercase t and numeric offset."""
        assert _check_date_time("2026-09-29t12:34:56+00:00") is True

    def test_valid_with_seconds_and_microseconds(self):
        """Valid ISO-8601 with microseconds."""
        assert _check_date_time("2026-09-29T12:34:56.123456Z") is True

    def test_valid_without_seconds(self):
        """Valid ISO-8601 with only hour and minute."""
        assert _check_date_time("2026-09-29T12:34Z") is True

    def test_non_string_returns_true(self):
        """Non-string inputs are delegated to type keyword and return True."""
        assert _check_date_time(12345) is True
        assert _check_date_time(None) is True
        assert _check_date_time({"date": "value"}) is True

    def test_invalid_date_format_raises_value_error(self):
        """Invalid date-time string raises ValueError."""
        with pytest.raises(ValueError, match="not an ISO-8601 date-time"):
            _check_date_time("not-a-date")

    def test_invalid_missing_time_raises_value_error(self):
        """Date without time raises ValueError."""
        with pytest.raises(ValueError, match="not an ISO-8601 date-time"):
            _check_date_time("2026-09-29")

    def test_invalid_wrong_separator_raises_value_error(self):
        """Wrong date-time separator raises ValueError."""
        with pytest.raises(ValueError, match="not an ISO-8601 date-time"):
            _check_date_time("2026-09-29 12:34:56Z")

    def test_invalid_malformed_time_raises_value_error(self):
        """Malformed time component raises ValueError."""
        with pytest.raises(ValueError):
            _check_date_time("2026-09-29T25:99:99Z")

    def test_invalid_partial_date_raises_value_error(self):
        """Incomplete date raises ValueError."""
        with pytest.raises(ValueError, match="not an ISO-8601 date-time"):
            _check_date_time("2026-09T12:34:56Z")

    def test_february_29_leap_year(self):
        """Valid leap year date-time."""
        assert _check_date_time("2024-02-29T12:34:56Z") is True

    def test_february_29_non_leap_year_raises_value_error(self):
        """Invalid non-leap year Feb 29 raises ValueError."""
        with pytest.raises(ValueError):
            _check_date_time("2025-02-29T12:34:56Z")
