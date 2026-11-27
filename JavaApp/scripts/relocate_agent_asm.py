#!/usr/bin/env python3
"""Give the embedded ASM copy a namespace private to the launcher agent."""

from pathlib import Path
import sys

root = Path(sys.argv[1])
# Equal length replacements preserve JVM constant pool UTF-8 lengths.
replacements = (
    (b"org/objectweb/asm", b"ame/objectweb/asm"),
    (b"org.objectweb.asm", b"ame.objectweb.asm"),
)
for path in root.rglob("*.class"):
    original = path.read_bytes()
    rewritten = original
    for old, new in replacements:
        rewritten = rewritten.replace(old, new)
    if rewritten != original:
        path.write_bytes(rewritten)

source = root / "org/objectweb/asm"
target = root / "ame/objectweb/asm"
target.parent.mkdir(parents=True, exist_ok=True)
source.rename(target)
