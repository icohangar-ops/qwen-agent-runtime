# SurrealDB Setup Guide

## Overview

SurrealDB v3.0.5 is the multi-model database powering the Senso ecosystem.
It runs on each node and provides document, graph, relational, vector, and
time-series storage in a single binary.

## Architecture

| Database | Namespace | Purpose |
|----------|-----------|---------|
| `knowledge` | `senso` | Senso.AI knowledge base (documents, categories, search) |
| `agent_runtime` | `senso` | Agent sessions, command history, audit logs, guardrails |
| `clinical` | `healthguard` | HealthGuard AI patient records, vitals, labs, alerts |

## Installation

### Mac Server
```bash
curl --proto '=https' --tlsv1.2 -sSf https://install.surrealdb.com | sh
```

### Windows Laptops (PowerShell)
```powershell
iwr https://windows.surrealdb.com -useb | iex
```

Or via Scoop:
```powershell
scoop install surrealdb
```

## Starting the Server

### Development (in-memory)
```bash
surreal start --user root --pass root memory
```

### Production (persistent with RocksDB)
```bash
surreal start --user root --pass root rocksdb:./data
```

### With specific bind address (for agent-to-agent communication)
```bash
surreal start --user root --pass root --bind 0.0.0.0:8000 rocksdb:./data
```

## Loading Schemas

### Knowledge Base
```bash
surreal sql --user root --pass root --ns senso --db knowledge < db/schemas/knowledge-base.surql
```

### Agent Runtime (Audit Logging)
```bash
surreal sql --user root --pass root --ns senso --db agent_runtime < db/schemas/agent-runtime.surql
```

### HealthGuard Clinical
```bash
surreal sql --user root --pass root --ns healthguard --db clinical < db/schemas/healthguard-clinical.surql
```

## HTTP API

```bash
# Query
curl -X POST http://localhost:8000/sql \
  -H "Content-Type: application/json" \
  -H "NS: senso" \
  -H "DB: knowledge" \
  -u "root:root" \
  -d '[{"sql":"SELECT * FROM repository"}]'

# Full-text search
curl -X POST http://localhost:8000/sql \
  -H "Content-Type: application/json" \
  -H "NS: senso" \
  -H "DB: knowledge" \
  -u "root:root" \
  -d '[{"sql":"SELECT * FROM document WHERE content @@ '\''agent guardrails'\''"}]'
```

## Python SDK

```python
from surrealdb import Surreal

async def main():
    async with Surreal("http://localhost:8000") as db:
        await db.signin({
            "username": "root",
            "password": "root"
        })
        await db.use("senso", "knowledge")

        # Create a document
        await db.create("repository", {
            "name": "qwen-agent-runtime",
            "description": "AI-powered shell command execution",
            "platform": "codeberg",
            "language": "python"
        })

        # Query
        repos = await db.select("repository")
        for repo in repos:
            print(repo["name"])

        # Full-text search
        results = await db.query(
            "SELECT * FROM document WHERE content @@ $query",
            {"query": "agent guardrails deny-list"}
        )
```

## Key Features Used

### 1. Multi-Model Storage
- **Documents**: Knowledge base articles, patient records
- **Graph**: Doctor-patient relationships, document cross-references
- **Relational**: Appointments, guardrail rules
- **Time-Series**: Patient vitals, agent heartbeats
- **Vector**: Semantic search on knowledge base documents
- **Geospatial**: Facility locations for proximity queries

### 2. Row-Level Security
Each agent only sees its own session data:
```surql
DEFINE TABLE command SCHEMAFULL
    PERMISSIONS
        FOR select WHERE session.agent = $auth.agent OR $auth.level >= 'admin';
```

### 3. Real-Time Live Queries
Subscribe to new events across the cluster:
```surql
LIVE SELECT * FROM command PARALLEL;
LIVE SELECT * FROM ai_alert WHERE status = 'new' PARALLEL;
```

### 4. Auto-Events (Triggers)
Guardrail hit counters, audit log entries, status change tracking:
```surql
DEFINE EVENT update_guardrail_hits ON TABLE triggered_rule
    WHEN $event = 'CREATE' THEN (
        UPDATE $after.out SET hit_count += 1, last_hit = time::now()
    );
```

### 5. Graph Traversal
Find documents referencing a specific paper:
```surql
SELECT <-references.in.title FROM document WHERE id = document:abc123;
```

## Schema Files

| File | Description | Tables |
|------|-------------|--------|
| `knowledge-base.surql` | Senso.AI knowledge base | repository, document, category, graph edges |
| `agent-runtime.surql` | Agent session/audit logging | agent_node, session, command, audit_log, guardrail_rule |
| `healthguard-clinical.surql` | HealthGuard patient data | patient, provider, facility, vital_sign, lab_result, ai_alert |
