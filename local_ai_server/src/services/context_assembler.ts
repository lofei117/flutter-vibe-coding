import type {
  AgentContext,
  AgentEmit,
  ProjectContext,
  ProjectFile,
} from '../types/agent.ts';
import type { CommandRequest, ContextSummary } from '../types/command.ts';
import type { SelectedComponentContext } from '../types/context.ts';
import { ProjectContextService } from './project_context_service.ts';

const DEFAULT_FALLBACK_FILES = [
  'lib/main.dart',
  'lib/app.dart',
  'lib/home_page.dart',
];

const SNIPPET_RADIUS = 20;

export class ContextAssembler {
  private readonly projects: ProjectContextService;

  constructor(projects: ProjectContextService) {
    this.projects = projects;
  }

  async assemble(
    request: CommandRequest,
    project: ProjectContext,
    emit: AgentEmit,
  ): Promise<{ agentContext: AgentContext; summary: ContextSummary }> {
    const candidatePaths = this.pickCandidateFiles(request.selection);
    const candidateFiles = await this.loadCandidateFiles(project, candidatePaths);
    const snippet = await this.buildSnippet(project.projectPath, request.selection);

    const summary: ContextSummary = {
      selectedWidget: request.selection?.widget?.widgetType,
      selectedText: request.selection?.widget?.text,
      sourceLocationStatus: resolveSourceLocationStatus(request.selection),
      candidateFiles: candidateFiles.map((file) => file.relativePath),
    };

    if (!request.selection) {
      console.log('[context] selection: missing');
    } else {
      console.log(
        `[context] selection: ${request.selection.widget.widgetType}` +
          (request.selection.widget.text ? ` text="${request.selection.widget.text}"` : ''),
      );
      if (request.selection.sourceLocation.status === 'available') {
        console.log(
          `[context] sourceLocation: ${request.selection.sourceLocation.file}:${request.selection.sourceLocation.line}`,
        );
      } else {
        console.log(
          `[context] sourceLocation: unavailable (${request.selection.sourceLocation.reason})`,
        );
      }
    }
    console.log(
      `[context] candidateFiles: ${summary.candidateFiles.join(', ') || 'none'}`,
    );

    const agentContext: AgentContext = {
      instruction: request.instruction,
      selection: request.selection,
      runtimeContext: request.runtimeContext,
      candidateFiles,
      snippet,
      project,
      emit,
    };

    return { agentContext, summary };
  }

  private pickCandidateFiles(
    selection: SelectedComponentContext | undefined,
  ): string[] {
    const out = new Set<string>();
    if (selection?.codeContext?.candidateFiles) {
      for (const file of selection.codeContext.candidateFiles) {
        out.add(file);
      }
    }
    if (selection?.sourceLocation.status === 'available') {
      out.add(selection.sourceLocation.file);
    }
    if (selection?.widget?.ancestorChain) {
      for (const ancestor of selection.widget.ancestorChain) {
        if (ancestor.sourceLocation?.status === 'available') {
          out.add(ancestor.sourceLocation.file);
        }
      }
    }
    if (out.size === 0) {
      for (const fallback of DEFAULT_FALLBACK_FILES) {
        out.add(fallback);
      }
    }
    return [...out];
  }

  private async loadCandidateFiles(
    project: ProjectContext,
    relativePaths: string[],
  ): Promise<ProjectFile[]> {
    const result: ProjectFile[] = [];
    for (const relative of relativePaths) {
      const inProject = project.files.find((file) => file.relativePath === relative);
      if (inProject) {
        result.push(inProject);
        continue;
      }
      const loaded = await this.projects.readFileSafe(project.projectPath, relative);
      if (loaded) result.push(loaded);
    }
    return result;
  }

  private async buildSnippet(
    projectPath: string,
    selection: SelectedComponentContext | undefined,
  ): Promise<AgentContext['snippet']> {
    if (!selection || selection.sourceLocation.status !== 'available') {
      const explicit = selection?.codeContext?.snippet;
      return explicit
        ? {
            file: explicit.file,
            startLine: explicit.startLine,
            endLine: explicit.endLine,
            content: explicit.content,
          }
        : undefined;
    }

    const file = await this.projects.readFileSafe(
      projectPath,
      selection.sourceLocation.file,
    );
    if (!file) return undefined;

    const lines = file.content.split(/\r?\n/);
    const center = Math.max(1, selection.sourceLocation.line);
    const startLine = Math.max(1, center - SNIPPET_RADIUS);
    const endLine = Math.min(lines.length, center + SNIPPET_RADIUS);
    const content = lines.slice(startLine - 1, endLine).join('\n');
    return {
      file: file.relativePath,
      startLine,
      endLine,
      content,
    };
  }
}

function resolveSourceLocationStatus(
  selection: SelectedComponentContext | undefined,
): ContextSummary['sourceLocationStatus'] {
  if (!selection) return 'missing';
  return selection.sourceLocation.status === 'available' ? 'available' : 'unavailable';
}
