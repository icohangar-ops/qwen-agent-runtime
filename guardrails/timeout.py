"""
Timeout handler — runs commands with configurable timeouts.
Kills process tree on timeout.
"""
from __future__ import annotations

import subprocess
import signal
import platform
from agent.executor import ShellResult
from agent.daytona_runtime import DaytonaSession, execute_in_sandbox


def run_with_timeout(
    command: str,
    timeout: int = 30,
    shell: str = "powershell",
    cwd: str | None = None,
    config: dict | None = None,
) -> ShellResult:
    """Execute command with a hard timeout. Raises TimeoutError if exceeded."""
    if DaytonaSession.enabled(config):
        return execute_in_sandbox(command, shell=shell, cwd=cwd, timeout=timeout, config=config)

    is_win = platform.system() == "Windows"

    if shell == "powershell":
        args = ["powershell", "-NoProfile", "-NonInteractive", "-Command", command]
    elif shell == "cmd":
        args = ["cmd", "/c", command]
    elif shell == "bash":
        args = ["bash", "-c", command]
    else:
        args = ["powershell", "-NoProfile", "-NonInteractive", "-Command", command]

    proc = subprocess.Popen(
        args,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        cwd=cwd,
        shell=False,
    )

    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        return ShellResult(
            stdout=stdout.strip(),
            stderr=stderr.strip(),
            exit_code=proc.returncode,
        )
    except subprocess.TimeoutExpired:
        # Kill the process tree
        if is_win:
            proc.kill()
        else:
            import os
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        proc.wait()
        raise TimeoutError(f"Command timed out after {timeout}s: {command[:80]}")
