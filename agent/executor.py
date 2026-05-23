"""
Shell command executor — runs commands via subprocess with timeout.
"""
from __future__ import annotations

import subprocess
import shlex
import platform
from dataclasses import dataclass


@dataclass
class ShellResult:
    stdout: str
    stderr: str
    exit_code: int


def _powershell_cmd(command: str) -> list[str]:
    """Build PowerShell invocation."""
    return ["powershell", "-NoProfile", "-NonInteractive", "-Command", command]


def _cmd_cmd(command: str) -> list[str]:
    """Build CMD invocation."""
    return ["cmd", "/c", command]


def execute(command: str, shell: str = "powershell", cwd: str | None = None) -> ShellResult:
    """Execute a shell command and return output."""
    is_win = platform.system() == "Windows"

    if shell == "powershell":
        args = _powershell_cmd(command)
    elif shell == "cmd":
        args = _cmd_cmd(command)
    elif shell == "bash":
        args = ["bash", "-c", command]
    elif shell == "sh":
        args = ["sh", "-c", command]
    else:
        args = _powershell_cmd(command)

    try:
        proc = subprocess.run(
            args,
            capture_output=True,
            text=True,
            cwd=cwd,
            timeout=None,  # timeout handled by caller
            shell=False,
        )
        return ShellResult(
            stdout=proc.stdout.strip(),
            stderr=proc.stderr.strip(),
            exit_code=proc.returncode,
        )
    except FileNotFoundError as e:
        return ShellResult(stdout="", stderr=f"Shell not found: {e}", exit_code=127)
    except subprocess.SubprocessError as e:
        return ShellResult(stdout="", stderr=f"Execution error: {e}", exit_code=-1)
