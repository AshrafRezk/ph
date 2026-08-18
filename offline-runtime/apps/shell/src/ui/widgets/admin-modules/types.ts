import type { SqlExecutor } from '@osr/db';

export interface AdminModuleContext {
  embedded?: boolean;
  online: boolean;
  db: SqlExecutor | null;
  sfAuth?: { accessToken: string; instanceUrl: string } | null;
  invokeApex?: (method: string, params?: Record<string, unknown>) => Promise<unknown>;
  toast?: (detail: { title?: string; message?: string; variant?: string }) => void;
  openRecord?: (objectApi: string, id: string) => void;
  openTab?: (developerName: string) => void;
  openAdminModule?: (componentName: string, title?: string) => void;
}

export interface TerritoryTreeNode {
  id: string;
  name: string;
  level?: string;
  hasChildren?: boolean;
  children?: TerritoryTreeNode[];
  parentId?: string | null;
}
