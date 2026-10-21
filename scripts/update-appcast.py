#!/usr/bin/env python3
"""Adds (or replaces) one release in mypet's Sparkle appcast.

  scripts/update-appcast.py --appcast pages/appcast.xml --version 0.2.0 \
      --url https://github.com/eramitgupta/mypet/releases/download/v0.2.0/MyPet-0.2.0.zip \
      --enclosure 'sparkle:edSignature="…" length="123"' [--changelog CHANGELOG.md]

The enclosure attributes are the exact output of Sparkle's `sign_update` for the archive.
Release notes come from the matching "## [x.y.z]" section of CHANGELOG.md and are embedded
as HTML, which Sparkle's update window displays.

This script only edits XML. Signing the archive and the feed is done with Sparkle's
`sign_update` (see scripts/publish-update.sh), so the feed signature always covers the final file.
"""

import argparse
import email.utils
import html
import re
import sys
from pathlib import Path

REPO = "https://github.com/eramitgupta/mypet"
MIN_SYSTEM = "13.0"

EMPTY_FEED = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>MyPet</title>
    <link>{repo}</link>
    <description>Updates for MyPet, your Mac’s little companion.</description>
    <language>en</language>
  </channel>
</rss>
""".format(repo=REPO)


def release_notes(changelog: Path, version: str) -> str:
    """Markdown section for `version` → small, safe HTML for the update window."""
    if not changelog.exists():
        return f"<p>mypet {html.escape(version)} is available.</p>"
    text = changelog.read_text(encoding="utf-8")
    m = re.search(rf"^## \[?{re.escape(version)}\]?.*?$\n(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not m:
        sys.exit(f"error: no '## [{version}]' section in {changelog}")
    return markdown_to_html(m.group(1).strip())


def inline(s: str) -> str:
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"`(.+?)`", r"<code>\1</code>", s)
    s = re.sub(r"\[(.+?)\]\((https?://[^)\s]+)\)", r'<a href="\2">\1</a>', s)
    return s


def markdown_to_html(md: str) -> str:
    out, in_list = [], False
    for line in md.splitlines():
        line = line.rstrip()
        bullet = re.match(r"^\s*[-*] (.*)", line)
        if bullet:
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(bullet.group(1))}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if not line:
            continue
        heading = re.match(r"^#{3,6} (.*)", line)
        out.append(f"<h3>{inline(heading.group(1))}</h3>" if heading else f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out) or "<p>Bug fixes and improvements.</p>"


def strip_signature(xml: str) -> str:
    """Remove a previous embedded feed signature; sign_update adds a fresh one."""
    xml = re.sub(r"<!--\s*sparkle-signatures:.*?-->\s*", "", xml, flags=re.S)
    xml = re.sub(r"<!--\s*sparkle-sign-warning:.*?-->", "", xml, flags=re.S)
    return xml


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--appcast", required=True, type=Path)
    p.add_argument("--version", required=True)
    p.add_argument("--url", required=True, help="download URL of the update archive (.zip)")
    p.add_argument("--enclosure", required=True, help='sign_update output: sparkle:edSignature="…" length="…"')
    p.add_argument("--changelog", type=Path, default=Path(__file__).resolve().parent.parent / "CHANGELOG.md")
    a = p.parse_args()

    if not re.fullmatch(r"\d+(\.\d+){1,3}", a.version):
        sys.exit(f"error: version must look like 1.2.3, got {a.version!r}")
    sig = re.search(r'sparkle:edSignature="([A-Za-z0-9+/=]+)"', a.enclosure)
    length = re.search(r'length="(\d+)"', a.enclosure)
    if not (sig and length):
        sys.exit("error: --enclosure must contain sparkle:edSignature=\"…\" and length=\"…\"")
    if not a.url.startswith("https://") and not a.url.startswith("http://127.0.0.1"):
        sys.exit("error: update URL must be https")

    xml = strip_signature(a.appcast.read_text(encoding="utf-8")) if a.appcast.exists() else EMPTY_FEED

    v = html.escape(a.version)
    item = f"""    <item>
      <title>Version {v}</title>
      <pubDate>{email.utils.formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{v}</sparkle:version>
      <sparkle:shortVersionString>{v}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MIN_SYSTEM}</sparkle:minimumSystemVersion>
      <link>{REPO}/releases/tag/v{v}</link>
      <description><![CDATA[
{release_notes(a.changelog, a.version)}
      ]]></description>
      <enclosure url="{html.escape(a.url)}" length="{length.group(1)}" type="application/octet-stream" sparkle:edSignature="{sig.group(1)}"/>
    </item>
"""
    # Replace an existing entry for this version (a re-run of the same release), else prepend.
    existing = re.compile(rf"\s*<item>(?:(?!</item>).)*?<sparkle:version>{re.escape(v)}</sparkle:version>.*?</item>\n?", re.S)
    xml = existing.sub("\n", xml)
    anchor = re.search(r"<language>.*?</language>\n", xml) or re.search(r"<channel>\n", xml)
    if not anchor:
        sys.exit("error: appcast has no <channel>")
    xml = xml[: anchor.end()] + item + xml[anchor.end():]
    xml = re.sub(r"\n{3,}", "\n\n", xml)
    a.appcast.parent.mkdir(parents=True, exist_ok=True)
    a.appcast.write_text(xml, encoding="utf-8")
    print(f"✓ {a.appcast}: version {a.version} → {a.url}")


if __name__ == "__main__":
    main()
