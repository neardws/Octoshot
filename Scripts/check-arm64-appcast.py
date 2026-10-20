#!/usr/bin/env python3
import sys
import xml.etree.ElementTree as ET


def check_appcast(path):
    namespace = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
    items = ET.parse(path).findall("./channel/item")
    downloads = [item for item in items if item.find("enclosure") is not None]
    if not downloads:
        raise ValueError("No release enclosures found")
    for item in downloads:
        requirements = item.findtext("sparkle:hardwareRequirements", "", namespace)
        if "arm64" not in {value.strip().lower() for value in requirements.split(",")}:
            raise ValueError("Release enclosure lacks sparkle:hardwareRequirements arm64; do not publish to Intel clients")


if __name__ == "__main__":
    check_appcast(sys.argv[1])
