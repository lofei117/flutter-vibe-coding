import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import type { ProjectContext, ProjectFile } from '../types/agent.ts';
import { evaluateProjectPath, SafetyError } from './safety_policy.ts';

const DEFAULT_FILES = [
  'lib/main.dart',
  'lib/app.dart',
  'lib/home_page.dart',
];

export class ProjectContextService {
  getAllowedRoot(): string {
    return path.resolve(
      process.env.FLUTTER_PROJECT_PATH ??
        path.join(process.cwd(), '..', 'mobile_vibe_demo'),
    );
  }

  resolveProjectPath(projectPathFromRequest?: string): string {
    const allowedRoot = this.getAllowedRoot();
    const projectPath = projectPathFromRequest
      ? path.resolve(projectPathFromRequest)
      : allowedRoot;
    const decision = evaluateProjectPath(projectPath, { allowedRoot });
    if (!decision.allowed) {
      throw new SafetyError(decision);
    }
    return projectPath;
  }

  async collect(projectPathFromRequest?: string): Promise<ProjectContext> {
    const projectPath = this.resolveProjectPath(projectPathFromRequest);

    const files: ProjectFile[] = [];
    for (const relativePath of DEFAULT_FILES) {
      const fullPath = path.join(projectPath, relativePath);
      try {
        await access(fullPath);
        files.push({
          path: fullPath,
          relativePath,
          content: await readFile(fullPath, 'utf8'),
        });
      } catch {
        console.warn(`[context] skipped missing file: ${fullPath}`);
      }
    }

    if (files.length === 0) {
      throw new Error(`No Flutter source files found under ${projectPath}`);
    }

    console.log(`[context] collected ${files.length} files from ${projectPath}`);
    return { projectPath, files };
  }

  async readFileSafe(
    projectPath: string,
    relativePath: string,
  ): Promise<ProjectFile | null> {
    const projectRoot = path.resolve(projectPath);
    const fullPath = path.resolve(projectRoot, relativePath);
    if (!fullPath.startsWith(projectRoot + path.sep) && fullPath !== projectRoot) {
      return null;
    }
    try {
      const content = await readFile(fullPath, 'utf8');
      return {
        path: fullPath,
        relativePath: path.relative(projectRoot, fullPath),
        content,
      };
    } catch {
      return null;
    }
  }
}
