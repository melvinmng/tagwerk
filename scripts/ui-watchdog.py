#!/usr/bin/python3
"""Runs a command (xcodebuild of a test stage) under a watchdog and shows its progress.

app/test-all.sh starts every xcodebuild call through this script. The command writes into the stage log; the watchdog follows
that log and
  - prints the test progress to its own stdout, so the job log of CI shows where the run stands: every `Test Case ... started`,
    `passed` and `failed` line, plus a heartbeat line every --heartbeat seconds (phase, elapsed time, time since the last log
    output, test counts, current test);
  - stops the run when the log stays silent for --silence seconds (a hang before or between tests, which the hang sampler
    cannot see) or the run takes longer than --max-seconds. Before it stops anything it collects diagnostics into
    <diag-dir>/watchdog-<phase>-<time>/: summary.txt (reason and the last log lines), ps.txt (`ps auxww`), simctl-booted.txt
    (`xcrun simctl list devices booted`), sample-<name>-<pid>.txt (`sample` of the app, the UI test runner, xcodebuild and
    testmanagerd of the run), simulator-log.txt (`simctl spawn <udid> log show --last 10m`). Then it terminates the process group
    of the command and its other descendants (TERM, then KILL after --grace seconds) and, with --shutdown-simulator, shuts the
    simulator of the run down.

Exit status: the status of the command (128 + n for a signal); 124 when the watchdog stopped it (the message names the phase and
the reason); 143 when the watchdog itself was terminated (the command is stopped as well).

Usage: ui-watchdog.py --phase NAME --log LOG --diag-dir DIR [--append] [--silence S] [--max-seconds S] [--heartbeat S]
                      [--simulator-id UDID] [--shutdown-simulator] [--grace S] [--poll S] -- COMMAND [ARGS...]
`sample`, `ps`, `pgrep` and `xcrun` are looked up in PATH.
"""
import argparse
import os
import re
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

TEST_LINE = re.compile(r"Test [Cc]ase '([^']+)' (started|passed|failed)")
# Processes that are sampled when the run hangs: the app, the UI test runner and the test daemon of the simulator, filtered by the
# simulator id; xcodebuild and its children are taken from the process tree of the command.
SAMPLE_PATTERNS = [
    ("app", re.compile(r"Tagwerk\.app/Tagwerk")),
    ("runner", re.compile(r"TagwerkUITests-Runner")),
    ("testmanagerd", re.compile(r"testmanagerd")),
]
TIMEOUT_EXIT_CODE = 124
MAX_SAMPLED_PROCESSES = 8


def log(message):
    print(message, flush=True)


def process_table():
    """All processes as (pid, ppid, command)."""
    result = subprocess.run(["ps", "-axo", "pid=,ppid=,command="], capture_output=True, text=True)
    table = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) >= 2 and parts[0].isdigit() and parts[1].isdigit():
            table.append((int(parts[0]), int(parts[1]), parts[2] if len(parts) > 2 else ""))
    return table


def descendants(table, root):
    """Process ids below `root` (not including it)."""
    children = {}
    for pid, ppid, _ in table:
        children.setdefault(ppid, []).append(pid)
    found, queue = [], list(children.get(root, []))
    while queue:
        pid = queue.pop()
        if pid not in found:
            found.append(pid)
            queue.extend(children.get(pid, []))
    return found


def run_capture(command, target, timeout):
    """Runs `command`, writes its output to `target` and gives up after `timeout` seconds (the partial output stays)."""
    try:
        with open(target, "wb") as handle:
            process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
                handle.write(f"\n[watchdog] stopped after {timeout} s\n".encode())
    except OSError as error:
        Path(target).write_text(f"could not run {' '.join(command)}: {error}\n")


def safe_name(text):
    return re.sub(r"[^A-Za-z0-9._-]+", "_", text).strip("_")[:60] or "x"


class Watchdog:
    def __init__(self, arguments, command):
        self.arguments = arguments
        self.command = command
        self.started = time.monotonic()
        self.last_activity = self.started
        self.last_heartbeat = self.started
        self.recent_lines = []
        self.passed = self.failed = 0
        self.current_test = ""
        self.process = None
        self.interrupted = False

    def elapsed(self):
        return int(time.monotonic() - self.started)

    def prefix(self):
        return f"    [{self.arguments.phase} +{self.elapsed()} s]"

    def handle_line(self, line):
        self.recent_lines.append(line)
        del self.recent_lines[:-60]
        match = TEST_LINE.search(line)
        if not match:
            return
        name, outcome = match.groups()
        if outcome == "started":
            self.current_test = name
        elif outcome == "passed":
            self.passed += 1
        else:
            self.failed += 1
        log(f"{self.prefix()} {outcome:7} {name}")

    def heartbeat(self, now):
        log(f"{self.prefix()} running; last log output {int(now - self.last_activity)} s ago; "
            f"tests: {self.passed} passed, {self.failed} failed; current: {self.current_test or '-'}")

    def run(self):
        arguments = self.arguments
        log_path = Path(arguments.log)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "ab" if arguments.append else "wb") as output:
            environment = dict(os.environ, NSUnbufferedIO="YES")
            self.process = subprocess.Popen(self.command, stdout=output, stderr=subprocess.STDOUT,
                                            env=environment, start_new_session=True)
            self.install_signal_handlers()
            with open(log_path, "rb") as reader:
                if arguments.append:
                    reader.seek(0, os.SEEK_END)
                status = self.follow(reader)
        return status

    def install_signal_handlers(self):
        def stop(signum, _frame):
            self.interrupted = True
            self.terminate_command()
            sys.exit(143)
        if threading.current_thread() is threading.main_thread():
            for signum in (signal.SIGTERM, signal.SIGINT, signal.SIGHUP):
                signal.signal(signum, stop)

    def follow(self, reader):
        arguments = self.arguments
        pending = b""
        while True:
            chunk = reader.read(65536)
            now = time.monotonic()
            if chunk:
                self.last_activity = now
                pending += chunk
                *lines, pending = pending.split(b"\n")
                for line in lines:
                    self.handle_line(line.decode(errors="replace"))
                continue
            code = self.process.poll()
            if code is not None:
                # Read what the command wrote last.
                rest = reader.read()
                for line in (pending + rest).split(b"\n"):
                    if line:
                        self.handle_line(line.decode(errors="replace"))
                return 128 - code if code < 0 else code
            silent = now - self.last_activity
            if arguments.silence > 0 and silent >= arguments.silence:
                return self.trigger(f"no log output for {int(silent)} s (limit {arguments.silence} s)")
            if arguments.max_seconds > 0 and now - self.started >= arguments.max_seconds:
                return self.trigger(f"run time limit of {arguments.max_seconds} s reached")
            if arguments.heartbeat > 0 and now - self.last_heartbeat >= arguments.heartbeat:
                self.last_heartbeat = now
                self.heartbeat(now)
            time.sleep(arguments.poll)

    def trigger(self, reason):
        arguments = self.arguments
        message = f"WATCHDOG: phase \"{arguments.phase}\" stopped: {reason}"
        log(f"{self.prefix()} {message}")
        print(message, file=sys.stderr, flush=True)
        folder = Path(arguments.diag_dir) / f"watchdog-{safe_name(arguments.phase)}-{time.strftime('%H%M%S')}"
        try:
            folder.mkdir(parents=True, exist_ok=True)
            self.collect_diagnostics(folder, reason)
            log(f"{self.prefix()} diagnostics written to {folder}")
        except OSError as error:
            log(f"{self.prefix()} diagnostics failed: {error}")
        self.terminate_command()
        if arguments.shutdown_simulator and arguments.simulator_id:
            run_capture(["xcrun", "simctl", "shutdown", arguments.simulator_id], folder / "simctl-shutdown.txt", 60)
            log(f"{self.prefix()} simulator {arguments.simulator_id} shut down")
        return TIMEOUT_EXIT_CODE

    def collect_diagnostics(self, folder, reason):
        arguments = self.arguments
        table = process_table()
        below = set(descendants(table, self.process.pid)) | {self.process.pid}
        commands = {pid: command for pid, _, command in table}
        with open(folder / "summary.txt", "w") as summary:
            summary.write(f"phase: {arguments.phase}\nreason: {reason}\nelapsed: {self.elapsed()} s\n"
                          f"tests: {self.passed} passed, {self.failed} failed, current: {self.current_test or '-'}\n"
                          f"command: {' '.join(self.command)}\nlog: {arguments.log}\n\n"
                          f"processes of the command:\n")
            for pid in sorted(below):
                summary.write(f"  {pid} {commands.get(pid, '')[:200]}\n")
            summary.write("\nlast log lines:\n" + "\n".join(self.recent_lines[-40:]) + "\n")

        jobs = [threading.Thread(target=run_capture, args=(["ps", "auxww"], folder / "ps.txt", 30))]
        jobs.append(threading.Thread(target=run_capture, args=(["xcrun", "simctl", "list", "devices", "booted"],
                                                               folder / "simctl-booted.txt", 60)))
        if arguments.simulator_id:
            jobs.append(threading.Thread(target=run_capture, args=(
                ["xcrun", "simctl", "spawn", arguments.simulator_id, "log", "show", "--last", "10m", "--style", "compact"],
                folder / "simulator-log.txt", 90)))
        targets = []
        for pid, label in self.processes_to_sample(table, below):
            targets.append((pid, label))
        for pid, label in targets[:MAX_SAMPLED_PROCESSES]:
            target = folder / f"sample-{safe_name(label)}-{pid}.txt"
            jobs.append(threading.Thread(target=run_capture, args=(
                ["sample", str(pid), "3", "-file", str(target)], folder / f"sample-{safe_name(label)}-{pid}.out", 30)))
        for job in jobs:
            job.start()
        for job in jobs:
            job.join()

    def processes_to_sample(self, table, below):
        """(pid, label) of the processes worth a stack sample: xcodebuild below the command, and the processes of the simulator."""
        found = []
        for pid, _, command in table:
            if pid in below and re.search(r"xcodebuild|xctest|xcodebuild-runner", command):
                found.append((pid, "xcodebuild"))
                continue
            simulator_match = not self.arguments.simulator_id or self.arguments.simulator_id in command
            if not simulator_match:
                continue
            for label, pattern in SAMPLE_PATTERNS:
                if pattern.search(command):
                    found.append((pid, label))
                    break
        return found

    def terminate_command(self):
        """TERM, then KILL for the process group of the command and for the descendants that left the group."""
        process = self.process
        if process is None:
            return
        below = descendants(process_table(), process.pid)
        for send in (signal.SIGTERM, signal.SIGKILL):
            try:
                os.killpg(process.pid, send)
            except OSError:
                pass
            for pid in below:
                try:
                    os.kill(pid, send)
                except OSError:
                    pass
            deadline = time.monotonic() + (self.arguments.grace if send == signal.SIGTERM else 5)
            while time.monotonic() < deadline and process.poll() is None:
                time.sleep(0.1)
            if process.poll() is not None and not any(alive(pid) for pid in below):
                return


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def main(argv):
    if "--" not in argv:
        print(__doc__, file=sys.stderr)
        return 2
    split = argv.index("--")
    command = argv[split + 1:]
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--phase", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("--diag-dir", required=True)
    parser.add_argument("--append", action="store_true")
    parser.add_argument("--silence", type=int, default=0, help="seconds without log output before the run is stopped (0 = off)")
    parser.add_argument("--max-seconds", type=int, default=0, help="run time limit in seconds (0 = off)")
    parser.add_argument("--heartbeat", type=int, default=300)
    parser.add_argument("--simulator-id", default="")
    parser.add_argument("--shutdown-simulator", action="store_true")
    parser.add_argument("--grace", type=float, default=10.0)
    parser.add_argument("--poll", type=float, default=1.0)
    arguments = parser.parse_args(argv[:split])
    if not command:
        print("ui-watchdog: no command after --", file=sys.stderr)
        return 2
    try:
        return Watchdog(arguments, command).run()
    except FileNotFoundError as error:
        print(f"ui-watchdog: cannot start {command[0]}: {error}", file=sys.stderr)
        return 127


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
