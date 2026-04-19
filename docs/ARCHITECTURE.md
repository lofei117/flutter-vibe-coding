# Architecture

## Overview

The project has three main pieces:

- `flutter_vibe_app`: a Flutter app that wires the demo UI and source registry
- `packages/flutter_vibe_ume`: a reusable UME package containing the AI panel
- `local_ai_server`: a local HTTP server that orchestrates edit requests

The goal is to shorten the loop between seeing a UI, describing a change, and
applying that change inside the running Flutter project.

## Flutter Side

The Flutter client:

- runs with UME enabled in debug mode
- registers `AI Vibe Panel` as a custom plugin
- captures server configuration
- gathers instruction text plus runtime context
- streams command progress and approval state back into the panel UI

Key files:

- [flutter_vibe_app/lib/main.dart](../flutter_vibe_app/lib/main.dart)
- [flutter_vibe_app/lib/source_registry.dart](../flutter_vibe_app/lib/source_registry.dart)
- [packages/flutter_vibe_ume/lib/flutter_vibe_ume.dart](../packages/flutter_vibe_ume/lib/flutter_vibe_ume.dart)

## Server Side

The local server:

- exposes HTTP routes for command submission, status, events, and app control
- validates and queues edit requests
- assembles project context
- routes requests through an adapter
- handles approval gates and event streaming
- optionally manages app reload/restart flows

Key files:

- [local_ai_server/src/index.ts](../local_ai_server/src/index.ts)
- [local_ai_server/src/routes/command.ts](../local_ai_server/src/routes/command.ts)
- [local_ai_server/src/services/command_orchestrator.ts](../local_ai_server/src/services/command_orchestrator.ts)

## Adapter Model

Two adapter modes exist today:

- `mock`: deterministic demo behavior for early validation
- `codex`: invokes Codex locally to perform broader edits

This split keeps the demo runnable even without live model integration while
still allowing a more capable path for local experimentation.

## Command Flow

1. User opens `AI Vibe Panel` in the Flutter app.
2. User submits an instruction.
3. Client sends the request to `POST /command`.
4. Server enqueues the command and emits status events.
5. Adapter edits the target Flutter project.
6. Server returns changed files, final status, and reload outcome.
7. Client renders progress, approval prompts, and final output.

## Safety Model

The current safety model is local and evolving. It includes:

- request classification
- approval checkpoints for higher-risk actions
- command/event logging
- guardrails around patch and command execution

This is still an experimental surface, so review behavior before using it
against important codebases.
