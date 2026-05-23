"""
Input/output sanitizer — strips secrets, PII, and sensitive data.
"""
from __future__ import annotations

import re
import yaml
from pathlib import Path
from dataclasses import dataclass, field


DEFAULT_STRIP_PATTERNS = [
    r"(?i)password[\s=:]+['\"]?\S+",
    r"(?i)api[_\-]?key[\s=:]+['\"]?\S+",
    r"(?i)token[\s=:]+['\"]?\S+",
    r"(?i)secret[\s=:]+['\"]?\S+",
    r"(?i)Bearer\s+\S+",
    r"(?i)Authorization:\s*\S+",
    r"(?i)sk-[a-zA-Z0-9]{20,}",          # API keys like sk-xxx
    r"(?i)ghp_[a-zA-Z0-9]{36,}",         # GitHub PATs
    r"(?i)gho_[a-zA-Z0-9]{36,}",         # GitHub OAuth
    r"(?i)ghu_[a-zA-Z0-9]{36,}",         # GitHub user tokens
    r"(?i)xox[bpas]-[a-zA-Z0-9\-]+",    # Slack tokens
    r"[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[A-Za-z]{2,}",  # Emails (basic)
    r"(?i)\b\d{3}[-.]?\d{2}[-.]?\d{4}\b",  # SSN pattern
    r"(?i)\b\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4}\b",  # CC numbers
]

DEFAULT_REDACT_REPLACEMENT = "[REDACTED]"


@dataclass
class OutputSanitizer:
    """Sanitizes command input and output to prevent secret leakage."""
    strip_patterns: list[str] = field(default_factory=lambda: list(DEFAULT_STRIP_PATTERNS))
    redact_replacement: str = DEFAULT_REDACT_REPLACEMENT

    @classmethod
    def default(cls) -> "OutputSanitizer":
        return cls()

    @classmethod
    def from_yaml(cls, path: Path) -> "OutputSanitizer":
        if not path.exists():
            return cls.default()
        with open(path) as f:
            raw = yaml.safe_load(f) or {}
        guards = raw.get("guardrails", {}).get("sanitization", {})
        patterns = guards.get("strip_patterns", [])
        return cls(strip_patterns=patterns + DEFAULT_STRIP_PATTERNS)

    def sanitize_input(self, text: str) -> str:
        """Clean a command before execution."""
        return self._redact(text)

    def sanitize_output(self, text: str) -> str:
        """Clean command output before returning/displaying."""
        if not text:
            return text
        return self._redact(text)

    def _redact(self, text: str) -> str:
        result = text
        for pattern in self.strip_patterns:
            try:
                result = re.sub(pattern, self.redact_replacement, result)
            except re.error:
                continue
        return result
