#!/usr/bin/python3
"""Splits the UI test classes into balanced shards (used by app/test-all.sh with TAGWERK_UI_SHARD and by the CI workflow).

The classes come from the sources of the UI test target (every class with at least one `func test...()`, own or inherited),
so a new test class lands in a shard without any list being edited. The weights are measured durations in seconds from
app/TagwerkUITests/ui-test-durations.txt (`ClassName seconds`, comments start with #); a class without an entry gets the mean
weight of the listed ones and is reported on stderr. The classes are distributed with the longest-processing-time rule
(heaviest class first, each to the shard with the smallest total so far; ties go to the lower shard number), which is
deterministic: every shard computes the same plan from the same checkout and takes its own part.

  ui-test-shards.py shard I/N [options]   prints the classes of shard I of N, one per line
  ui-test-shards.py plan N [options]      prints every shard with its classes and the sum of its weights
  ui-test-shards.py others I/N [options]  prints the classes of all shards except I, one per line

The last shard can be run as the complement of the others (`-skip-testing` for `others`): a class that the source scan above does not
see then still runs, in the last shard, instead of being left out of every shard (app/test-all.sh does that).

Options:
  --tests-dir DIR          folder of the UI test sources (default: app/TagwerkUITests next to this script's repository)
  --durations FILE         weights file (default: ui-test-durations.txt in the tests folder)
  --nightly-only-file FILE list of tests that the pull request set skips (default: nightly-only.txt in the tests folder)
  --set pr|full            "pr": classes whose tests are all listed in the nightly-only file are left out (default: full)
"""
import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# `final class A: Base`, with attributes and access modifiers in front (`@MainActor public final class A: Base`).
CLASS_DECLARATION = re.compile(r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:(?:public|open|internal|private|fileprivate|final)\s+)*class\s+(\w+)\s*:\s*(\w+)")
# `extension A {` adds test methods to a class declared elsewhere.
EXTENSION_DECLARATION = re.compile(r"^\s*(?:@\w+\s+)*(?:(?:public|internal|private|fileprivate)\s+)?extension\s+(\w+)\b")
TEST_FUNCTION = re.compile(r"\bfunc\s+(test\w*)\s*\(")
IDENTIFIER = re.compile(r"^[A-Za-z0-9_]+(/[A-Za-z0-9_]+)?$")


def read_classes(tests_dir):
    """Returns {class name: sorted test method names} including inherited tests."""
    own, parent = {}, {}
    for source in sorted(Path(tests_dir).glob("*.swift")):
        current = None
        for line in source.read_text(errors="replace").splitlines():
            declaration = CLASS_DECLARATION.match(line)
            if declaration:
                current = declaration.group(1)
                parent[current] = declaration.group(2)
                own.setdefault(current, [])
                continue
            extension = EXTENSION_DECLARATION.match(line)
            if extension:
                current = extension.group(1)
                own.setdefault(current, [])
                continue
            function = TEST_FUNCTION.search(line)
            if function and current:
                own[current].append(function.group(1))

    def all_tests(name, seen=()):
        if name not in own or name in seen:
            return []
        return own[name] + all_tests(parent.get(name, ""), seen + (name,))

    result = {name: sorted(set(all_tests(name))) for name in own}
    return {name: tests for name, tests in result.items() if tests}


def read_entries(path):
    """Entries (`Class` or `Class/method`) of a list file; empty when the file does not exist."""
    entries = []
    if not path or not Path(path).is_file():
        return entries
    for line in Path(path).read_text().splitlines():
        entry = re.sub(r"\s+", "", line)
        if not entry or entry.startswith("#"):
            continue
        if not IDENTIFIER.match(entry):
            raise ValueError(f'invalid entry "{entry}" in {path} (expected Class or Class/method)')
        entries.append(entry)
    return entries


def read_durations(path):
    durations = {}
    if not path or not Path(path).is_file():
        return durations
    for number, line in enumerate(Path(path).read_text().splitlines(), start=1):
        text = line.split("#", 1)[0].strip()
        if not text:
            continue
        parts = text.split()
        if len(parts) != 2 or not re.match(r"^\d+(\.\d+)?$", parts[1]):
            raise ValueError(f"{path}:{number}: expected `ClassName seconds`, got `{line}`")
        durations[parts[0]] = float(parts[1])
    return durations


def selected_classes(classes, test_set, nightly_entries):
    """Classes of the set: with "pr" those whose tests are all skipped by the nightly-only entries are left out."""
    if test_set != "pr":
        return dict(classes)
    selected = {}
    for name, tests in classes.items():
        remaining = [test for test in tests if name not in nightly_entries and f"{name}/{test}" not in nightly_entries]
        if remaining:
            selected[name] = remaining
    return selected


def weights_for(names, durations):
    """Weight per class; classes without an entry get the mean of the listed ones (60 s when nothing is listed)."""
    listed = [durations[name] for name in names if name in durations]
    default = sum(listed) / len(listed) if listed else 60.0
    return {name: durations.get(name, default) for name in names}, [name for name in names if name not in durations]


def partition(weights, shard_count):
    """Longest-processing-time distribution. Returns a list of shard_count lists of class names."""
    shards = [[] for _ in range(shard_count)]
    totals = [0.0] * shard_count
    for name in sorted(weights, key=lambda item: (-weights[item], item)):
        index = min(range(shard_count), key=lambda candidate: (totals[candidate], candidate))
        shards[index].append(name)
        totals[index] += weights[name]
    return [sorted(shard) for shard in shards]


def build_plan(tests_dir, durations_file, nightly_file, test_set, shard_count):
    tests_dir = Path(tests_dir)
    classes = selected_classes(read_classes(tests_dir), test_set, read_entries(nightly_file))
    weights, unlisted = weights_for(sorted(classes), read_durations(durations_file))
    return partition(weights, shard_count), weights, unlisted


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("mode", choices=["shard", "others", "plan"])
    parser.add_argument("spec", help="I/N for shard, N for plan")
    parser.add_argument("--tests-dir", default=str(ROOT / "app" / "TagwerkUITests"))
    parser.add_argument("--durations")
    parser.add_argument("--nightly-only-file")
    parser.add_argument("--set", dest="test_set", choices=["pr", "full"], default="full")
    arguments = parser.parse_args(argv)
    tests_dir = Path(arguments.tests_dir)
    durations_file = arguments.durations or str(tests_dir / "ui-test-durations.txt")
    nightly_file = arguments.nightly_only_file or str(tests_dir / "nightly-only.txt")

    if arguments.mode in ("shard", "others"):
        match = re.match(r"^(\d+)/(\d+)$", arguments.spec)
        if not match or not 1 <= int(match.group(1)) <= int(match.group(2)) <= 8:
            print(f'Invalid shard "{arguments.spec}" (expected I/N with 1 <= I <= N <= 8)', file=sys.stderr)
            return 2
        index, count = int(match.group(1)), int(match.group(2))
    else:
        if not arguments.spec.isdigit() or not 1 <= int(arguments.spec) <= 8:
            print(f'Invalid shard count "{arguments.spec}" (expected 1 to 8)', file=sys.stderr)
            return 2
        index, count = 0, int(arguments.spec)

    try:
        shards, weights, unlisted = build_plan(tests_dir, durations_file, nightly_file, arguments.test_set, count)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    if not any(shards):
        print(f"No UI test class found in {tests_dir}", file=sys.stderr)
        return 2
    if unlisted:
        print(f"ui-test-shards: no duration for {', '.join(unlisted)}; weighted with the mean of the listed classes "
              f"(add them to {durations_file})", file=sys.stderr)

    if arguments.mode == "shard":
        for name in shards[index - 1]:
            print(name)
    elif arguments.mode == "others":
        for number, shard in enumerate(shards, start=1):
            if number != index:
                for name in shard:
                    print(name)
    else:
        for number, shard in enumerate(shards, start=1):
            print(f"shard {number}/{count}: {sum(weights[name] for name in shard):.0f} s, {len(shard)} classes")
            for name in shard:
                print(f"  {name} {weights[name]:.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
