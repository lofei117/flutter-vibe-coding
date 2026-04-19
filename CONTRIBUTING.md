# Contributing

Thanks for your interest in contributing.

## Before You Start

- Open an issue for significant changes so the direction is clear early.
- Keep pull requests focused. Small, reviewable changes move fastest.
- Please avoid unrelated refactors in the same PR.

## Local Setup

### Flutter client

```bash
cd flutter_vibe_app
flutter pub get
```

### Local server

```bash
cd local_ai_server
npm ci
```

## Development Checks

Run the relevant checks before opening a PR:

```bash
cd local_ai_server
npm run typecheck
```

```bash
cd flutter_vibe_app
flutter analyze
flutter test
```

## Pull Request Guidelines

- Explain the user-facing change and the motivation.
- Mention any tradeoffs or follow-up work.
- Include screenshots or short recordings for UI changes when practical.
- Add or update tests when behavior changes.
- Update documentation if setup, architecture, or behavior changes.

## Scope

Good contribution areas:

- Flutter panel UX and runtime context capture
- Safety and approval workflows
- Agent adapter integration
- Documentation and examples
- Tests and developer tooling

## Code Style

- Follow existing project conventions.
- Prefer simple, local changes over broad abstraction.
- Keep names descriptive and comments minimal but useful.
