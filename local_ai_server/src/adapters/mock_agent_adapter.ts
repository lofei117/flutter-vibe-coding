import type { AgentAdapter } from '../services/agent_service.ts';
import type { AgentPatchResult, ProjectContext } from '../types/index.ts';

export class MockAgentAdapter implements AgentAdapter {
  async applyInstruction(instruction: string, context: ProjectContext): Promise<AgentPatchResult> {
    const homePage = context.files.find((file) => file.relativePath === 'lib/home_page.dart');
    if (!homePage) {
      throw new Error('lib/home_page.dart is required for the mock adapter.');
    }

    let next = homePage.content;
    const logs: string[] = [];

    if (/绿色|green/i.test(instruction)) {
      next = replaceConstColor(next, 'homeButtonColor', 'Colors.green');
      logs.push('Set homeButtonColor to Colors.green.');
    }

    if (/Start|开始/i.test(instruction)) {
      next = replaceConstString(next, 'homeButtonLabel', 'Start');
      logs.push('Set homeButtonLabel to Start.');
    }

    if (/标题|title/i.test(instruction)) {
      const title = extractTitle(instruction) ?? 'Mobile Vibe Coding Demo';
      next = replaceConstString(next, 'homeTitle', title);
      logs.push(`Set homeTitle to ${title}.`);
    }

    const changed = next !== homePage.content;
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
      agentOutput: logs.length > 0
        ? logs.join('\n')
        : 'Supported mock rules: green/绿色, Start/开始, title/标题.',
    };
  }
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
