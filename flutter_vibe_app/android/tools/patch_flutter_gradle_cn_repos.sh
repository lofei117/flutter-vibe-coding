#!/usr/bin/env bash
# Flutter SDK 里复合构建与 buildscript 默认走 google()/mavenCentral()，会直连 repo.maven.apache.org。
# flutter upgrade 会覆盖本补丁，升级后请重新执行本脚本。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PROP="$ROOT/android/local.properties"
if [[ ! -f "$PROP" ]]; then
  echo "missing $PROP" >&2
  exit 1
fi
FLUTTER_SDK="$(grep '^flutter\.sdk=' "$PROP" | cut -d= -f2- | tr -d '\r')"
if [[ -z "${FLUTTER_SDK:-}" || ! -d "$FLUTTER_SDK" ]]; then
  echo "invalid flutter.sdk in local.properties: $FLUTTER_SDK" >&2
  exit 1
fi

SETTINGS="$FLUTTER_SDK/packages/flutter_tools/gradle/settings.gradle.kts"
CHECKER="$FLUTTER_SDK/packages/flutter_tools/gradle/src/main/kotlin/dependency_version_checker.gradle.kts"
GROOVY="$FLUTTER_SDK/packages/flutter_tools/gradle/src/main/groovy/flutter.groovy"

mark='maven.aliyun.com/repository/public'

if grep -q "$mark" "$SETTINGS" 2>/dev/null; then
  echo "already patched: $SETTINGS"
else
  echo "patching $SETTINGS"
  python3 << 'PY' "$SETTINGS"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = """dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}"""
new = """dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/public/") }
        maven { url = uri("https://maven.aliyun.com/repository/google/") }
        maven { url = uri("https://maven.aliyun.com/repository/central/") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin/") }
        google()
        mavenCentral()
    }
}"""
if old not in text:
    sys.exit("settings.gradle.kts pattern mismatch — Flutter SDK version may have changed; patch manually.")
p.write_text(text.replace(old, new, 1))
PY
fi

if grep -q "$mark" "$CHECKER" 2>/dev/null; then
  echo "already patched: $CHECKER"
else
  echo "patching $CHECKER"
  python3 << 'PY' "$CHECKER"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = """buildscript {
    repositories {
        google()
        mavenCentral()
    }"""
new = """buildscript {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/public/") }
        maven { url = uri("https://maven.aliyun.com/repository/google/") }
        maven { url = uri("https://maven.aliyun.com/repository/central/") }
        google()
        mavenCentral()
    }"""
if old not in text:
    sys.exit("dependency_version_checker.gradle.kts pattern mismatch — Flutter SDK version may have changed.")
p.write_text(text.replace(old, new, 1))
PY
fi

if grep -q "$mark" "$GROOVY" 2>/dev/null; then
  echo "already patched: $GROOVY"
else
  echo "patching $GROOVY"
  python3 << 'PY' "$GROOVY"
import pathlib, sys
p = pathlib.Path(sys.argv[1])
text = p.read_text()
old = """buildscript {
    repositories {
        google()
        mavenCentral()
    }"""
new = """buildscript {
    repositories {
        maven { url 'https://maven.aliyun.com/repository/public/' }
        maven { url 'https://maven.aliyun.com/repository/google/' }
        maven { url 'https://maven.aliyun.com/repository/central/' }
        google()
        mavenCentral()
    }"""
if old not in text:
    sys.exit("flutter.groovy pattern mismatch — Flutter SDK version may have changed.")
p.write_text(text.replace(old, new, 1))
PY
fi

echo "done. Flutter SDK: $FLUTTER_SDK"
