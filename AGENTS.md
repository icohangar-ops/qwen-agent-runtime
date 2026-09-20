# AGENTS.md — Qwen Agent Runtime

## Mission

Qwen Agent Runtime is a Python 3 agent runtime with pytest-asyncio tests. Its
guards and model-integration surfaces are exercised by `tests/test_guardrails.py`
and `tests/test_daytona.py`. Agents working here must keep the guardrail tests
deterministic, keep model/API keys out of the tree, and run the pytest suite
before declaring any change done.

## Architecture

| Layer | Role | Do | Don't |
|-------|------|----|-------|
| `agent/` | Runtime source | Keep async boundaries explicit | Block the event loop in agent paths |
| `tests/` | Guardrail + integration tests | Run `pytest tests/ -q` locally | Skip guardrail tests to speed up a run |
| `config/` | Runtime configuration | Keep secrets in env, never in config files | Commit real keys or endpoints |
| `db/` | Persistence surface | Treat as implementation detail of `agent/` | Reach into it from tests bypassing `agent/` APIs |

## Engineering rules

### Non-negotiables

1. **Guardrails are load-bearing** — any change that weakens a guardrail test
   requires the PR to argue the policy change explicitly; never loosen an
   assertion to make a test pass.
2. **No committed secrets** — model API keys live in the environment only.
3. **Pytest is the gate** — `pytest tests/ -q` must pass on every change;
   pytest-asyncio tests must not be marked skip by default.

### Propagation Matrix — Wave C rows

- **Row 21 (executable contracts) — adopted.** This file compiles under
  agent-conductor: the checklist below matches the parser's gate section and
  its commands execute as gates.
- **Row 23 (supply-chain discipline) — pending carrier.** The
  receipts/skills-lock/bundle-manifest kit extension lives in the archived
  `_cubiczan-shared` repo (push blocked); delivery waits on the
  owner-designated live `chp init` carrier. This file's contract + gates are
  the row-21 half, delivered now.

## Code change checklist

```bash
python -m pytest tests/ -q
```
