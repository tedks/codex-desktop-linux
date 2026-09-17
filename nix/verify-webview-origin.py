#!/usr/bin/env python3
"""Verify that the launcher's local webview server is serving the Codex app."""

import sys
import urllib.request


ACCEPTED_TITLES = ("<title>Codex</title>", "<title>ChatGPT</title>")
REQUIRED_MARKERS = ("startup-loader",)


def main() -> None:
    url = sys.argv[1]
    with urllib.request.urlopen(url, timeout=2) as response:
        body = response.read(8192).decode("utf-8", "ignore")

    missing = [marker for marker in REQUIRED_MARKERS if marker not in body]
    if not any(title in body for title in ACCEPTED_TITLES):
        missing.append("an accepted app title")
    if missing:
        raise SystemExit(
            f"Webview origin validation failed for {url}; "
            f"missing markers: {', '.join(missing)}"
        )


if __name__ == "__main__":
    main()
