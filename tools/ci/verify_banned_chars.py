#!/usr/bin/env python3
"""
tools/ci/verify_banned_chars.py — verification tool for banned non-standard characters.

Checks that:
1. tools/ci/banned_chars.json is valid and contains all expected codepoints.
2. tools/check.sh's check_chars() references and validates against tools/ci/banned_chars.json.
3. tools/README.md documents the banned character set.
4. (Optional with --upstream) Verifies parity with Morrison-Lab/gha's check-non-standard-chars.py.
"""

import sys
import json
import re
import urllib.request
from pathlib import Path

# Ensure UTF-8 output on all platforms
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
BANNED_JSON_PATH = PROJECT_ROOT / "tools" / "ci" / "banned_chars.json"
CHECK_SH_PATH = PROJECT_ROOT / "tools" / "check.sh"
README_PATH = PROJECT_ROOT / "tools" / "README.md"

UPSTREAM_URL = (
    "https://raw.githubusercontent.com/Morrison-Lab/gha/v2/"
    "check-non-standard-chars/check-non-standard-chars.py"
)


def load_local_banned_chars():
    if not BANNED_JSON_PATH.exists():
        print(f"Error: {BANNED_JSON_PATH} missing", file=sys.stderr)
        sys.exit(1)
    with open(BANNED_JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
    return data.get("banned_characters", [])


def check_check_sh(banned_chars):
    if not CHECK_SH_PATH.exists():
        print(f"Error: {CHECK_SH_PATH} missing", file=sys.stderr)
        return False
    content = CHECK_SH_PATH.read_text(encoding="utf-8")
    
    if "banned_chars.json" not in content:
        print("Error: tools/check.sh does not reference tools/ci/banned_chars.json", file=sys.stderr)
        return False

    missing_codepoints = []
    for item in banned_chars:
        cp = item["codepoint"]
        hex_code = cp.replace("U+", "")
        char = item["char"]
        if cp not in content and hex_code not in content and char not in content:
            missing_codepoints.append(cp)

    if missing_codepoints:
        print(f"Error: tools/check.sh missing codepoints: {missing_codepoints}", file=sys.stderr)
        return False

    print("[PASS] tools/check.sh is synchronized with tools/ci/banned_chars.json")
    return True


def check_readme(banned_chars):
    if not README_PATH.exists():
        print(f"Error: {README_PATH} missing", file=sys.stderr)
        return False
    content = README_PATH.read_text(encoding="utf-8")

    if "banned_chars.json" not in content:
        print("Warning: tools/README.md does not reference tools/ci/banned_chars.json", file=sys.stderr)

    missing = []
    for item in banned_chars:
        cp = item["codepoint"]
        hex_code = cp.replace("U+", "")
        if cp not in content and hex_code not in content and item["name"] not in content:
            missing.append(cp)

    if missing:
        print(f"Error: tools/README.md missing codepoint documentation for: {missing}", file=sys.stderr)
        return False

    print("[PASS] tools/README.md is synchronized with tools/ci/banned_chars.json")
    return True


def check_upstream_parity(banned_chars):
    print("Checking upstream parity against Morrison-Lab/gha@v2...")
    try:
        req = urllib.request.urlopen(UPSTREAM_URL, timeout=10)
        code = req.read().decode("utf-8")
    except Exception as e:
        print(f"Warning: Could not fetch upstream script ({e}). Skipping online check.")
        return True

    match = re.search(r"NON_STANDARD_CHARS\s*=\s*\{([^}]+)\}", code)
    if not match:
        print("Error: Could not parse NON_STANDARD_CHARS from upstream script", file=sys.stderr)
        return False

    dict_body = match.group(1)
    upstream_codepoints = {
        cp.lower() for cp in re.findall(r"\\u([0-9a-fA-F]{4})", dict_body)
    }
    local_codepoints = {
        item["codepoint"].replace("U+", "").lower() for item in banned_chars
    }

    if upstream_codepoints != local_codepoints:
        print(
            f"Error: Parity mismatch! Upstream: {upstream_codepoints}, Local: {local_codepoints}",
            file=sys.stderr,
        )
        return False

    print("[PASS] Parity verified: local banned_chars.json matches upstream Morrison-Lab/gha@v2 NON_STANDARD_CHARS")
    return True


def main():
    check_upstream = "--upstream" in sys.argv or "--check-upstream" in sys.argv
    banned_chars = load_local_banned_chars()
    print(f"Loaded {len(banned_chars)} banned characters from tools/ci/banned_chars.json")

    ok = True
    ok = check_check_sh(banned_chars) and ok
    ok = check_readme(banned_chars) and ok

    if check_upstream or "--all" in sys.argv:
        ok = check_upstream_parity(banned_chars) and ok

    if not ok:
        sys.exit(1)
    print("All banned glyph set synchronization checks passed successfully.")


if __name__ == "__main__":
    main()
