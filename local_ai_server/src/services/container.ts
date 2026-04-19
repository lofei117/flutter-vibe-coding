import { AgentService } from './agent_service.ts';
import { AppSessionManager, getAppSessionManager } from './app_session_manager.ts';
import { CommandOrchestrator } from './command_orchestrator.ts';
import { ContextAssembler } from './context_assembler.ts';
import { FlutterReloadService } from './flutter_reload_service.ts';
import { PatchGuardService } from './patch_guard_service.ts';
import { ProjectContextService } from './project_context_service.ts';
import { SessionStore, getSessionStore } from './session_store.ts';

export type ServiceContainer = {
  projects: ProjectContextService;
  contextAssembler: ContextAssembler;
  agents: AgentService;
  patchGuard: PatchGuardService;
  appSessions: AppSessionManager;
  reload: FlutterReloadService;
  sessionStore: SessionStore;
  orchestrator: CommandOrchestrator;
};

let container: ServiceContainer | null = null;

export async function buildContainer(): Promise<ServiceContainer> {
  if (container) return container;

  const projects = new ProjectContextService();
  const contextAssembler = new ContextAssembler(projects);
  const agents = new AgentService();
  const patchGuard = new PatchGuardService();
  const appSessions = getAppSessionManager(projects);
  const reload = new FlutterReloadService(appSessions);
  const sessionStore = getSessionStore();
  await sessionStore.load();

  const orchestrator = new CommandOrchestrator({
    projects,
    contextAssembler,
    agents,
    patchGuard,
    reload,
    appSessions,
    sessionStore,
  });

  container = {
    projects,
    contextAssembler,
    agents,
    patchGuard,
    appSessions,
    reload,
    sessionStore,
    orchestrator,
  };
  return container;
}

export function getContainer(): ServiceContainer {
  if (!container) {
    throw new Error('Service container not built yet.');
  }
  return container;
}
