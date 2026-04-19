# Mobile Vibe Coding Demo

This is a minimal local demo for a mobile vibe coding loop:

1. A Flutter app starts with UME Core enabled in debug mode.
2. UME registers a custom `AI Vibe Panel`.
3. The panel sends a natural language instruction to a Mac-local HTTP server.
4. The server applies a small code change to the Flutter project.
5. The server tries to trigger hot reload, or tells you to press `r`.

The first version intentionally uses a mock agent so the loop can run without a real Codex CLI. Chrome Web is the fastest first validation target; Android/iOS can follow once the mobile build chain is healthy.

## Directory Structure

```text
project-root/
  mobile_vibe_demo/
    lib/
      main.dart
      app.dart
      home_page.dart
      ume_plugins/
        ai_vibe_panel.dart
        server_config_store.dart
        api_client.dart
    pubspec.yaml

  local_ai_server/
    src/
      index.ts
      routes/
        health.ts
        command.ts
      services/
        agent_service.ts
        flutter_reload_service.ts
        project_context_service.ts
      adapters/
        codex_adapter.ts
        mock_agent_adapter.ts
      types/
        index.ts
    package.json
```

## Flutter Client

The current machine's `flutter create` command crashed while generating platform files, so this repo contains the Flutter source and pubspec. If `android/` and `ios/` do not exist yet, generate them once:

```bash
cd mobile_vibe_demo
flutter create --platforms=android,ios .
flutter pub get
```

Then run the app on Chrome:

```bash
flutter run -d chrome
```

Or run it on a mobile device:

```bash
flutter run
```

For a physical phone, make sure the Mac and phone are on the same network. UME Core is enabled only in debug mode.

## Mac Local Server

Start the server. This version uses Node's built-in HTTP server and has no runtime npm dependencies:

```bash
cd local_ai_server
FLUTTER_PROJECT_PATH=../mobile_vibe_demo npm run start
```

The script uses `node --experimental-strip-types`, which works on the Node v23 runtime available in this workspace. If you prefer compiling TypeScript first, run `npm install` later and replace the script with your own `tsc` or `tsx` workflow.

Health check:

```bash
curl http://localhost:8787/health
```

From a phone, use the Mac LAN IP, for example:

```text
http://192.168.31.10:8787
```

## Configure Server URL

Open UME in the Flutter app, enter the Mac server URL in `AI Vibe Panel`, then tap `Save Server URL`.

The URL is saved with `shared_preferences`, so it survives app restarts.

## Send A Demo Instruction

In `AI Vibe Panel`, send:

```text
把按钮改成绿色，并把文案改成 Start
```

The mock adapter edits:

```text
mobile_vibe_demo/lib/home_page.dart
```

It changes:

```dart
const String homeButtonLabel = 'Start';
const Color homeButtonColor = Colors.green;
```

## Hot Reload

The server supports three reload modes.

Default mode:

```text
The server edits code and returns a message asking you to press r in the flutter run terminal.
```

Managed mode:

```bash
cd local_ai_server
AUTO_START_FLUTTER=true FLUTTER_PROJECT_PATH=../mobile_vibe_demo npm run start
```

In managed mode, the server starts `flutter run` and sends `r` to that process after code changes.

Custom reload command:

```bash
FLUTTER_RELOAD_COMMAND="your reload command" FLUTTER_PROJECT_PATH=../mobile_vibe_demo npm run start
```

Use this if you later wire up `flutter attach`, a custom script, or another local workflow.

## Mock Adapter

Default adapter:

```bash
AGENT_ADAPTER=mock npm run start
```

Supported MVP rules:

- `绿色` or `green`: set the home button color to green.
- `Start` or `开始`: set the button label to `Start`.
- `标题` or `title`: update the home title with a simple extracted value.

This is enough to verify the full local loop before plugging in a real agent.

## Codex Adapter

The Codex adapter calls your local Codex CLI by default. It runs Codex inside the Flutter project,
lets Codex edit files directly, then compares a lightweight before/after file snapshot so the
client can see which files changed.

```bash
cd local_ai_server
FLUTTER_PROJECT_PATH=../mobile_vibe_demo npm run start:codex
```

Equivalent explicit form:

```bash
AGENT_ADAPTER=codex FLUTTER_PROJECT_PATH=../mobile_vibe_demo npm run start
```

Default Codex invocation:

```bash
codex exec --full-auto --skip-git-repo-check --cd <flutter-project-path> -
```

Optional environment variables:

- `CODEX_BIN`: override the Codex binary path. Defaults to `codex`.
- `CODEX_MODEL`: pass a model to `codex exec --model`.
- `CODEX_PROFILE`: pass a profile to `codex exec --profile`.
- `CODEX_COMMAND`: advanced escape hatch. If set, the server runs this shell command instead of the default `codex exec` command and sends the prompt through stdin.

`local_ai_server/src/adapters/codex_adapter.ts` centralizes the invocation. The default contract is:

- Codex runs inside the Flutter project path;
- the prompt is sent through stdin;
- Codex edits files directly;
- if Codex changes tracked source/config files, the server returns those relative paths;
- if the command fails, the server falls back to the mock adapter.

This means you can send broader instructions from `AI Vibe Panel`, for example:

```text
分析首页结构，把按钮文案改得更像一个创建任务入口，并保持界面简洁
```

## Verify Success

1. Start the local server.
2. Start the Flutter app.
3. Open UME and choose `AI Vibe Panel`.
4. Save your Mac server URL.
5. Send `把按钮改成绿色，并把文案改成 Start`.
6. Check server logs for:
   - received instruction;
   - collected project files;
   - changed file path;
   - reload behavior.
7. If reload was not automatic, press `r` in the `flutter run` terminal.
8. The button should become green and its text should become `Start`.

## Known Limits

- The mock agent only edits `lib/home_page.dart`.
- The Flutter app uses `ume_core` directly. The aggregate `ume` package pulls in kits such as memory detector that import `dart:ffi`, which does not compile for Web.
- Automatic hot reload works only when the server owns the `flutter run` process or a custom reload command is configured.
- Multi-turn history, runtime widget selection, voice input, operation trace capture, and automated regression tests are phase 2 TODOs.
- The current source was generated manually because `flutter create` crashed in this environment; run `flutter create --platforms=android,ios .` inside `mobile_vibe_demo` if platform folders are missing.
