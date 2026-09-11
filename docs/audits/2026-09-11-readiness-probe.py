#!/usr/bin/env python3
"""Build an isolated probe against existing debug app objects; never contact HA.

Run `swift test` first. This is audit evidence, not a passing regression suite:
the audited revision crashes or exceeds the deadline in three subprocesses.
"""

from pathlib import Path
import resource
import subprocess
import tempfile


def disable_core_dump():
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))


def main():
    root = Path(__file__).resolve().parents[2]
    source = Path(__file__).with_suffix(".swift")
    output = Path(tempfile.mkdtemp(prefix="nativeha-readiness-audit-"))
    build = Path(subprocess.check_output(
        ["swift", "build", "--show-bin-path"], cwd=root, text=True
    ).strip())
    objects = sorted(
        path
        for folder in ["NativeHAMac.build", "NativeHACore.build", "plugins"]
        for path in (build / folder).rglob("*.swift.o")
        if path.name != "NativeHAMacApp.swift.o"
    )
    if not objects:
        raise SystemExit("Run swift test to build the debug application objects first")
    executable = output / "AuditProbe"
    compiled = subprocess.run([
        "swiftc", "-parse-as-library", "-I", str(build), "-I", str(build / "Modules"),
        str(source), *map(str, objects), "-o", str(executable),
    ], capture_output=True, text=True, cwd=root)
    (output / "build.log").write_text(compiled.stdout + compiled.stderr)
    if compiled.returncode:
        raise SystemExit(f"Probe build failed; see {output / 'build.log'}")

    for mode in ["climate", "infinite-axis", "large-finite-axis", "graph"]:
        deadline = 5 if mode == "graph" else 0.3
        try:
            result = subprocess.run(
                [str(executable), mode], capture_output=True, text=True,
                timeout=deadline, preexec_fn=disable_core_dump,
            )
            report = f"{mode}: exit={result.returncode}\n{result.stdout}{result.stderr}"
        except subprocess.TimeoutExpired:
            report = f"{mode}: exceeded {deadline}s deadline; child killed"
        (output / f"{mode}.log").write_text(report)
        print(report)
    print(f"Audit artifacts: {output}")


if __name__ == "__main__":
    main()
