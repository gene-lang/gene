#!/usr/bin/env python3
"""Source assertions for explicit interception install/toggle invariants.

This test intentionally complements black-box expected-output fixtures.  It pins
that class interception installation is the only path that mutates class method
metadata, while definition/application toggles remain constant-time field writes.
"""

from pathlib import Path
import re
import sys


REPO_ROOT = Path(__file__).resolve().parents[2]
ASPECTS = REPO_ROOT / "src/gene/stdlib/aspects.nim"
TYPE_DEFS = REPO_ROOT / "src/gene/types/type_defs.nim"
CLASS_FIXTURE = REPO_ROOT / "testsuite/07-oop/oop/12_interceptor_enablement.gene"
FUNCTION_FIXTURE = REPO_ROOT / "testsuite/05-functions/functions/16_fn_interceptor_enablement.gene"


FAILURES: list[str] = []
PASSES: list[str] = []


def read_tracked_source(path: Path) -> str:
    """Read a repository source/fixture path; never inspects local-only artifacts."""
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        FAILURES.append(f"missing required tracked source file: {path.relative_to(REPO_ROOT)}")
        return ""


def extract_proc(source: str, proc_name: str) -> str:
    pattern = re.compile(rf"^proc\s+{re.escape(proc_name)}\b.*?(?=^proc\s+|\Z)", re.MULTILINE | re.DOTALL)
    match = pattern.search(source)
    if not match:
        FAILURES.append(f"missing proc {proc_name}")
        return ""
    return match.group(0)


def check(condition: bool, message: str) -> None:
    if condition:
        PASSES.append(message)
    else:
        FAILURES.append(message)


def check_contains(body: str, needle: str, context: str) -> None:
    check(needle in body, f"{context}: expected `{needle}`")


def check_absent(body: str, forbidden: list[str], context: str) -> None:
    for needle in forbidden:
        check(needle not in body, f"{context}: must not contain `{needle}`")


def check_order(body: str, needles: list[str], context: str) -> None:
    positions = []
    for needle in needles:
        pos = body.find(needle)
        check(pos >= 0, f"{context}: expected `{needle}`")
        positions.append(pos)
    if all(pos >= 0 for pos in positions):
        check(positions == sorted(positions), f"{context}: expected order {' -> '.join(needles)}")


def main() -> int:
    aspects = read_tracked_source(ASPECTS)
    type_defs = read_tracked_source(TYPE_DEFS)
    class_fixture = read_tracked_source(CLASS_FIXTURE)
    function_fixture = read_tracked_source(FUNCTION_FIXTURE)

    apply_class = extract_proc(aspects, "apply_aspect_to_class")
    aspect_toggle = extract_proc(aspects, "aspect_set_enabled")
    interception_toggle = extract_proc(aspects, "interception_set_active")
    legacy_interception_toggle = extract_proc(aspects, "aspect_set_interception_active")

    # Install invariants: class interception installation owns method table mutation
    # and invalidates both class.version and runtime_type.methods.
    check_contains(
        apply_class,
        "let interception_val = create_interception_value(original_method.callable, self, param_name)",
        "apply_aspect_to_class install",
    )
    check_order(
        apply_class,
        [
            "class.methods[method_key].callable = interception_val",
            "class.version.inc()",
            "if class.runtime_type != nil:",
            "class.runtime_type.methods[method_key] = interception_val",
        ],
        "apply_aspect_to_class install invalidation",
    )

    # Cheap toggle invariants: direct Aspect and Interception slash toggles are field
    # assignments only. They must not reinstall wrappers, rewrite method tables, or
    # invalidate runtime method caches.
    toggle_forbidden = [
        "class.methods",
        "runtime_type.methods",
        "class.version",
        "create_interception_value",
        "apply_aspect_to_class",
        "apply_aspect_to_function",
    ]
    check_contains(aspect_toggle, "self.ref.aspect.enabled = enabled", "aspect_set_enabled")
    check_absent(aspect_toggle, toggle_forbidden, "aspect_set_enabled")

    check_contains(interception_toggle, "self.ref.interception.active = active", "interception_set_active")
    check_absent(interception_toggle, toggle_forbidden, "interception_set_active")

    check_contains(
        legacy_interception_toggle,
        "interception_val.ref.interception.active = active",
        "aspect_set_interception_active",
    )
    check_absent(legacy_interception_toggle, toggle_forbidden, "aspect_set_interception_active")

    # Type-surface invariants backing the toggles and inspection surface.
    check_contains(type_defs, "interception_class*: Value", "Application stores Interception class")
    check_contains(type_defs, "active*: bool", "Interception stores application enablement")
    check_contains(type_defs, "enabled*: bool", "Aspect stores definition enablement")

    # Fixture smoke assertions keep this diagnostic tied to the S03 behavior tests
    # without depending on local-only .gsd artifacts.
    check_contains(class_fixture, "class_app/.disable", "class enablement fixture exercises application disable")
    check_contains(class_fixture, "ClassGate/.disable", "class enablement fixture exercises definition disable")
    check_contains(function_fixture, "fn_wrap/.disable", "function enablement fixture exercises application disable")
    check_contains(function_fixture, "FnGate/.disable", "function enablement fixture exercises definition disable")

    if FAILURES:
        print("interception toggle source assertions FAILED")
        for failure in FAILURES:
            print(f"FAIL: {failure}")
        return 1

    print(f"interception toggle source assertions passed ({len(PASSES)} checks)")
    for passed in PASSES:
        print(f"PASS: {passed}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
