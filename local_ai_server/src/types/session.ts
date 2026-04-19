import type { CommandEvent, CommandResponse } from './command.ts';

export type SessionTurn = {
  turnId: string;
  commandId?: string;
  userInstruction: string;
  selectionSummary?: string;
  events: CommandEvent[];
  finalResponse?: CommandResponse;
  createdAt: string;
  updatedAt: string;
};

export type SessionState = {
  sessionId: string;
  createdAt: string;
  updatedAt: string;
  turns: SessionTurn[];
};
