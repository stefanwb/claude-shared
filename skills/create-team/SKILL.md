---
name: create-team
description: Creates a new team using TeamCreate and runs the agents in the foreground. Use when the user says "create a team".
argument-hint: [team-name and agent descriptions]
---

# Create Team Skill

When the user says "create a team", use the `TeamCreate` tool to create a new team.

**Important**: All agents on the team must run in the **foreground** (not background).

Use `$ARGUMENTS` to determine the agent configuration. If the user hasn't provided enough detail, ask for:
1. Agent roles/names and their responsibilities
2. The task the team should work on

**Team naming**: Do NOT ask the user for a team name. Instead, generate a suitable name based on the context, goal, and team composition (e.g., `infra-migration-team`, `api-redesign-squad`).

**Team size cap**: every teammate is a spawned agent and counts toward the delegation policy of at most **2 agents per session without explicit approval**. Before creating a team of more than 2 agents (or a team of any size when agents were already spawned this session), list the proposed roster with one line per role and wait for the user's explicit approval. Do not create the team or spawn teammates until it is given. When the `limit-agent-spawns` hook is installed it enforces this cap and its denial message tells you how the user can raise it.
