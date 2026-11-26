#!/usr/bin/env python3
"""Copy Java 25 multi-release entries from a set of LWJGL module JARs."""

from pathlib import Path
import shutil
import sys
import zipfile


source_dir = Path(sys.argv[1])
destination = Path(sys.argv[2])
prefix = "META-INF/versions/25/"

for jar_path in sorted(source_dir.glob("lwjgl*.jar")):
    with zipfile.ZipFile(jar_path) as archive:
        for entry in archive.infolist():
            if not entry.filename.startswith(prefix) or entry.is_dir():
                continue
            # LWJGL 3.4.1's Java 25 MemoryUtil drops Unsafe, while its Java 11
            # MultiReleaseTextDecoding implementation still links that field.
            # Keep the base MemoryUtil until the matching native/runtime stack
            # can move to a release where these replacements are consistent.
            relative = entry.filename.removeprefix(prefix)
            if relative == "org/lwjgl/system/MemoryUtil.class" or relative.startswith("org/lwjgl/system/MemoryUtil$"):
                continue
            output = destination / entry.filename
            output.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(entry) as source, output.open("wb") as target:
                shutil.copyfileobj(source, target)
