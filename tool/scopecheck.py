#!/usr/bin/env python3
"""
A stand-in for `flutter analyze`.

This sandbox cannot download the Flutter SDK, so the real analyser has
never run against this tree. This script covers the failure mode that
actually bites: a type or widget used in a file that never imports it.
It is deliberately conservative — it reports a name only when it is
declared *somewhere in this project* and not reachable from the file
using it, so an unknown SDK symbol never produces noise.

It also checks the mechanical things a compiler would: part/part-of
pairing, imports that point at files which do not exist, and duplicate
top-level declarations.
"""

from __future__ import annotations

import os
import re
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIB = os.path.join(ROOT, "lib")

DECL = re.compile(
    r"^\s*(?:abstract\s+|final\s+|base\s+|interface\s+|sealed\s+|mixin\s+)*"
    r"(?:class|mixin|enum|extension|typedef)\s+([A-Z_$][A-Za-z0-9_$]*)",
    re.M,
)
IMPORT = re.compile(r"""^\s*import\s+['"]([^'"]+)['"]([^;]*);""", re.M)
EXPORT = re.compile(r"""^\s*export\s+['"]([^'"]+)['"]""", re.M)
PART = re.compile(r"""^\s*part\s+['"]([^'"]+)['"]\s*;""", re.M)
PART_OF = re.compile(r"""^\s*part\s+of\s+['"]([^'"]+)['"]\s*;""", re.M)
SHOW = re.compile(r"\bshow\s+([A-Za-z0-9_$,\s]+)")
# The negative lookbehind on '.' matters: `ckit.CallEvent` is a reference
# to the prefixed import, not to a same-named class in this project.
IDENT = re.compile(r"(?<![\w.$])([A-Z][A-Za-z0-9_$]*)\b")


def strip_code(src: str) -> str:
    """Remove comments and string bodies so they cannot fake a reference."""
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"^\s*///.*$", " ", src, flags=re.M)
    src = re.sub(r"//.*$", " ", src, flags=re.M)
    src = re.sub(r"r?'''.*?'''", "''", src, flags=re.S)
    src = re.sub(r'r?""".*?"""', "''", src, flags=re.S)
    # Keep ${...} interpolations — they contain real references.
    src = re.sub(r"r'[^'\n]*'", "''", src)
    src = re.sub(r'r"[^"\n]*"', "''", src)
    return src


def dart_files() -> list[str]:
    out = []
    for base, _dirs, files in os.walk(LIB):
        for f in files:
            if f.endswith(".dart"):
                out.append(os.path.join(base, f))
    return sorted(out)


def main() -> int:
    files = dart_files()
    src: dict[str, str] = {}
    clean: dict[str, str] = {}
    for path in files:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
        src[path] = raw
        clean[path] = strip_code(raw)

    errors: list[str] = []
    warnings: list[str] = []

    # ---------------------------------------------------------------- decls
    declared_in: dict[str, set[str]] = defaultdict(set)   # file -> names
    owner: dict[str, list[str]] = defaultdict(list)        # name -> files
    for path in files:
        for name in DECL.findall(clean[path]):
            declared_in[path].add(name)
            owner[name].append(path)

    for name, paths in sorted(owner.items()):
        if len(paths) > 1:
            rel = ", ".join(os.path.relpath(p, ROOT) for p in paths)
            warnings.append(f"'{name}' declared in {len(paths)} files: {rel}")

    # ---------------------------------------------------------- parts/library
    parts_of: dict[str, str] = {}       # part file -> owning library file
    part_list: dict[str, set[str]] = defaultdict(set)  # library -> part files
    for path in files:
        for target in PART.findall(clean[path]):
            if PART_OF.search(clean[path]):
                continue  # 'part of' matched by PART too; skip
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
            if not os.path.exists(resolved):
                errors.append(
                    f"{os.path.relpath(path, ROOT)}: part '{target}' does not exist"
                )
                continue
            part_list[path].add(resolved)
            parts_of[resolved] = path

    for path in files:
        m = PART_OF.search(clean[path])
        if not m:
            continue
        target = m.group(1)
        resolved = os.path.normpath(os.path.join(os.path.dirname(path), target))
        if not os.path.exists(resolved):
            errors.append(
                f"{os.path.relpath(path, ROOT)}: 'part of {target}' points nowhere"
            )
        elif path not in part_list.get(resolved, set()):
            errors.append(
                f"{os.path.relpath(path, ROOT)}: is 'part of' "
                f"{os.path.relpath(resolved, ROOT)}, which does not declare it"
            )

    # ------------------------------------------------------------- imports
    def resolve(path: str, uri: str) -> str | None:
        if uri.startswith("package:fitness_app/"):
            return os.path.normpath(
                os.path.join(LIB, uri[len("package:fitness_app/"):])
            )
        if uri.startswith("dart:") or uri.startswith("package:"):
            return None
        return os.path.normpath(os.path.join(os.path.dirname(path), uri))

    # name -> reachable set, per file
    visible: dict[str, set[str]] = {}
    for path in files:
        # A part file sees everything its library sees.
        anchor = parts_of.get(path, path)
        names: set[str] = set(declared_in[anchor])
        for p in part_list.get(anchor, set()):
            names |= declared_in[p]

        for uri, tail in IMPORT.findall(clean[anchor]):
            target = resolve(anchor, uri)
            if target is None:
                continue
            if not os.path.exists(target):
                errors.append(
                    f"{os.path.relpath(anchor, ROOT)}: imports '{uri}', "
                    f"which does not exist"
                )
                continue
            show = SHOW.search(tail)
            exposed = set(declared_in[target])
            for p in part_list.get(target, set()):
                exposed |= declared_in[p]
            # One level of re-export is enough for this tree.
            for ex in EXPORT.findall(clean[target]):
                ex_target = resolve(target, ex)
                if ex_target and os.path.exists(ex_target):
                    exposed |= declared_in[ex_target]
            if show:
                wanted = {s.strip() for s in show.group(1).split(",") if s.strip()}
                exposed &= wanted
            names |= exposed

        visible[path] = names

    # --------------------------------------------------------------- usage
    project_names = set(owner)
    for path in files:
        body = clean[path]
        # Drop the directive block so `import 'x.dart' as y;` is not a usage.
        body = re.sub(r"^\s*(import|export|part)\s+[^;]*;", " ", body, flags=re.M)
        used = set(IDENT.findall(body))
        anchor = parts_of.get(path, path)
        own = set(declared_in[path]) | set(declared_in[anchor])
        for p in part_list.get(anchor, set()):
            own |= declared_in[p]
        for name in sorted(used & project_names):
            if name in own or name in visible[path]:
                continue
            errors.append(
                f"{os.path.relpath(path, ROOT)}: uses '{name}' "
                f"(declared in {os.path.relpath(owner[name][0], ROOT)}) "
                f"but does not import it"
            )

    # -------------------------------------------------------------- report
    for w in warnings:
        print(f"  warn  {w}")
    for e in errors:
        print(f"  ERROR {e}")

    print(
        f"\n{len(files)} files, {len(project_names)} top-level declarations, "
        f"{len(errors)} errors, {len(warnings)} warnings"
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
