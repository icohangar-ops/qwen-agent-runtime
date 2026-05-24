"""
Senso Agent Runtime — main entry point.
Usage: python -m agent
"""
from __future__ import annotations

import sys
import re
import yaml
from pathlib import Path
from datetime import datetime

from rich.console import Console
from rich.panel import Panel
from rich.text import Text

from agent.executor import ShellResult, execute
from guardrails.whitelist import WhitelistEngine
from guardrails.approval import ApprovalUI
from guardrails.timeout import run_with_timeout
from guardrails.sanitizer import OutputSanitizer
from siem.audit_logger import AuditLogger

console = Console()

BANNER = r"""
[bold cyan]
  ╔══════════════════════════════════════════╗
  ║       Senso Agent Runtime v1.1           ║
  ║   Groq-Powered Local Shell Agent        ║
  ╚══════════════════════════════════════════╝
[/bold cyan]
"""

SYSTEM_PROMPT = """You are Senso, a local system administration agent running on Windows PowerShell.
Your job is to help the user by executing shell commands.

RULES:
1. When you need to run a shell command, output it on a line starting with "CMD> " (exactly).
   Example: CMD> Get-Process | Where-Object {$_.WorkingSet64 -gt 100MB}
2. You can output multiple CMD> lines in sequence if multiple commands are needed.
3. After the last command, end with a line containing only "CMD> DONE".
4. If you can answer without running a command, just answer normally (no CMD> prefix).
5. Always explain what you're about to do before executing.
6. Keep responses concise and actionable.
7. If a command fails, analyze the error and suggest a fix.
8. Never suggest commands that could harm the system (format, delete system files, disable security, etc.).
"""


def load_config() -> dict:
    """Load configuration from config/config.yaml."""
    config_path = Path(__file__).parent.parent / "config" / "config.yaml"
    if not config_path.exists():
        console.print(f"[red]Config not found:[/red] {config_path}")
        console.print("Copy config/config.example.yaml to config/config.yaml and fill in your API key.")
        sys.exit(1)

    with open(config_path) as f:
        return yaml.safe_load(f)


def create_llm(config: dict):
    """Create the LangChain Chat model connected to Qwen via OpenAI-compatible API."""
    from langchain_openai import ChatOpenAI

    llm_cfg = config.get("llm", {}).get("backup", {})
    return ChatOpenAI(
        model=llm_cfg.get("model", "qwen2.5-72b-instruct"),
        api_key=llm_cfg.get("api_key", ""),
        base_url=llm_cfg.get("base_url", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
        temperature=0.1,
        max_tokens=2048,
    )


def parse_commands(response: str) -> list[str]:
    """Extract CMD> lines from LLM response. Returns list of commands."""
    commands = []
    for line in response.split("\n"):
        line = line.strip()
        if line.startswith("CMD> ") and line != "CMD> DONE":
            cmd = line[5:].strip()
            if cmd:
                commands.append(cmd)
        elif line == "CMD> DONE":
            break
    return commands


def strip_command_blocks(response: str) -> str:
    """Remove CMD> lines from response to get the explanatory text."""
    lines = []
    for line in response.split("\n"):
        stripped = line.strip()
        if stripped.startswith("CMD>"):
            continue
        lines.append(line)
    return "\n".join(lines).strip()


def run_command(
    command: str,
    whitelist: WhitelistEngine,
    approval: ApprovalUI,
    sanitizer: OutputSanitizer,
    logger: AuditLogger,
    shell: str,
    max_cmd_len: int,
) -> tuple[bool, str]:
    """
    Run a single command through the full guardrail pipeline.
    Returns (success: bool, output: str).
    """
    command = command.strip()

    # Length check
    if len(command) > max_cmd_len:
        msg = f"Command exceeds max length ({max_cmd_len} chars)"
        console.print(f"  [red]BLOCKED:[/red] {msg}")
        logger.log("command_blocked", {"command": command[:200], "reason": msg})
        return False, msg

    # Whitelist check
    allowed, reason = whitelist.check(command)
    if not allowed:
        console.print(f"  [red]BLOCKED:[/red] {reason}")
        logger.log("command_blocked", {"command": command[:200], "reason": reason})
        return False, f"Command blocked: {reason}"

    # Human approval
    decision = approval.ask(command)
    if decision.action.value == "reject":
        console.print("  [yellow]REJECTED by user.[/yellow]")
        logger.log("command_rejected", {"command": command[:200]})
        return False, "Command rejected by user."

    final_cmd = decision.modified_command or command
    if decision.action.value == "modify":
        logger.log("command_modified", {"original": command[:200], "modified": final_cmd[:200]})

    # Get timeout
    timeout = whitelist.get_timeout(final_cmd)

    # Execute with timeout
    logger.log("command_executing", {"command": final_cmd[:200], "timeout": timeout})
    console.print(f"  [dim]Executing (timeout: {timeout}s)...[/dim]")

    try:
        result = run_with_timeout(final_cmd, timeout=timeout, shell=shell)
    except TimeoutError as e:
        msg = str(e)
        console.print(f"  [red]TIMEOUT:[/red] {msg}")
        logger.log("command_timeout", {"command": final_cmd[:200], "timeout": timeout})
        return False, msg

    # Sanitize output
    safe_output = sanitizer.sanitize_output(result.stdout)
    safe_stderr = sanitizer.sanitize_output(result.stderr)

    # Log result
    logger.log("command_completed", {
        "command": final_cmd[:200],
        "exit_code": result.exit_code,
        "stdout_length": len(result.stdout),
        "stderr_length": len(result.stderr),
    })

    # Display output
    if safe_output:
        console.print(Panel(safe_output, title="[green]Output[/green]", border_style="green", expand=False))
    if safe_stderr and result.exit_code != 0:
        console.print(Panel(safe_stderr, title="[red]Error[/red]", border_style="red", expand=False))

    output = safe_output
    if safe_stderr:
        output = output + "\n" + safe_stderr if output else safe_stderr

    return result.exit_code == 0, output or "(no output)"


def chat_loop():
    """Main interactive chat loop."""
    config = load_config()

    # Initialize components
    config_path = Path(__file__).parent.parent / "config" / "config.yaml"
    llm = create_llm(config)
    whitelist = WhitelistEngine.from_yaml(config_path)
    approval = ApprovalUI.from_yaml(config_path)
    sanitizer = OutputSanitizer.from_yaml(config_path)

    agent_id = config.get("agent", {}).get("id", "unknown")
    shell = config.get("shell", "powershell")
    max_turns = config.get("limits", {}).get("max_turns", 20)
    max_cmd_len = config.get("limits", {}).get("max_command_length", 2000)
    siem_cfg = config.get("siem", {})
    log_file = siem_cfg.get("log_file", "logs/audit.jsonl") if siem_cfg.get("enabled", True) else "logs/audit.jsonl"

    logger = AuditLogger(log_file=log_file, agent_id=agent_id)

    console.print(BANNER)
    console.print(f"  Agent ID: [bold]{agent_id}[/bold]")
    console.print(f"  Shell:    [bold]{shell}[/bold]")
    console.print(f"  Model:    [bold]{config.get('llm', {}).get('backup', {}).get('model', 'qwen2.5-72b-instruct')}[/bold]")
    console.print(f"  Guardrails: [green]active[/green] | SIEM: [green]logging[/green]")
    console.print(f"\n  Type [bold]quit[/bold] or [bold]exit[/bold] to stop. Type [bold]help[/bold] for commands.\n")

    logger.log("agent_started", {"shell": shell, "model": config.get("llm", {}).get("backup", {}).get("model")})

    # Conversation history
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    while True:
        try:
            user_input = console.input("\n[bold cyan]You >[/bold cyan] ").strip()
        except (EOFError, KeyboardInterrupt):
            console.print("\n[yellow]Goodbye![/yellow]")
            logger.log("agent_stopped", {"reason": "user_interrupt"})
            logger.close()
            break

        if not user_input:
            continue

        if user_input.lower() in ("quit", "exit", "q"):
            console.print("[yellow]Goodbye![/yellow]")
            logger.log("agent_stopped", {"reason": "user_quit"})
            logger.close()
            break

        if user_input.lower() == "help":
            console.print(Panel(
                "[bold]Available commands:[/bold]\n"
                "  help       - Show this help\n"
                "  quit/exit  - Stop the agent\n"
                "  status     - Show agent status\n"
                "  history    - Show conversation length\n"
                "  clear      - Clear conversation history\n\n"
                "  [bold]Anything else[/bold] will be sent to Qwen as a natural language request.\n"
                "  Qwen may generate shell commands (CMD>) that require your approval.",
                title="Help", border_style="cyan"
            ))
            continue

        if user_input.lower() == "status":
            console.print(Panel(
                f"Agent ID: {agent_id}\n"
                f"Shell: {shell}\n"
                f"Model: {config.get('llm', {}).get('backup', {}).get('model')}\n"
                f"Conversation turns: {len(messages) - 1}\n"
                f"Guardrails: active\n"
                f"SIEM log: {log_file}",
                title="Agent Status", border_style="cyan"
            ))
            continue

        if user_input.lower() == "history":
            console.print(f"  Conversation has [bold]{len(messages) - 1}[/bold] messages.")
            continue

        if user_input.lower() == "clear":
            messages = [{"role": "system", "content": SYSTEM_PROMPT}]
            console.print("  [green]Conversation history cleared.[/green]")
            logger.log("history_cleared", {})
            continue

        # Send to LLM
        logger.log("user_message", {"content_length": len(user_input)})
        messages.append({"role": "user", "content": user_input})

        try:
            response = llm.invoke(messages)
            ai_text = response.content
        except Exception as e:
            console.print(f"  [red]LLM Error:[/red] {e}")
            logger.log("llm_error", {"error": str(e)[:500]})
            messages.pop()  # Remove failed user message
            continue

        # Parse commands from response
        commands = parse_commands(ai_text)
        explanation = strip_command_blocks(ai_text)

        if explanation:
            console.print(f"\n[bold magenta]Senso >[/bold magenta] {explanation}\n")

        # Execute commands
        all_output = ""
        turn_count = 0
        for cmd in commands:
            if turn_count >= max_turns:
                console.print(f"  [yellow]Max turns ({max_turns}) reached.[/yellow]")
                break

            success, output = run_command(
                cmd, whitelist, approval, sanitizer, logger, shell, max_cmd_len
            )
            all_output += f"\n[{cmd}]\nExit code: {0 if success else 'non-zero'}\n{output}\n"
            turn_count += 1

        # Feed results back to LLM for analysis if commands were run
        if commands and all_output:
            messages.append({"role": "assistant", "content": ai_text})
            # Truncate output to stay within token limits (roughly 6000 chars ~ 2000 tokens)
            truncated = all_output[:6000] + "...\n[output truncated]" if len(all_output) > 6000 else all_output
            messages.append({
                "role": "user",
                "content": f"Command outputs:\n{truncated}\n\nPlease analyze the results and respond.",
            })

            try:
                analysis = llm.invoke(messages)
                console.print(f"\n[bold magenta]Senso >[/bold magenta] {analysis.content}")
                messages.append({"role": "assistant", "content": analysis.content})
            except Exception as e:
                console.print(f"  [red]Analysis error:[/red] {e}")
        elif commands:
            # Commands ran but no output to analyze
            messages.append({"role": "assistant", "content": ai_text})
        else:
            # No commands — pure conversational response
            if not explanation:
                console.print(f"\n[bold magenta]Senso >[/bold magenta] {ai_text}")
            messages.append({"role": "assistant", "content": ai_text})


if __name__ == "__main__":
    chat_loop()
