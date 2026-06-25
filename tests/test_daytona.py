"""Tests for Daytona sandbox routing."""
from unittest.mock import MagicMock, patch

import pytest

from agent.daytona_runtime import DaytonaSession, execute_in_sandbox
from agent.executor import ShellResult
from guardrails.timeout import run_with_timeout


class TestDaytonaSession:
    def setup_method(self):
        DaytonaSession.cleanup()

    def teardown_method(self):
        DaytonaSession.cleanup()

    def test_disabled_without_key(self, monkeypatch):
        monkeypatch.delenv("DAYTONA_API_KEY", raising=False)
        assert DaytonaSession.enabled({}) is False
        assert DaytonaSession.enabled({"daytona": {"enabled": False}}) is False

    def test_enabled_with_env(self, monkeypatch):
        monkeypatch.setenv("DAYTONA_API_KEY", "test-key")
        assert DaytonaSession.enabled({}) is True

    def test_enabled_with_config(self, monkeypatch):
        monkeypatch.delenv("DAYTONA_API_KEY", raising=False)
        assert DaytonaSession.enabled({"daytona": {"enabled": True}}) is True

    def test_disable_flag(self, monkeypatch):
        monkeypatch.setenv("DAYTONA_API_KEY", "test-key")
        monkeypatch.setenv("DAYTONA_DISABLE", "1")
        assert DaytonaSession.enabled({}) is False


class TestDaytonaExecution:
    def setup_method(self):
        DaytonaSession.cleanup()

    def teardown_method(self):
        DaytonaSession.cleanup()

    @patch("agent.daytona_runtime.DaytonaSession.get_sandbox")
    def test_execute_in_sandbox(self, mock_get_sandbox):
        sandbox = MagicMock()
        sandbox.get_work_dir.return_value = "/home/daytona"
        response = MagicMock(result="hello\n", exit_code=0)
        sandbox.process.exec.return_value = response
        mock_get_sandbox.return_value = sandbox

        result = execute_in_sandbox("echo hello", timeout=10)
        assert result.exit_code == 0
        assert result.stdout == "hello"
        sandbox.process.exec.assert_called_once_with("echo hello", cwd="/home/daytona", timeout=10)

    @patch("guardrails.timeout.execute_in_sandbox")
    def test_run_with_timeout_routes_to_daytona(self, mock_exec, monkeypatch):
        monkeypatch.setenv("DAYTONA_API_KEY", "test-key")
        mock_exec.return_value = ShellResult(stdout="ok", stderr="", exit_code=0)

        result = run_with_timeout("echo ok", timeout=5, shell="bash")
        assert result.stdout == "ok"
        mock_exec.assert_called_once()

    def test_run_with_timeout_local_when_disabled(self, monkeypatch):
        monkeypatch.delenv("DAYTONA_API_KEY", raising=False)
        monkeypatch.setenv("DAYTONA_DISABLE", "1")

        with patch("guardrails.timeout.subprocess.Popen") as mock_popen:
            proc = MagicMock()
            proc.communicate.return_value = ("local\n", "")
            proc.returncode = 0
            mock_popen.return_value = proc

            result = run_with_timeout("echo local", timeout=5, shell="bash")
            assert result.stdout == "local"
            mock_popen.assert_called_once()
