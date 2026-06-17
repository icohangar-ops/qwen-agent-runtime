# Senso Agent Runtime — Qwen-Powered Local Execution

> Secure local agent runtime using **LangChain** with a cloud-hosted, OpenAI-compatible LLM (Qwen 2.5/3 via DashScope by default; Groq or DeepSeek also supported). Executes AI-suggested commands on Windows with built-in safety guardrails, human-in-the-loop approval, and SIEM audit logging.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Senso Agent Runtime                           │
│                                                                 │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │  LLM Client  │───▶│  Guardrails  │───▶│  Shell Executor  │   │
│  │  (OpenAI-    │    │              │    │                  │   │
│  │  compatible) │    │ ✓ Whitelist  │    │ subprocess.run() │   │
│  │  Qwen/Groq/  │    │ ✓ Timeout    │    │                  │   │
│  │  DeepSeek    │    │ ✓ Sanitize   │    └────────┬─────────┘   │
│  └──────────────┘    │ ✓ Approval   │             │              │
│                      └──────────────┘             │              │
│  ┌──────────────┐                                  │              │
│  │  Approval UI │◀─────────────────────────────────┘              │
│  │  (Terminal)  │                                                 │
│  └──────┬───────┘                                                  │
│         │                                                          │
│  ┌──────▼───────────────────┐                                      │
│  │  SIEM / Audit Logger     │                                      │
│  │  • JSON structured logs  │                                      │
│  │  • Syslog forwarder      │                                      │
│  │  • File-based audit trail│                                      │
│  └──────────────────────────┘                                      │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- **OpenAI-compatible LLM**: Uses `langchain-openai` against any OpenAI-compatible endpoint — Qwen 2.5/3 via Alibaba DashScope, Groq, or DeepSeek (configurable `base_url` and `model`)
- **Command Whitelist**: Regex-based allow/deny lists for commands, paths, and arguments
- **Timeout Enforcement**: Per-command configurable timeouts with automatic kill
- **Output Sanitization**: Strips secrets, PII, and sensitive paths from output
- **Human-in-the-Loop**: Terminal-based approval UI — confirm, modify, or reject commands
- **SIEM Integration**: Structured JSON logging, optional syslog forwarding
- **Windows Ready**: PowerShell and CMD support, execution policy config, Defender guidance

## Quick Start (Windows)

### 1. Prerequisites
```powershell
# Set execution policy (run as admin)
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser

# Install Python 3.11+
winget install Python.Python.3.11

# Install dependencies
pip install -r requirements.txt
```

### 2. Configure
```powershell
cp config/config.example.yaml config/config.yaml
notepad config/config.yaml
# Add your Qwen API key and configure guardrails
```

### 3. Run
```powershell
python -m agent
```

## Configuration

```yaml
# config/config.yaml
llm:
  backup:
    type: "qwen"
    api_key: "sk-your-dashscope-key"
    model: "qwen2.5-72b-instruct"  # or qwen3-6b
    base_url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
    # Point base_url/model at Groq or DeepSeek to use a different
    # OpenAI-compatible provider.

guardrails:
  command_whitelist:
    allow:
      - "^Get-"
      - "^Test-"
      - "^Get-Process$"
      - "^Get-Service$"
      - "^systeminfo$"
      - "^ipconfig$"
      - "^ping "
      - "^netstat$"
      - "^dir "
      - "^ls "
      - "^python "
      - "^pip "
      - "^npm "
      - "^npx "
      - "^git "
      - "^docker "
    deny:
      - ".*-Verb RunAs.*"
      - ".*Remove-Item.*-Recurse.*"
      - ".*Format-Volume.*"
      - ".*Stop-Computer.*"
      - ".*Restart-Computer.*"
      - ".*reg.*delete.*"
      - ".*net user.*"
      - ".*net localgroup.*"
      - ".*New-LocalUser.*"
      - ".*Set-ExecutionPolicy.*"

  timeouts:
    default_seconds: 30
    max_seconds: 300
    per_command:
      "ping": 15
      "systeminfo": 60
      "docker": 120

  sanitization:
    strip_patterns:
      - "password[\\s:=]+\\S+"
      - "api[_-]?key[\\s:=]+\\S+"
      - "token[\\s:=]+\\S+"
      - "secret[\\s:=]+\\S+"
      - "Bearer \\S+"
      - "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Z|a-z]{2,}"

  approval:
    mode: "prompt"          # "prompt" | "auto" | "deny"
    auto_approve_patterns:
      - "^Get-Process$"
      - "^echo "
      - "^dir "
      - "^ls "

siem:
  enabled: true
  log_file: "logs/audit.jsonl"
  syslog:
    enabled: false
    host: "localhost"
    port: 514
    protocol: "UDP"
```

## LLM Providers

The runtime talks to any OpenAI-compatible chat endpoint through `langchain-openai`.
Set `base_url` and `model` for the provider you want.

### Qwen 2.5/3 (Alibaba DashScope)
```yaml
backup:
  type: "qwen"
  api_key: "sk-your-dashscope-key"
  model: "qwen2.5-72b-instruct"
  base_url: "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"
```

Get your API key: https://dashscope.console.aliyun.com/apiKey

### Groq / DeepSeek (alternative)
Point `base_url` and `model` at the provider (for example
`https://api.groq.com/openai/v1` with `llama-3.3-70b-versatile`) and supply the
matching `api_key`.

## Safety Model

```
User Request
    │
    ▼
┌─ LLM generates command suggestion ─┐
│                                      │
│  ┌─ Guardrail Layer 1: Whitelist ──┐ │
│  │  Is command pattern allowed?    │ │
│  │  NO → Reject with reason       │ │
│  │  YES → Continue                │ │
│  └─────────────────────────────────┘ │
│                                      │
│  ┌─ Guardrail Layer 2: Sanitize ──┐ │
│  │  Strip secrets/PII from cmd    │ │
│  │  Check argument injection      │ │
│  └─────────────────────────────────┘ │
│                                      │
│  ┌─ Guardrail Layer 3: Approval ──┐ │
│  │  Auto-approve or prompt user?  │ │
│  │  User can: [Y]es [N]o [E]dit  │ │
│  └─────────────────────────────────┘ │
│                                      │
│  ┌─ Guardrail Layer 4: Timeout ───┐ │
│  │  Execute with timeout          │ │
│  │  Kill if exceeded              │ │
│  └─────────────────────────────────┘ │
│                                      │
│  ┌─ Guardrail Layer 5: Sanitize ──┐ │
│  │  Strip secrets from output     │ │
│  └─────────────────────────────────┘ │
│                                      │
└─ Return result to LLM ───────────────┘
    │
    ▼
SIEM Audit Log (async)
```

## Windows PowerShell Requirements

| Scenario | Permission Needed |
|----------|-------------------|
| Direct commands (Get-Process, Test-Connection) | None — standard user |
| Running .ps1 scripts | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Elevated commands (Restart-Service, registry) | Run host as Administrator or `Start-Process -Verb RunAs` |
| Defender/SmartScreen blocks | May require app signing or explicit user override |

## Two-Laptop Setup

Configure both laptops identically, then set one as primary and one as failover:

```yaml
# Laptop 1 (Primary) — config/config.yaml
agent:
  id: "laptop-primary"
  role: "primary"

# Laptop 2 (Failover) — config/config.yaml
agent:
  id: "laptop-failover"
  role: "failover"
  heartbeat:
    primary_url: "http://192.168.1.100:8472/health"
```

## Project Structure

```
qwen-agent-runtime/
├── agent/
│   ├── __init__.py
│   ├── __main__.py          # CLI entry point (python -m agent)
│   └── executor.py          # Shell command executor
├── guardrails/
│   ├── __init__.py
│   ├── whitelist.py         # Command whitelist engine
│   ├── sanitizer.py         # Input/output sanitization
│   ├── approval.py          # Human-in-the-loop approval UI
│   └── timeout.py           # Execution timeout handler
├── siem/
│   ├── __init__.py
│   └── audit_logger.py      # Structured JSON audit logging (+ optional syslog)
├── config/
│   ├── config.example.yaml  # Example configuration (copy to config.yaml)
│   └── config.yaml          # Your local config (gitignored)
├── db/
│   └── schemas/             # SurrealDB multi-model schemas
├── docs/
│   └── diagrams/            # D2 architecture diagrams (.d2/.svg/.png)
├── scripts/
│   ├── setup_windows.ps1    # Windows setup helper
│   └── bootstrap_awesome_ps.ps1
├── tests/
│   └── test_guardrails.py   # Whitelist, sanitizer, approval tests
├── requirements.txt
├── pyproject.toml
└── README.md
```

## License

MIT
