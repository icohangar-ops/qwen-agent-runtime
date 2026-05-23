"""
Command whitelist engine — regex-based allow/deny for shell commands.
"""
from __future__ import annotations

import re
import yaml
from pathlib import Path
from dataclasses import dataclass, field

# Dangerous patterns — always blocked regardless of whitelist
HARD_DENY = [
    r"(?i).*-Verb\s+RunAs.*",
    r"(?i).*Remove-Item.*-Recurse.*-Force.*",
    r"(?i).*Format-Volume.*",
    r"(?i).*Stop-Computer.*",
    r"(?i).*Restart-Computer.*",
    r"(?i).*reg\s+delete.*",
    r"(?i).*reg\s+add.*",
    r"(?i).*net\s+user\s+.*\/add.*",
    r"(?i).*net\s+localgroup\s+.*\/add.*",
    r"(?i).*New-LocalUser.*",
    r"(?i).*Remove-LocalUser.*",
    r"(?i).*Set-ExecutionPolicy.*",
    r"(?i).* Invoke-Expression.*",
    r"(?i).*iex\s+.*",
    r"(?i).*Start-BitsTransfer.*-Source\s+http.*",
    r"(?i).*Invoke-WebRequest.*-OutFile.*",
    r"(?i).*wget\s+.*\|\s*bash",
    r"(?i).*curl\s+.*\|\s*(bash|sh|powershell)",
    r"(?i).*New-Item.*-ItemType\s+SymbolicLink.*",
    r"(?i).*Set-ACL.*",
    r"(?i).*TakeOwnership.*",
    r"(?i).*diskpart.*",
    r"(?i).*bcdedit.*",
    r"(?i).*netsh\s+advfirewall\s+.*disable.*",
    r"(?i).*Set-MpPreference.*-DisableRealtimeMonitoring.*",
    r"(?i).*Add-MpPreference.*-ExclusionPath.*",
]

# Default safe commands
DEFAULT_ALLOW = [
    r"^Get-",
    r"^Test-",
    r"^Select-",
    r"^Where-",
    r"^Format-",
    r"^Sort-",
    r"^Group-",
    r"^Measure-",
    r"^Compare-",
    r"^Find-",
    r"^Write-Host\s",
    r"^Write-Output\s",
    r"^echo\s",
    r"^dir\b",
    r"^ls\b",
    r"^cat\b",
    r"^type\b",
    r"^systeminfo$",
    r"^ipconfig\b",
    r"^ping\s",
    r"^tracert\s",
    r"^netstat\b",
    r"^tasklist$",
    r"^whoami$",
    r"^hostname$",
    r"^date$",
    r"^time\s*/t$",
    r"^ver$",
    r"^python\s",
    r"^pip\s",
    r"^pip3\s",
    r"^node\s",
    r"^npm\s",
    r"^npx\s",
    r"^git\s",
    r"^docker\s",
    r"^docker-compose\s",
    r"^code\s",
    r"^notepad\s",
    r"^Get-Content\s",
    r"^Set-Content\s",
    r"^Get-ChildItem\s",
    r"^Get-Process$",
    r"^Get-Service$",
    r"^Get-EventLog\s",
    r"^Get-WinEvent\s",
    r"^Get-NetIPAddress\b",
    r"^Get-NetAdapter\b",
    r"^Get-Disk$",
    r"^Get-Volume$",
    r"^Get-FileHash\s",
    r"^tree\b",
    r"^fc\s",
    r"^findstr\s",
    r"^more\s",
    r"^help$",
    r"^cls$",
    r"^clear$",
]

DEFAULT_TIMEOUTS = {
    "default": 30,
    "max": 300,
    "ping": 15,
    "tracert": 30,
    "systeminfo": 60,
    "docker": 120,
    "pip": 120,
    "npm": 120,
    "npx": 120,
    "git": 60,
}


@dataclass
class WhitelistEngine:
    """Regex-based command whitelist with hard deny rules."""
    allow_patterns: list[str] = field(default_factory=lambda: list(DEFAULT_ALLOW))
    deny_patterns: list[str] = field(default_factory=list)
    hard_deny: list[str] = field(default_factory=lambda: list(HARD_DENY))
    timeouts: dict[str, int] = field(default_factory=lambda: dict(DEFAULT_TIMEOUTS))

    @classmethod
    def default(cls) -> "WhitelistEngine":
        return cls()

    @classmethod
    def from_yaml(cls, path: Path) -> "WhitelistEngine":
        if not path.exists():
            return cls.default()
        with open(path) as f:
            raw = yaml.safe_load(f) or {}
        guards = raw.get("guardrails", {})

        allow = guards.get("command_whitelist", {}).get("allow", [])
        deny = guards.get("command_whitelist", {}).get("deny", [])

        timeouts = dict(DEFAULT_TIMEOUTS)
        timeouts.update(guards.get("timeouts", {}).get("per_command", {}))
        timeouts["default"] = guards.get("timeouts", {}).get("default_seconds", 30)
        timeouts["max"] = guards.get("timeouts", {}).get("max_seconds", 300)

        return cls(allow_patterns=allow + DEFAULT_ALLOW, deny_patterns=deny, timeouts=timeouts)

    def check(self, command: str) -> tuple[bool, str]:
        """
        Check if a command is allowed.
        Returns (allowed: bool, reason: str).
        """
        # 1. Hard deny — always blocked
        for pattern in self.hard_deny:
            if re.match(pattern, command.strip()):
                return False, f"Hard deny: dangerous pattern matched [{pattern}]"

        # 2. Explicit deny list
        for pattern in self.deny_patterns:
            if re.match(pattern, command.strip()):
                return False, f"Denied by rule [{pattern}]"

        # 3. Allow list — if any pattern matches, allow
        for pattern in self.allow_patterns:
            if re.match(pattern, command.strip()):
                return True, ""

        # 4. Default: deny if no allow pattern matched
        return False, f"No allow pattern matched for: {command[:60]}"

    def get_timeout(self, command: str) -> int:
        """Get timeout for a specific command."""
        cmd_base = command.strip().split()[0] if command.strip() else ""
        max_t = self.timeouts.get("max", 300)

        # Check exact command first
        if cmd_base.lower() in self.timeouts:
            return min(self.timeouts[cmd_base.lower()], max_t)
        # Check starts-with
        for key, val in self.timeouts.items():
            if key not in ("default", "max") and cmd_base.lower().startswith(key):
                return min(val, max_t)
        return self.timeouts.get("default", 30)
