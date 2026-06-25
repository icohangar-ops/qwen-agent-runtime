"""
Daytona sandbox execution — routes approved shell commands to isolated VMs.

Enabled when DAYTONA_API_KEY is set or config daytona.enabled is true.
Set DAYTONA_DISABLE=1 to force local subprocess execution.
"""
from __future__ import annotations

import os
import shlex
from typing import Any

from agent.executor import ShellResult


class DaytonaSession:
    """Reuse one sandbox for the agent session to limit credit burn."""

    _daytona: Any | None = None
    _sandbox: Any | None = None

    @classmethod
    def enabled(cls, config: dict | None = None) -> bool:
        if os.environ.get("DAYTONA_DISABLE", "").lower() in ("1", "true", "yes"):
            return False
        if os.environ.get("DAYTONA_API_KEY"):
            return True
        return bool((config or {}).get("daytona", {}).get("enabled"))

    @classmethod
    def sandbox_shell(cls, config: dict | None = None) -> str:
        if config and config.get("daytona", {}).get("shell"):
            return str(config["daytona"]["shell"])
        return os.environ.get("DAYTONA_SHELL", "bash")

    @classmethod
    def get_sandbox(cls):
        if cls._sandbox is not None:
            return cls._sandbox
        from daytona import Daytona

        cls._daytona = Daytona()
        cls._sandbox = cls._daytona.create()
        return cls._sandbox

    @classmethod
    def cleanup(cls) -> None:
        if cls._sandbox is not None:
            try:
                cls._sandbox.delete()
            except Exception:
                pass
        cls._sandbox = None
        cls._daytona = None


def _wrap_command(command: str, shell: str, sandbox_shell: str) -> str:
    """Map host shell dialect to the Linux sandbox shell."""
    if sandbox_shell == shell:
        return command
    if sandbox_shell == "bash":
        return command
    return command


def execute_in_sandbox(
    command: str,
    shell: str = "powershell",
    cwd: str | None = None,
    timeout: int = 30,
    config: dict | None = None,
) -> ShellResult:
    """Execute a whitelisted command inside a Daytona sandbox."""
    sandbox = DaytonaSession.get_sandbox()
    sandbox_shell = DaytonaSession.sandbox_shell(config)
    run_cmd = _wrap_command(command, shell, sandbox_shell)

    work_dir = cwd
    if not work_dir:
        try:
            work_dir = sandbox.get_work_dir()
        except Exception:
            work_dir = None

    try:
        response = sandbox.process.exec(run_cmd, cwd=work_dir, timeout=timeout)
        output = (response.result or "").strip()
        exit_code = int(getattr(response, "exit_code", 1) or 0)
        return ShellResult(stdout=output, stderr="", exit_code=exit_code)
    except TimeoutError:
        raise
    except Exception as exc:
        message = str(exc)
        if "timeout" in message.lower():
            raise TimeoutError(f"Command timed out after {timeout}s: {command[:80]}") from exc
        return ShellResult(stdout="", stderr=f"Daytona execution error: {message}", exit_code=-1)


def upload_workspace(sandbox, local_dir: str, remote_dir: str | None = None) -> str:
    """Upload a local directory into the active sandbox workspace."""
    from pathlib import Path

    root = Path(local_dir)
    if not root.exists():
        raise FileNotFoundError(local_dir)

    if remote_dir is None:
        remote_dir = sandbox.get_work_dir()

    uploads: list[tuple[str, bytes]] = []
    for path in root.rglob("*"):
        if path.is_file():
            rel = path.relative_to(root).as_posix()
            uploads.append((f"{remote_dir.rstrip('/')}/{rel}", path.read_bytes()))

    if uploads:
        sandbox.fs.upload_files(uploads)
    return remote_dir


def run_argv_in_sandbox(
    command: list[str],
    work_dir: str | None = None,
    timeout: int = 300,
    config: dict | None = None,
) -> ShellResult:
    """Run a argv command list inside Daytona (used by bio pipeline runner)."""
    cmd = " ".join(shlex.quote(part) for part in command)
    return execute_in_sandbox(cmd, shell="bash", cwd=work_dir, timeout=timeout, config=config)
