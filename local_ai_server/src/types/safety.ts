export type SafetyDecision = {
  allowed: boolean;
  level: 'safe' | 'needs_review' | 'blocked';
  reasons: string[];
  blockedOperations?: string[];
};

export type ApprovalRequest = {
  approvalId: string;
  title: string;
  summary: string;
  changedFiles: string[];
  diffPreview?: string;
  risks?: string[];
};

export type ApprovalDecision = {
  approvalId: string;
  decision: 'approved' | 'rejected' | 'revise';
  comment?: string;
};
