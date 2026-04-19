import path from 'node:path';

export type RiskKind = 'reload' | 'restart' | 'full_rebuild';

export type RiskAssessment = {
  kind: RiskKind;
  reasons: string[];
  requiresApproval: boolean;
};

const REBUILD_FILES = new Set([
  'pubspec.yaml',
  'pubspec.lock',
  'analysis_options.yaml',
]);

const REBUILD_SEGMENTS = [
  // iOS
  'ios/Podfile',
  'ios/Podfile.lock',
  'ios/Runner/Info.plist',
  'ios/Runner.xcodeproj',
  'ios/Runner.xcworkspace',
  // Android
  'android/build.gradle',
  'android/app/build.gradle',
  'android/gradle.properties',
  'android/settings.gradle',
  'android/app/src/main/AndroidManifest.xml',
  // macOS / windows / linux
  'macos/Runner',
  'windows/runner',
  'linux/',
];

const RESTART_FILES = new Set(['lib/main.dart']);

/**
 * Given a list of relative paths changed by the agent, decide whether we can
 * just hot reload, need a hot restart, or need a full rebuild (which triggers
 * HITL confirmation).
 */
export function classifyRisk(relativePaths: string[]): RiskAssessment {
  const reasons: string[] = [];
  let kind: RiskKind = 'reload';

  for (const rel of relativePaths) {
    const norm = rel.split(path.sep).join('/');
    const base = norm.split('/').pop() ?? norm;

    if (REBUILD_FILES.has(base) || REBUILD_SEGMENTS.some((seg) => norm.startsWith(seg) || norm === seg)) {
      reasons.push(`${rel} requires a full rebuild.`);
      kind = 'full_rebuild';
      continue;
    }

    if (RESTART_FILES.has(norm)) {
      reasons.push(`${rel} requires a hot restart instead of a hot reload.`);
      if (kind === 'reload') kind = 'restart';
      continue;
    }

    if (norm.endsWith('.dart')) {
      // Regular dart file → hot reload is fine.
      continue;
    }

    // Unknown file type that still passed patch guard (e.g., README).
    reasons.push(`${rel} is a non-dart file; defaulting to hot restart.`);
    if (kind === 'reload') kind = 'restart';
  }

  return {
    kind,
    reasons,
    requiresApproval: kind === 'full_rebuild',
  };
}
