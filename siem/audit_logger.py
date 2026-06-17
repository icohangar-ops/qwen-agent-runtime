"""
SIEM audit logger — structured JSON lines logging for all agent actions.
"""
from __future__ import annotations

import json
import os
import time
import datetime
from pathlib import Path


class AuditLogger:
    """
    Writes structured JSONL audit logs for every agent action.

    Each log entry:
    {
        "timestamp": "2025-05-24T12:00:00.000Z",
        "event": "command_executed",
        "agent_id": "laptop-primary",
        "data": { ... }
    }
    """

    def __init__(self, log_file: str = "logs/audit.jsonl", agent_id: str = "unknown"):
        self.agent_id = agent_id
        self.log_path = Path(log_file)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self._fh = open(self.log_path, "a", encoding="utf-8")

    def log(self, event: str, data: dict | None = None):
        """Write a structured audit log entry."""
        entry = {
            "timestamp": datetime.datetime.utcnow().isoformat() + "Z",
            "event": event,
            "agent_id": self.agent_id,
            "data": data or {},
        }
        self._fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
        self._fh.flush()

        # Optional: syslog forwarding could go here
        syslog_config = self._load_syslog_config()
        if syslog_config and syslog_config.get("enabled"):
            self._forward_syslog(entry, syslog_config)

    def _load_syslog_config(self) -> dict | None:
        """Try to load syslog config from config.yaml."""
        try:
            import yaml
            config_path = Path(__file__).parent.parent / "config" / "config.yaml"
            if config_path.exists():
                with open(config_path) as f:
                    raw = yaml.safe_load(f)
                return raw.get("siem", {}).get("syslog")
        except Exception:
            pass
        return None

    def _forward_syslog(self, entry: dict, config: dict):
        """Forward log entry to syslog server."""
        try:
            from pysyslogclient import SyslogClient
            client = SyslogClient(
                hostname=config.get("host", "localhost"),
                port=config.get("port", 514),
                protocol=config.get("protocol", "UDP").lower(),
            )
            client.log(
                msg=json.dumps(entry),
                severity=SyslogClient.SEVERITY_INFO,
                facility=SyslogClient.FACILITY_LOCAL0,
            )
        except ImportError:
            pass  # pysyslogclient not installed
        except Exception:
            pass  # syslog unavailable

    def close(self):
        """Flush and close the log file."""
        if self._fh and not self._fh.closed:
            self._fh.flush()
            self._fh.close()
