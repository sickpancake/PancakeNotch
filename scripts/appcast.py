#!/usr/bin/env python3
"""Adds a release to Sparkle's update feed (appcast.xml), keeping the older releases.

Usage:
  scripts/appcast.py --out appcast.xml [--existing old.xml] --version 0.1.0 --build 42 \
      --url https://…/PancakeNotch.zip --length 123 --signature BASE64 [--notes notes.md]

The release notes are a short Markdown list (from CHANGELOG.md); they're turned into the small bit
of HTML Sparkle's update window shows. Only the standard library is used.
"""
import argparse
import email.utils
import html
import re
import sys
import xml.etree.ElementTree as ET

SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
DC = "http://purl.org/dc/elements/1.1/"
FEED_TITLE = "PancakeNotch"
FEED_LINK = "https://sickpancake.github.io/PancakeNotch/"
MIN_SYSTEM = "15.0"
KEEP = 10

ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", DC)


def notes_html(markdown: str) -> str:
    """Bullets become a list, other lines paragraphs; **bold** and `code` are kept."""
    def inline(text: str) -> str:
        text = html.escape(text)
        text = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", text)
        return re.sub(r"`(.+?)`", r"<code>\1</code>", text)

    parts, items = [], []
    for line in markdown.splitlines():
        line = line.strip()
        if line.startswith(("- ", "* ")):
            items.append(f"<li>{inline(line[2:])}</li>")
            continue
        if items:
            parts.append("<ul>" + "".join(items) + "</ul>")
            items = []
        if line and not line.startswith("#"):
            parts.append(f"<p>{inline(line)}</p>")
    if items:
        parts.append("<ul>" + "".join(items) + "</ul>")
    return "".join(parts) or "<p>Bug fixes and improvements.</p>"


def new_feed() -> ET.Element:
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = FEED_TITLE
    ET.SubElement(channel, "link").text = FEED_LINK
    ET.SubElement(channel, "description").text = "Updates for PancakeNotch."
    ET.SubElement(channel, "language").text = "en"
    return rss


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", required=True)
    parser.add_argument("--existing")
    parser.add_argument("--version", required=True)
    parser.add_argument("--build", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--notes")
    args = parser.parse_args()

    if not args.build.isdigit():
        sys.exit("--build must be a number (Sparkle compares it).")

    rss = ET.parse(args.existing).getroot() if args.existing else new_feed()
    channel = rss.find("channel")
    if channel is None:
        sys.exit("The existing appcast has no <channel>.")

    # A rebuilt release replaces its earlier entry; a lower build number than the newest is a mistake.
    items = channel.findall("item")
    for item in items:
        build = item.findtext(f"{{{SPARKLE}}}version", "")
        if build == args.build:
            channel.remove(item)
        elif build.isdigit() and int(build) > int(args.build):
            sys.exit(f"The feed already has a newer build ({build}) than {args.build}.")

    notes = open(args.notes, encoding="utf-8").read() if args.notes else ""
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Version {args.version}"
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = args.build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = args.version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = MIN_SYSTEM
    ET.SubElement(item, "description").text = notes_html(notes)
    ET.SubElement(item, "enclosure", {
        "url": args.url,
        "length": args.length,
        "type": "application/octet-stream",
        f"{{{SPARKLE}}}edSignature": args.signature,
    })

    # Newest first, after the channel's own fields.
    first_item = next((index for index, child in enumerate(channel) if child.tag == "item"), len(channel))
    channel.insert(first_item, item)
    for old in channel.findall("item")[KEEP:]:
        channel.remove(old)

    ET.indent(rss, space="  ")
    ET.ElementTree(rss).write(args.out, encoding="utf-8", xml_declaration=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
