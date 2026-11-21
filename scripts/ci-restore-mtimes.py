#!/usr/bin/python3
"""Sets the modification time of every tracked file to the time of the commit that last changed it.

A fresh checkout gives every file the current time, so the build system treats all sources as changed and rebuilds
everything, even when DerivedData was restored from a cache. With the commit time as modification time, a file that
did not change since the cached build keeps the same modification time and is not compiled again; only the files that
changed get another time and are rebuilt.

Needs the full history (checkout with fetch-depth 0). Usage: scripts/ci-restore-mtimes.py [repository folder]
Merge commits count when they change a file relative to all parents (conflict resolutions, combined diff), so a merge
result that differs from every parent still gets a new time.
"""
import os
import subprocess
import sys

MARKER = "\x01"


def main() -> int:
    repository = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.getcwd()
    listing = subprocess.run(
        ["git", "-C", repository, "-c", "core.quotepath=false", "ls-files"],
        check=True, capture_output=True, text=True,
    ).stdout
    pending = {line for line in listing.split("\n") if line}
    total = len(pending)
    if total == 0:
        print("No tracked files found.", file=sys.stderr)
        return 1

    log = subprocess.Popen(
        ["git", "-C", repository, "-c", "core.quotepath=false", "log", "-c", "--name-only", "--no-renames",
         f"--format={MARKER}%ct"],
        stdout=subprocess.PIPE, text=True, errors="replace",
    )
    commit_time = 0
    restored = 0
    assert log.stdout is not None
    for line in log.stdout:
        line = line.rstrip("\n")
        if line.startswith(MARKER):
            commit_time = int(line[1:])
            continue
        # The newest commit is listed first, so the first time a file appears is the commit that last changed it.
        if line in pending:
            pending.discard(line)
            path = os.path.join(repository, line)
            try:
                os.utime(path, (commit_time, commit_time), follow_symlinks=False)
                restored += 1
            except OSError as error:
                print(f"Could not set the time of {line}: {error}", file=sys.stderr)
            if not pending:
                break
    # Stop reading early; git may still be writing, so the process is ended by closing the pipe.
    log.stdout.close()
    log.wait()

    print(f"Restored the modification time of {restored} of {total} tracked files from the commit history.")
    if pending:
        print(f"{len(pending)} tracked files were not found in the history and keep their checkout time"
              f" (shallow clone?), first: {sorted(pending)[:3]}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
