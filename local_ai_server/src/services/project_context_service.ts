import { access, readFile } from 'node:fs/promises';
import path from 'node:path';
import type { ProjectContext, ProjectFile } from '../types/index.ts';

const DEFAULT_FILES = [
  'lib/main.dart',
  'lib/app.dart',
  'lib/home_page.dart',
];

export class ProjectContextService {
  async collect(projectPathFromRequest?: string): Promise<ProjectContext> {
    const projectPath = path.resolve(
      projectPathFromRequest ??
        process.env.FLUTTER_PROJECT_PATH ??
        path.join(process.cwd(), '..', 'mobile_vibe_demo'),
    );

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
}
