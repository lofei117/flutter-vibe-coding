# Flutter Vibe Coding

In-app vibe coding for Flutter apps.

[简体中文](README.zh-CN.md)

This repository packages a local development loop where a Flutter app exposes an in-app AI panel through UME, sends structured edit requests to a local server, and applies small code changes back into the app with optional hot reload support.

## Status

Experimental, but runnable.

The project is currently optimized for local development and prototyping rather than production deployment. If you want to explore AI-assisted UI iteration directly inside a running Flutter app, this repo gives you a concrete starting point.

## What It Does

- Embeds an `AI Vibe Panel` inside a debug Flutter app
- Sends natural-language edit requests to a local server
- Supports a mock adapter for deterministic demo behavior
- Supports a Codex-backed adapter for broader code edits
- Streams command progress and approval state back to the client
- Can trigger hot reload in managed local workflows

## Repository Layout

```text
.
|-- flutter_vibe_app/   # Flutter client with UME integration
|-- packages/
|   `-- flutter_vibe_ume/  # Reusable UME vibe-coding package
|-- local_ai_server/    # Local TypeScript server and agent orchestration
|-- docs/               # Project documentation
`-- .github/            # CI and community health files
```

## Architecture

1. The Flutter app runs in debug mode with UME enabled.
2. `AI Vibe Panel` collects an instruction and optional runtime context.
3. The panel sends the request to the local server over HTTP.
4. The server routes the request through an adapter (`mock` or `codex`).
5. The adapter edits the Flutter project and reports changed files.
6. The server optionally triggers app reload and streams status updates back.

More detail lives in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Quick Start

### Prerequisites

- Flutter SDK
- Node.js 22+ recommended
- A local environment that can run Flutter debug builds

### 1. Start the local server

```bash
cd local_ai_server
npm ci
FLUTTER_PROJECT_PATH=../flutter_vibe_app npm run start
```

To use the Codex-backed adapter:

```bash
cd local_ai_server
npm ci
FLUTTER_PROJECT_PATH=../flutter_vibe_app npm run start:codex
```

### 2. Run the Flutter app

```bash
cd flutter_vibe_app
flutter pub get
flutter run -d chrome
```

You can also run on Android or iOS if your local toolchain is ready:

```bash
flutter run
```

### 3. Point the app at the server

Open UME, launch `AI Vibe Panel`, and save your local server URL.

For local desktop testing:

```text
http://127.0.0.1:8787
```

For a physical device on the same network, use your machine's LAN IP:

```text
http://192.168.x.x:8787
```

## Example Instruction

```text
Make the button green and change the label to Start.
```

In mock mode, this updates the demo home screen constants in [flutter_vibe_app/lib/home_page.dart](flutter_vibe_app/lib/home_page.dart).

## Environment Variables

### Server

- `PORT`: server port, default `8787`
- `HOST`: bind host, default `0.0.0.0`
- `FLUTTER_PROJECT_PATH`: target Flutter project path
- `AGENT_ADAPTER`: `mock` or `codex`
- `AUTO_START_FLUTTER`: start and manage `flutter run` automatically
- `FLUTTER_RELOAD_COMMAND`: custom reload command

### Codex adapter

- `CODEX_BIN`: override the Codex binary
- `CODEX_MODEL`: pass `--model` to `codex exec`
- `CODEX_PROFILE`: pass `--profile` to `codex exec`
- `CODEX_COMMAND`: override the full Codex command

## Development

### Type check server

```bash
cd local_ai_server
npm run typecheck
```

### Analyze and test Flutter app

```bash
cd flutter_vibe_app
flutter analyze
flutter test
```

## Known Limits

- This is still a local-first prototype, not a hardened remote execution platform.
- The mock adapter only covers a narrow demo instruction set.
- Hot reload automation depends on how the Flutter process is launched.
- Web support is intentionally constrained by UME package compatibility.

## Roadmap

- Better component selection and runtime context capture
- Richer approval and safety policies
- Multi-turn editing history
- Regression testing around generated edits
- Stronger mobile-device workflows

## Contributing

Contributions are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md).

For security-sensitive issues, use [SECURITY.md](SECURITY.md).

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
