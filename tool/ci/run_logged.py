"""Run a build with streaming output, a retained log and an Actions timing summary."""

import datetime
import os
from pathlib import Path
import subprocess
import sys
import time


def main(args):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    if len(args) < 2 or not args[0].replace("-", "").isalnum():
        raise SystemExit("Usage: run_logged.py LABEL COMMAND [ARG ...]")
    label, command = args[0], args[1:]
    directory = Path("build-logs")
    directory.mkdir(exist_ok=True)
    start = time.monotonic()
    code = 1
    with (directory / f"{label}.log").open("w", encoding="utf-8") as log:
        log.write(f"Started: {datetime.datetime.now(datetime.timezone.utc).isoformat()}\n")
        log.write(f"Command: {command!r}\n")
        log.flush()
        try:
            # Flutter is a .bat launcher on Windows; cmd must handle it.
            if os.name == "nt":
                command = ["cmd", "/d", "/s", "/c", subprocess.list2cmdline(command)]
            process = subprocess.Popen(
                command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", bufsize=1,
            )
            for line in process.stdout:
                print(line, end="", flush=True)
                log.write(line)
            code = process.wait()
        finally:
            elapsed = round(time.monotonic() - start, 1)
            result = f"{label}: exit={code}, elapsed={elapsed}s"
            log.write(f"\n{result}\n")
            print(result, flush=True)
            summary = os.environ.get("GITHUB_STEP_SUMMARY")
            if summary:
                with open(summary, "a", encoding="utf-8") as target:
                    target.write(f"- `{label}`: exit `{code}`, **{elapsed}s**\n")
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
