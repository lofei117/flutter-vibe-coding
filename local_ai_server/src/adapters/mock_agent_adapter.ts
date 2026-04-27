import type { AgentAdapter } from '../services/agent_service.ts';
import type {
  AgentContext,
  AgentPatchResult,
  ProjectFile,
} from '../types/agent.ts';
import type { SelectedComponentContext } from '../types/context.ts';

type MockTarget = 'home-button' | 'home-title' | 'unknown';

export class MockAgentAdapter implements AgentAdapter {
  async applyInstruction(context: AgentContext): Promise<AgentPatchResult> {
    const { instruction, project, selection, emit } = context;
    const homePage = findHomePage(context.candidateFiles, project.files);
    if (!homePage) {
      throw new Error('lib/home_page.dart is required for the mock adapter.');
    }

    const target = inferTarget(selection);
    emit('agent_log', `mock adapter target: ${target}`);

    let next = homePage.content;
    const logs: string[] = [`Target: ${target}.`];

    if (target === 'home-title' || /标题|title/i.test(instruction)) {
      const title = extractTitle(instruction) ?? 'Flutter Vibe Coding';
      next = replaceConstString(next, 'homeTitle', title);
      logs.push(`Set homeTitle to "${title}".`);
    }

    if (/翻译成中文|改成中文|中文/i.test(instruction)) {
      next = replaceConstString(next, 'homeTitle', 'Flutter 氛围编程');
      next = replaceConstString(next, 'homeDescription', '打开 UME，然后用 AI Vibe Panel 修改这个应用。');
      logs.push('Translated homeTitle and homeDescription to Chinese.');
    }

    if (target === 'home-button' || target === 'unknown') {
      if (/绿色|green/i.test(instruction)) {
        next = replaceConstColor(next, 'homeButtonColor', 'Colors.green');
        logs.push('Set homeButtonColor to Colors.green.');
      }
      if (/红色|red/i.test(instruction)) {
        next = replaceConstColor(next, 'homeButtonColor', 'Colors.red');
        logs.push('Set homeButtonColor to Colors.red.');
      }
      if (/蓝色|blue/i.test(instruction)) {
        next = replaceConstColor(next, 'homeButtonColor', 'Colors.blue');
        logs.push('Set homeButtonColor to Colors.blue.');
      }
      if (/Start|开始/i.test(instruction)) {
        next = replaceConstString(next, 'homeButtonLabel', 'Start');
        logs.push('Set homeButtonLabel to "Start".');
      }
    }

    const changed = next !== homePage.content;
    if (changed) {
      emit('patch_generated', `mock adapter generated patch for ${homePage.relativePath}`, {
        files: [homePage.relativePath],
      });
    }

    return {
      applied: changed,
      message: changed
        ? 'Mock agent applied the instruction.'
        : 'Mock agent did not find a supported rule for this instruction.',
      changedFiles: changed ? [homePage.relativePath] : [],
      patches: changed
        ? [
            {
              path: homePage.path,
              relativePath: homePage.relativePath,
              before: homePage.content,
              after: next,
            },
          ]
        : [],
      agentOutput:
        logs.join('\n') +
        '\nSupported mock rules: green/red/blue, Start/开始, title/标题.',
    };
  }
}

function findHomePage(
  candidateFiles: ProjectFile[],
  projectFiles: ProjectFile[],
): ProjectFile | undefined {
  return (
    candidateFiles.find((f) => f.relativePath === 'lib/home_page.dart') ??
    projectFiles.find((f) => f.relativePath === 'lib/home_page.dart')
  );
}

function inferTarget(
  selection: SelectedComponentContext | undefined,
): MockTarget {
  if (!selection) return 'unknown';
  const widget = selection.widget;
  const key = widget.key ?? '';
  const text = widget.text ?? '';
    if (
      /home\.helloButton|home\.button/i.test(key) ||
      widget.widgetType === 'FilledButton' ||
      widget.widgetType === 'ElevatedButton' ||
      widget.widgetType === 'TextButton' ||
      /Hello Button|StartWQ|Start/i.test(text)
    ) {
      return 'home-button';
    }
  const ancestorIsAppBar = (widget.ancestorChain ?? []).some(
    (a) => a.widgetType === 'AppBar',
  );
  if (
      /home\.title/i.test(key) ||
      ancestorIsAppBar ||
      widget.widgetType === 'AppBar' ||
      /Flutter Vibe Coding|Flutter 氛围编程/i.test(text)
    ) {
      return 'home-title';
    }
  return 'unknown';
}

function replaceConstString(source: string, name: string, value: string): string {
  const escaped = value.replace(/\\/g, '\\\\').replace(/'/g, "\\'");
  return source.replace(
    new RegExp(`const String ${name} = '[^']*';`),
    `const String ${name} = '${escaped}';`,
  );
}

function replaceConstColor(source: string, name: string, value: string): string {
  return source.replace(
    new RegExp(`const Color ${name} = Colors\\.[a-zA-Z]+;`),
    `const Color ${name} = ${value};`,
  );
}

function extractTitle(instruction: string): string | null {
  const quoted = instruction.match(/[“"']([^“"']+)[”"']/);
  if (quoted?.[1]) {
    return quoted[1].trim();
  }
  const chinese = instruction.match(/标题.*?(?:改成|修改为|变成|叫)([^，。,.]+)/);
  if (chinese?.[1]) {
    return chinese[1].trim();
  }
  const english = instruction.match(/title.*?(?:to|as)\s+([^,.]+)/i);
  if (english?.[1]) {
    return english[1].trim();
  }
  return null;
}
