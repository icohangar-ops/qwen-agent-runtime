"""
Human-in-the-loop approval UI — terminal-based command confirmation.
"""
from __future__ import annotations

import yaml
from pathlib import Path
from dataclasses import dataclass, field
from enum import Enum


class ApprovalAction(str, Enum):
    APPROVE = "approve"
    MODIFY = "modify"
    REJECT = "reject"


@dataclass
class ApprovalDecision:
    action: ApprovalAction
    modified_command: str | None = None


# Commands safe enough to auto-approve
DEFAULT_AUTO_APPROVE = [
    r"^Get-Process$",
    r"^Get-Service$",
    r"^whoami$",
    r"^hostname$",
    r"^ver$",
    r"^echo\s",
    r"^dir\s",
    r"^ls\s",
    r"^date$",
    r"^ipconfig\b",
    r"^Get-ChildItem\s",
    r"^pwd$",
    r"^pwd\s",
]


@dataclass
class ApprovalUI:
    mode: str = "prompt"  # "prompt" | "auto" | "deny"
    auto_approve_patterns: list[str] = field(default_factory=lambda: list(DEFAULT_AUTO_APPROVE))

    @classmethod
    def default(cls) -> "ApprovalUI":
        return cls()

    @classmethod
    def from_yaml(cls, path: Path) -> "ApprovalUI":
        if not path.exists():
            return cls.default()
        with open(path) as f:
            raw = yaml.safe_load(f) or {}
        approval = raw.get("guardrails", {}).get("approval", {})
        return cls(
            mode=approval.get("mode", "prompt"),
            auto_approve_patterns=approval.get("auto_approve_patterns", []) + DEFAULT_AUTO_APPROVE,
        )

    def ask(self, command: str) -> ApprovalDecision:
        """
        Ask user to approve/reject/modify a command.
        Returns ApprovalDecision with the final action.
        """
        import re

        # Check auto-approve
        if self._should_auto_approve(command):
            return ApprovalDecision(action=ApprovalAction.APPROVE)

        if self.mode == "auto":
            return ApprovalDecision(action=ApprovalAction.APPROVE)

        if self.mode == "deny":
            print(f"  [DENY MODE] Command blocked: {command[:60]}")
            return ApprovalDecision(action=ApprovalAction.REJECT)

        # Interactive prompt
        print(f"\n  {'─'*50}")
        print(f"  ⚡ Command to execute:")
        print(f"    {command}")
        print(f"  {'─'*50}")

        while True:
            try:
                choice = input("  Approve? [Y]es / [N]o / [E]dit: ").strip().lower()
            except (EOFError, KeyboardInterrupt):
                return ApprovalDecision(action=ApprovalAction.REJECT)

            if choice in ("y", "yes", ""):
                return ApprovalDecision(action=ApprovalAction.APPROVE)
            elif choice in ("n", "no", "q"):
                return ApprovalDecision(action=ApprovalAction.REJECT)
            elif choice in ("e", "edit"):
                try:
                    modified = input("  Enter modified command: ").strip()
                    if modified:
                        print(f"  Modified: {modified}")
                        return ApprovalDecision(
                            action=ApprovalAction.MODIFY,
                            modified_command=modified,
                        )
                except (EOFError, KeyboardInterrupt):
                    return ApprovalDecision(action=ApprovalAction.REJECT)
            else:
                print("  Enter Y, N, or E")

    def _should_auto_approve(self, command: str) -> bool:
        import re
        for pattern in self.auto_approve_patterns:
            if re.match(pattern, command.strip()):
                return True
        return False
