import type { TerritoryTreeNode } from './types';

export interface FlatTerritoryRow {
  key: string;
  id: string | null;
  name: string;
  depth: number;
  depthStyle: string;
  level?: string;
  hasChildren: boolean;
  expanded: boolean;
  chevronIcon: string;
  rowClass: string;
  isAll?: boolean;
  assignedUserName?: string;
  statusLabel?: string;
}

export function flattenTerritoryTree(
  roots: TerritoryTreeNode[],
  expandedIds: Set<string>,
  opts: {
    selectedId?: string | null;
    includeAllRow?: boolean;
    depthOffset?: number;
    extraRowFields?: (node: TerritoryTreeNode, depth: number) => Record<string, unknown>;
  } = {}
): FlatTerritoryRow[] {
  const rows: FlatTerritoryRow[] = [];
  if (opts.includeAllRow) {
    rows.push({
      key: 'all',
      id: null,
      name: 'All Territories',
      depth: 0,
      depthStyle: 'padding-left: 0',
      hasChildren: false,
      expanded: false,
      chevronIcon: '',
      rowClass: !opts.selectedId ? 'tree-row tree-row--selected' : 'tree-row',
      isAll: true
    });
  }
  for (const root of roots) {
    flattenNode(root, opts.depthOffset ?? 0, rows, expandedIds, opts);
  }
  return rows;
}

function flattenNode(
  node: TerritoryTreeNode,
  depth: number,
  rows: FlatTerritoryRow[],
  expandedIds: Set<string>,
  opts: {
    selectedId?: string | null;
    extraRowFields?: (node: TerritoryTreeNode, depth: number) => Record<string, unknown>;
  }
): void {
  const expanded = expandedIds.has(node.id);
  rows.push({
    key: node.id,
    id: node.id,
    name: node.name,
    depth,
    depthStyle: `padding-left: ${depth * 1.25}rem`,
    level: node.level,
    hasChildren: !!node.hasChildren,
    expanded,
    chevronIcon: expanded ? 'chevrondown' : 'chevronright',
    rowClass: node.id === opts.selectedId ? 'tree-row tree-row--selected' : 'tree-row',
    ...(opts.extraRowFields?.(node, depth) ?? {})
  });
  if (expanded && node.children) {
    for (const child of node.children) {
      flattenNode(child, depth + 1, rows, expandedIds, opts);
    }
  }
}

export function initExpandedFromRoots(roots: TerritoryTreeNode[], depth = 2): Set<string> {
  const ids = new Set<string>();
  for (const root of roots) {
    ids.add(root.id);
    if (depth > 1 && root.children) {
      for (const child of root.children) {
        ids.add(child.id);
      }
    }
  }
  return ids;
}
