#!/usr/bin/env python3
"""Confirm a temporary Xcode checkout contains the exact app/core build inputs."""
import hashlib
import pathlib
import sys

source = pathlib.Path(__file__).resolve().parents[1]
staged = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/private/tmp/LiltBuild")
roots = [source / "App", source / "Sources", source / "Lilt.xcodeproj"]
files = [source / "Package.swift", source / "project.yml"]
for root in roots:
    files.extend(path for path in root.rglob("*") if path.is_file() and "xcuserdata" not in path.parts)
mismatches = []
for path in files:
    relative = path.relative_to(source)
    copy = staged / relative
    if not copy.is_file() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(copy.read_bytes()).digest():
        mismatches.append(str(relative))
if mismatches:
    print("Source parity failed: " + ", ".join(mismatches))
    raise SystemExit(1)
print(f"Source parity passed for {len(files)} build input files.")
