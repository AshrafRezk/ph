/** SQLite schema + repositories for Offline Salesforce Runtime */

export type SqlValue = string | number | null | Uint8Array;

export interface SqlExecutor {
  execute(sql: string, params?: SqlValue[]): Promise<{ rows: Record<string, unknown>[] }>;
  run(sql: string, params?: SqlValue[]): Promise<void>;
  transaction<T>(fn: (tx: SqlExecutor) => Promise<T>): Promise<T>;
}

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS meta_objects (
  api_name TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  key_prefix TEXT,
  describe_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS meta_layouts (
  id TEXT PRIMARY KEY,
  object_api TEXT NOT NULL,
  record_type_id TEXT,
  name TEXT NOT NULL,
  layout_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS meta_flexipages (
  id TEXT PRIMARY KEY,
  developer_name TEXT NOT NULL,
  type TEXT,
  page_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS meta_tabs (
  id TEXT PRIMARY KEY,
  developer_name TEXT NOT NULL,
  label TEXT NOT NULL,
  tab_json TEXT NOT NULL,
  sort_order INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS meta_apps (
  id TEXT PRIMARY KEY,
  developer_name TEXT NOT NULL,
  label TEXT NOT NULL,
  app_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS meta_validation_rules (
  id TEXT PRIMARY KEY,
  object_api TEXT NOT NULL,
  name TEXT NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  error_condition TEXT NOT NULL,
  error_message TEXT NOT NULL,
  error_display_field TEXT,
  rule_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS meta_lwc_registry (
  bundle_name TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  module_url TEXT,
  source_js TEXT,
  source_html TEXT,
  source_css TEXT,
  source_js_raw TEXT,
  source_meta_xml TEXT,
  source_kind TEXT,
  has_org_source INTEGER NOT NULL DEFAULT 0,
  meta_json TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS meta_listviews (
  id TEXT PRIMARY KEY,
  object_api TEXT NOT NULL,
  developer_name TEXT NOT NULL,
  label TEXT NOT NULL,
  listview_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_listviews_object ON meta_listviews(object_api);

CREATE TABLE IF NOT EXISTS meta_actions (
  id TEXT PRIMARY KEY,
  object_api TEXT NOT NULL,
  name TEXT NOT NULL,
  label TEXT NOT NULL,
  action_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_actions_object ON meta_actions(object_api);

CREATE TABLE IF NOT EXISTS meta_compact_layouts (
  id TEXT PRIMARY KEY,
  object_api TEXT NOT NULL,
  name TEXT NOT NULL,
  compact_json TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_compact_object ON meta_compact_layouts(object_api);

CREATE TABLE IF NOT EXISTS user_prefs (
  object_api TEXT PRIMARY KEY,
  favourites_json TEXT NOT NULL DEFAULT '[]',
  pinned_list_view_id TEXT,
  calendar_field TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS records (
  object_api TEXT NOT NULL,
  id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  version TEXT,
  deleted INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (object_api, id)
);

CREATE INDEX IF NOT EXISTS idx_records_object ON records(object_api, deleted);

CREATE TABLE IF NOT EXISTS files (
  content_version_id TEXT PRIMARY KEY,
  content_document_id TEXT,
  title TEXT,
  path TEXT NOT NULL,
  hash TEXT,
  size INTEGER,
  mime_type TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS outbox (
  id TEXT PRIMARY KEY,
  op TEXT NOT NULL,
  object_api TEXT,
  record_id TEXT,
  payload_json TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  attempts INTEGER NOT NULL DEFAULT 0,
  last_error TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_outbox_status ON outbox(status, created_at);

CREATE TABLE IF NOT EXISTS sync_state (
  channel TEXT PRIMARY KEY,
  cursor TEXT,
  last_ok_at TEXT,
  meta_json TEXT
);

CREATE TABLE IF NOT EXISTS conflicts (
  id TEXT PRIMARY KEY,
  outbox_id TEXT,
  object_api TEXT,
  record_id TEXT,
  server_json TEXT,
  client_json TEXT,
  resolution TEXT,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sharing_id_sets (
  object_api TEXT NOT NULL,
  record_id TEXT NOT NULL,
  profile_name TEXT NOT NULL,
  PRIMARY KEY (object_api, record_id, profile_name)
);

CREATE TABLE IF NOT EXISTS kv_secure (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS apex_payload_cache (
  cache_key TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  etag TEXT
);

CREATE TABLE IF NOT EXISTS static_resources (
  name TEXT PRIMARY KEY,
  content_type TEXT,
  body_b64 TEXT,
  size INTEGER,
  cache_control TEXT,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS location_trail (
  id TEXT PRIMARY KEY,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  accuracy_meters REAL,
  recorded_at TEXT NOT NULL,
  device_model TEXT,
  device_os TEXT,
  app_version TEXT,
  device_id TEXT,
  source TEXT NOT NULL DEFAULT 'Mobile',
  synced INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_location_trail_synced ON location_trail(synced, recorded_at);

CREATE TABLE IF NOT EXISTS logs (
  id TEXT PRIMARY KEY,
  category TEXT NOT NULL,
  source TEXT,
  message TEXT NOT NULL,
  detail_json TEXT,
  tags_json TEXT,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_logs_created ON logs(created_at);
CREATE INDEX IF NOT EXISTS idx_logs_category ON logs(category, created_at);
`;

export async function migrate(db: SqlExecutor): Promise<void> {
  for (const stmt of SCHEMA_SQL.split(';').map((s) => s.trim()).filter(Boolean)) {
    await db.run(stmt);
  }
  // Additive columns for LWC HTML/CSS/raw/controller metadata (older installs)
  const alters = [
    'ALTER TABLE meta_lwc_registry ADD COLUMN source_html TEXT',
    'ALTER TABLE meta_lwc_registry ADD COLUMN source_css TEXT',
    'ALTER TABLE meta_lwc_registry ADD COLUMN source_js_raw TEXT',
    'ALTER TABLE meta_lwc_registry ADD COLUMN source_meta_xml TEXT',
    'ALTER TABLE meta_lwc_registry ADD COLUMN source_kind TEXT',
    'ALTER TABLE meta_lwc_registry ADD COLUMN has_org_source INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE meta_lwc_registry ADD COLUMN meta_json TEXT'
  ];
  for (const sql of alters) {
    try {
      await db.run(sql);
    } catch {
      /* column already exists */
    }
  }
  // Ensure location_trail exists on older installs
  try {
    await db.run(`CREATE TABLE IF NOT EXISTS location_trail (
      id TEXT PRIMARY KEY,
      latitude REAL NOT NULL,
      longitude REAL NOT NULL,
      accuracy_meters REAL,
      recorded_at TEXT NOT NULL,
      device_model TEXT,
      device_os TEXT,
      app_version TEXT,
      device_id TEXT,
      source TEXT NOT NULL DEFAULT 'Mobile',
      synced INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL
    )`);
    await db.run(
      `CREATE INDEX IF NOT EXISTS idx_location_trail_synced ON location_trail(synced, recorded_at)`
    );
  } catch {
    /* ignore */
  }
  // Support / sync diagnostic logs (older installs)
  try {
    await db.run(`CREATE TABLE IF NOT EXISTS logs (
      id TEXT PRIMARY KEY,
      category TEXT NOT NULL,
      source TEXT,
      message TEXT NOT NULL,
      detail_json TEXT,
      tags_json TEXT,
      created_at TEXT NOT NULL
    )`);
    await db.run(`CREATE INDEX IF NOT EXISTS idx_logs_created ON logs(created_at)`);
    await db.run(`CREATE INDEX IF NOT EXISTS idx_logs_category ON logs(category, created_at)`);
  } catch {
    /* ignore */
  }
}

/** In-memory SQLite stand-in for web/unit tests when native plugin is absent */
export class MemorySqlExecutor implements SqlExecutor {
  private tables = new Map<string, Map<string, Record<string, unknown>>>();
  private rows: Record<string, unknown>[][] = [];

  async execute(sql: string, params: SqlValue[] = []): Promise<{ rows: Record<string, unknown>[] }> {
    const normalized = sql.replace(/\s+/g, ' ').trim();
    if (/^CREATE TABLE/i.test(normalized) || /^CREATE INDEX/i.test(normalized)) {
      return { rows: [] };
    }
    if (/^SELECT/i.test(normalized)) {
      return this.select(normalized, params);
    }
    return { rows: [] };
  }

  async run(sql: string, params: SqlValue[] = []): Promise<void> {
    const normalized = sql.replace(/\s+/g, ' ').trim();
    if (/^CREATE TABLE/i.test(normalized) || /^CREATE INDEX/i.test(normalized)) {
      const m = normalized.match(/CREATE TABLE IF NOT EXISTS (\w+)/i);
      if (m && !this.tables.has(m[1])) {
        this.tables.set(m[1], new Map());
      }
      return;
    }
    if (/^INSERT OR REPLACE INTO/i.test(normalized) || /^INSERT INTO/i.test(normalized)) {
      this.insert(normalized, params);
      return;
    }
    if (/^UPDATE/i.test(normalized)) {
      this.update(normalized, params);
      return;
    }
    if (/^DELETE/i.test(normalized)) {
      this.delete(normalized, params);
    }
  }

  async transaction<T>(fn: (tx: SqlExecutor) => Promise<T>): Promise<T> {
    return fn(this);
  }

  private tableName(sql: string): string {
    const m = sql.match(/(?:INTO|FROM|UPDATE)\s+(\w+)/i);
    if (!m) throw new Error(`Cannot parse table from: ${sql}`);
    return m[1];
  }

  private ensure(table: string): Map<string, Record<string, unknown>> {
    if (!this.tables.has(table)) this.tables.set(table, new Map());
    return this.tables.get(table)!;
  }

  private insert(sql: string, params: SqlValue[]): void {
    const table = this.tableName(sql);
    const colsMatch = sql.match(/\(([^)]+)\)\s*VALUES/i);
    if (!colsMatch) return;
    const cols = colsMatch[1].split(',').map((c) => c.trim());
    const row: Record<string, unknown> = {};
    cols.forEach((c, i) => {
      row[c] = params[i] ?? null;
    });
    const pk = (row.id as string)
      ?? (row.api_name as string)
      ?? (row.bundle_name as string)
      ?? (row.content_version_id as string)
      ?? (row.channel as string)
      ?? (row.cache_key as string)
      ?? (row.key as string)
      ?? `${row.object_api}:${row.id ?? row.record_id ?? Math.random()}`;
    // composite for records / sharing
    let key = String(pk);
    if (table === 'apex_payload_cache' && row.cache_key) {
      key = String(row.cache_key);
    }
    if (table === 'records' && row.object_api && row.id) {
      key = `${row.object_api}:${row.id}`;
    }
    if (table === 'user_prefs' && row.object_api) {
      key = String(row.object_api);
    }
    if (table === 'sharing_id_sets') {
      key = `${row.object_api}:${row.record_id}:${row.profile_name}`;
    }
    this.ensure(table).set(key, row);
  }

  private update(sql: string, params: SqlValue[]): void {
    const table = this.tableName(sql);
    const store = this.ensure(table);
    // Simple: UPDATE outbox SET status=?, attempts=?, last_error=?, updated_at=? WHERE id=?
    if (table === 'outbox' && /WHERE id=/i.test(sql)) {
      const id = String(params[params.length - 1]);
      const existing = store.get(id);
      if (!existing) return;
      const setMatch = sql.match(/SET (.+) WHERE/i);
      if (!setMatch) return;
      const assignments = setMatch[1].split(',').map((a) => a.trim().split('=')[0].trim());
      assignments.forEach((col, i) => {
        existing[col] = params[i];
      });
      store.set(id, existing);
    }
    if (table === 'conflicts' && /WHERE id=/i.test(sql)) {
      const id = String(params[params.length - 1]);
      const existing = store.get(id);
      if (!existing) return;
      existing.resolution = params[0];
      store.set(id, existing);
    }
  }

  private delete(sql: string, params: SqlValue[]): void {
    const table = this.tableName(sql);
    const store = this.ensure(table);
    if (table === 'sharing_id_sets' && /WHERE profile_name=\? AND object_api=\?/i.test(sql)) {
      for (const [k, row] of [...store.entries()]) {
        if (row.profile_name === params[0] && row.object_api === params[1]) store.delete(k);
      }
      return;
    }
    if (table === 'logs' && /WHERE category=\?/i.test(sql)) {
      for (const [k, row] of [...store.entries()]) {
        if (row.category === params[0]) store.delete(k);
      }
      return;
    }
    if (table === 'logs' && !/WHERE/i.test(sql)) {
      store.clear();
      return;
    }
    if (/WHERE id=/i.test(sql)) {
      store.delete(String(params[0]));
      return;
    }
    if (/WHERE object_api=\? AND id=\?/i.test(sql)) {
      store.delete(`${params[0]}:${params[1]}`);
    }
  }

  private select(sql: string, params: SqlValue[]): { rows: Record<string, unknown>[] } {
    const table = this.tableName(sql);
    const store = this.ensure(table);
    let rows = [...store.values()];

    if (/WHERE channel=\?/i.test(sql)) {
      rows = rows.filter((r) => r.channel === params[0]);
    } else if (/WHERE object_api=\? AND id=\?/i.test(sql)) {
      rows = rows.filter((r) => r.object_api === params[0] && r.id === params[1]);
    } else if (/WHERE object_api=\? AND deleted=0/i.test(sql)) {
      rows = rows.filter((r) => r.object_api === params[0] && Number(r.deleted) === 0);
    } else if (/WHERE object_api=\?/i.test(sql) && table === 'meta_validation_rules') {
      rows = rows.filter((r) => r.object_api === params[0] && Number(r.active) === 1);
    } else if (/WHERE object_api=\?/i.test(sql) && table === 'meta_layouts') {
      rows = rows.filter((r) => r.object_api === params[0]);
      if (params.length > 1) {
        rows = rows.filter((r) => r.record_type_id === params[1] || r.record_type_id == null);
      }
    } else if (/WHERE object_api=\?/i.test(sql) && table === 'meta_actions') {
      const all = [...this.ensure(table).values()].filter((r) => r.object_api === params[0]);
      return { rows: all };
    } else if (
      /WHERE object_api=\?/i.test(sql) &&
      table === 'meta_compact_layouts'
    ) {
      const all = [...this.ensure(table).values()].filter((r) => r.object_api === params[0]);
      return { rows: all.slice(0, 1) };
    } else if (/WHERE object_api=\?/i.test(sql) && table === 'meta_listviews') {
      rows = rows.filter((r) => r.object_api === params[0]);
    } else if (/WHERE object_api=\?/i.test(sql) && table === 'user_prefs') {
      rows = rows.filter((r) => r.object_api === params[0]);
    } else if (/FROM user_prefs/i.test(sql) && !/WHERE/i.test(sql)) {
      // list all user prefs
    } else if (/WHERE deleted=0/i.test(sql) && table === 'records' && !/object_api=\?/i.test(sql)) {
      rows = rows.filter((r) => Number(r.deleted) === 0);
    } else if (/WHERE api_name=\?/i.test(sql)) {
      rows = rows.filter((r) => r.api_name === params[0]);
    } else if (/WHERE id=\?/i.test(sql)) {
      rows = rows.filter((r) => r.id === params[0]);
    } else if (/WHERE developer_name=\?/i.test(sql)) {
      rows = rows.filter((r) => r.developer_name === params[0]);
    } else if (/WHERE bundle_name=\?/i.test(sql)) {
      rows = rows.filter((r) => r.bundle_name === params[0]);
    } else if (/WHERE cache_key=\?/i.test(sql)) {
      rows = rows.filter((r) => r.cache_key === params[0]);
    } else if (/WHERE content_version_id=\?/i.test(sql)) {
      rows = rows.filter((r) => r.content_version_id === params[0]);
    } else if (/WHERE status=\?/i.test(sql)) {
      rows = rows.filter((r) => r.status === params[0]);
      rows.sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));
    } else if (/WHERE status IN/i.test(sql) && table === 'outbox') {
      const statuses = new Set(params.slice(0, -1).map(String));
      rows = rows.filter((r) => statuses.has(String(r.status)));
      rows.sort((a, b) => String(b.updated_at ?? b.created_at).localeCompare(String(a.updated_at ?? a.created_at)));
    } else if (/WHERE category=\?/i.test(sql) && table === 'logs') {
      rows = rows.filter((r) => r.category === params[0]);
    } else if (/WHERE resolution IS NULL/i.test(sql)) {
      rows = rows.filter((r) => r.resolution == null || r.resolution === '');
    } else if (/WHERE key=\?/i.test(sql)) {
      rows = rows.filter((r) => r.key === params[0]);
    }

    if (/ORDER BY sort_order/i.test(sql)) {
      rows.sort((a, b) => Number(a.sort_order ?? 0) - Number(b.sort_order ?? 0));
    }
    if (/ORDER BY created_at DESC/i.test(sql)) {
      rows.sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
    } else if (/ORDER BY recorded_at DESC/i.test(sql)) {
      rows.sort((a, b) => String(b.recorded_at).localeCompare(String(a.recorded_at)));
    } else if (/ORDER BY updated_at DESC/i.test(sql)) {
      rows.sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)));
    }
    if (/LIMIT \?/i.test(sql)) {
      const lim = Number(params[params.length - 1]);
      rows = rows.slice(0, lim);
    }
    return { rows };
  }
}

export function nowIso(): string {
  return new Date().toISOString();
}

export function newId(prefix = 'osr'): string {
  return `${prefix}_${crypto.randomUUID()}`;
}

// ---- Repositories ----

export async function upsertObjectDescribe(
  db: SqlExecutor,
  apiName: string,
  label: string,
  describe: unknown,
  keyPrefix?: string
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_objects (api_name, label, key_prefix, describe_json, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
    [apiName, label, keyPrefix ?? null, JSON.stringify(describe), nowIso()]
  );
}

export async function getObjectDescribe(
  db: SqlExecutor,
  apiName: string
): Promise<Record<string, unknown> | null> {
  const { rows } = await db.execute(`SELECT * FROM meta_objects WHERE api_name=?`, [apiName]);
  if (!rows[0]) return null;
  return JSON.parse(String(rows[0].describe_json));
}

export async function upsertLayout(
  db: SqlExecutor,
  layout: {
    id: string;
    objectApi: string;
    recordTypeId?: string | null;
    name: string;
    layout: unknown;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_layouts (id, object_api, record_type_id, name, layout_json, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      layout.id,
      layout.objectApi,
      layout.recordTypeId ?? null,
      layout.name,
      JSON.stringify(layout.layout),
      nowIso()
    ]
  );
}

export async function getLayoutsForObject(
  db: SqlExecutor,
  objectApi: string,
  recordTypeId?: string | null
): Promise<Record<string, unknown>[]> {
  if (recordTypeId) {
    const { rows } = await db.execute(
      `SELECT * FROM meta_layouts WHERE object_api=? AND record_type_id=?`,
      [objectApi, recordTypeId]
    );
    if (rows.length) return rows.map((r) => JSON.parse(String(r.layout_json)));
  }
  const { rows } = await db.execute(`SELECT * FROM meta_layouts WHERE object_api=?`, [objectApi]);
  return rows.map((r) => JSON.parse(String(r.layout_json)));
}

export async function upsertFlexiPage(
  db: SqlExecutor,
  page: { id: string; developerName: string; type?: string; page: unknown }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_flexipages (id, developer_name, type, page_json, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
    [page.id, page.developerName, page.type ?? null, JSON.stringify(page.page), nowIso()]
  );
}

export async function getFlexiPage(
  db: SqlExecutor,
  developerName: string
): Promise<Record<string, unknown> | null> {
  const { rows } = await db.execute(
    `SELECT * FROM meta_flexipages WHERE developer_name=?`,
    [developerName]
  );
  if (!rows[0]) return null;
  return JSON.parse(String(rows[0].page_json));
}

export async function upsertTab(
  db: SqlExecutor,
  tab: { id: string; developerName: string; label: string; tab: unknown; sortOrder?: number }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_tabs (id, developer_name, label, tab_json, sort_order)
     VALUES (?, ?, ?, ?, ?)`,
    [tab.id, tab.developerName, tab.label, JSON.stringify(tab.tab), tab.sortOrder ?? 0]
  );
}

export async function listTabs(db: SqlExecutor): Promise<
  { id: string; developerName: string; label: string; tab: unknown }[]
> {
  const { rows } = await db.execute(`SELECT * FROM meta_tabs ORDER BY sort_order ASC`);
  return rows.map((r) => ({
    id: String(r.id),
    developerName: String(r.developer_name),
    label: String(r.label),
    tab: JSON.parse(String(r.tab_json))
  }));
}

export async function upsertApp(
  db: SqlExecutor,
  app: { id: string; developerName: string; label: string; app: unknown }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_apps (id, developer_name, label, app_json) VALUES (?, ?, ?, ?)`,
    [app.id, app.developerName, app.label, JSON.stringify(app.app)]
  );
}

export async function listApps(
  db: SqlExecutor
): Promise<{ id: string; developerName: string; label: string; app: Record<string, unknown> }[]> {
  const { rows } = await db.execute(`SELECT * FROM meta_apps ORDER BY label ASC`);
  return rows.map((r) => ({
    id: String(r.id),
    developerName: String(r.developer_name),
    label: String(r.label),
    app: JSON.parse(String(r.app_json)) as Record<string, unknown>
  }));
}

export async function getApp(
  db: SqlExecutor,
  developerName: string
): Promise<{ id: string; developerName: string; label: string; app: Record<string, unknown> } | null> {
  const { rows } = await db.execute(`SELECT * FROM meta_apps WHERE developer_name=?`, [
    developerName
  ]);
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: String(r.id),
    developerName: String(r.developer_name),
    label: String(r.label),
    app: JSON.parse(String(r.app_json)) as Record<string, unknown>
  };
}

export async function listFlexiPages(
  db: SqlExecutor
): Promise<{ id: string; developerName: string; type: string | null; page: Record<string, unknown> }[]> {
  const { rows } = await db.execute(`SELECT * FROM meta_flexipages ORDER BY developer_name ASC`);
  return rows.map((r) => ({
    id: String(r.id),
    developerName: String(r.developer_name),
    type: r.type == null ? null : String(r.type),
    page: JSON.parse(String(r.page_json)) as Record<string, unknown>
  }));
}

export async function findFlexiPageForObject(
  db: SqlExecutor,
  objectApi: string
): Promise<{ developerName: string; type: string | null; page: Record<string, unknown> } | null> {
  const preferred = `${objectApi}_Record_Page`;
  const byName = await getFlexiPageRow(db, preferred);
  if (byName) return byName;

  const all = await listFlexiPages(db);
  const match = all.find((p) => {
    const sobj = p.page.sobjectType;
    return (
      (p.type === 'RecordPage' || p.page.type === 'RecordPage') &&
      (sobj === objectApi || p.developerName.toLowerCase().includes(objectApi.toLowerCase()))
    );
  });
  return match
    ? { developerName: match.developerName, type: match.type, page: match.page }
    : null;
}

async function getFlexiPageRow(
  db: SqlExecutor,
  developerName: string
): Promise<{ developerName: string; type: string | null; page: Record<string, unknown> } | null> {
  const { rows } = await db.execute(
    `SELECT * FROM meta_flexipages WHERE developer_name=?`,
    [developerName]
  );
  if (!rows[0]) return null;
  return {
    developerName: String(rows[0].developer_name),
    type: rows[0].type == null ? null : String(rows[0].type),
    page: JSON.parse(String(rows[0].page_json)) as Record<string, unknown>
  };
}

export async function upsertValidationRule(
  db: SqlExecutor,
  rule: {
    id: string;
    objectApi: string;
    name: string;
    active: boolean;
    errorCondition: string;
    errorMessage: string;
    errorDisplayField?: string | null;
    rule: unknown;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_validation_rules
      (id, object_api, name, active, error_condition, error_message, error_display_field, rule_json)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      rule.id,
      rule.objectApi,
      rule.name,
      rule.active ? 1 : 0,
      rule.errorCondition,
      rule.errorMessage,
      rule.errorDisplayField ?? null,
      JSON.stringify(rule.rule)
    ]
  );
}

export async function getValidationRules(
  db: SqlExecutor,
  objectApi: string
): Promise<
  {
    id: string;
    name: string;
    errorCondition: string;
    errorMessage: string;
    errorDisplayField?: string | null;
  }[]
> {
  const { rows } = await db.execute(
    `SELECT * FROM meta_validation_rules WHERE object_api=? AND active=1`,
    [objectApi]
  );
  return rows.map((r) => ({
    id: String(r.id),
    name: String(r.name),
    errorCondition: String(r.error_condition),
    errorMessage: String(r.error_message),
    errorDisplayField: (r.error_display_field as string) ?? null
  }));
}

export async function upsertRecord(
  db: SqlExecutor,
  objectApi: string,
  id: string,
  payload: Record<string, unknown>,
  version?: string | null
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO records (object_api, id, payload_json, version, deleted, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [objectApi, id, JSON.stringify(payload), version ?? null, 0, nowIso()]
  );
}

export async function softDeleteRecord(
  db: SqlExecutor,
  objectApi: string,
  id: string
): Promise<void> {
  const existing = await getRecord(db, objectApi, id);
  await db.run(
    `INSERT OR REPLACE INTO records (object_api, id, payload_json, version, deleted, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [objectApi, id, JSON.stringify(existing ?? { Id: id }), null, 1, nowIso()]
  );
}

/** Undo a local soft-delete when server rejected the outbox delete. */
export async function restoreSoftDeletedRecord(
  db: SqlExecutor,
  objectApi: string,
  id: string
): Promise<void> {
  const { rows } = await db.execute(
    `SELECT payload_json, version FROM records WHERE object_api=? AND id=? AND deleted=1`,
    [objectApi, id]
  );
  if (!rows[0]) return;
  const versionRaw = rows[0].version;
  const version: SqlValue =
    typeof versionRaw === 'string' || typeof versionRaw === 'number' ? versionRaw : null;
  await db.run(
    `INSERT OR REPLACE INTO records (object_api, id, payload_json, version, deleted, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [objectApi, id, String(rows[0].payload_json), version, 0, nowIso()]
  );
}

/** After outbox create sync: replace local_* id with Salesforce Id in SQLite. */
export async function remapRecordId(
  db: SqlExecutor,
  objectApi: string,
  localId: string,
  serverId: string,
  serverPayload?: Record<string, unknown> | null
): Promise<void> {
  if (!localId.startsWith('local_') || localId === serverId) return;
  const existing = await getRecord(db, objectApi, localId);
  const payload = {
    ...(existing ?? {}),
    ...(serverPayload ?? {}),
    Id: serverId
  };
  await db.run(`DELETE FROM records WHERE object_api=? AND id=?`, [objectApi, localId]);
  await upsertRecord(db, objectApi, serverId, payload);
  await db.run(`UPDATE outbox SET record_id=? WHERE record_id=?`, [serverId, localId]);
}

export async function getRecord(
  db: SqlExecutor,
  objectApi: string,
  id: string
): Promise<Record<string, unknown> | null> {
  const { rows } = await db.execute(
    `SELECT * FROM records WHERE object_api=? AND id=?`,
    [objectApi, id]
  );
  if (!rows[0] || Number(rows[0].deleted) === 1) return null;
  return JSON.parse(String(rows[0].payload_json));
}

export async function listRecords(
  db: SqlExecutor,
  objectApi: string,
  limit = 200
): Promise<Record<string, unknown>[]> {
  const { rows } = await db.execute(
    `SELECT * FROM records WHERE object_api=? AND deleted=0 LIMIT ?`,
    [objectApi, limit]
  );
  return rows.map((r) => JSON.parse(String(r.payload_json)));
}

export type ListViewColumn = {
  fieldOrColumn: string;
  label?: string;
  type?: string;
  sortable?: boolean;
};

export type ListViewFilter = {
  field: string;
  operation: string;
  value?: string | null;
};

export type ListViewRow = {
  id: string;
  objectApi: string;
  developerName: string;
  label: string;
  listview: {
    id?: string;
    developerName?: string;
    label?: string;
    soqlCompatible?: boolean;
    query?: string;
    recordIds?: string[];
    /** @deprecated prefer columns with fieldOrColumn objects */
    columns?: string[] | ListViewColumn[];
    filters?: ListViewFilter[];
    booleanFilter?: string | null;
    filtersSupported?: boolean;
    displayType?: string;
    kanbanGroupField?: string | null;
  };
};

export type ActionRow = {
  id: string;
  objectApi: string;
  name: string;
  label: string;
  action: {
    type?: string;
    actionType?: string;
    targetObject?: string | null;
    offlineSafe?: boolean;
    fieldDefaults?: Record<string, unknown>;
    apexName?: string | null;
  };
};

export type CompactLayoutRow = {
  id: string;
  objectApi: string;
  name: string;
  compact: { fields?: string[] };
};

export async function upsertListView(
  db: SqlExecutor,
  lv: {
    id: string;
    objectApi: string;
    developerName: string;
    label: string;
    listview: unknown;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_listviews (id, object_api, developer_name, label, listview_json, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [lv.id, lv.objectApi, lv.developerName, lv.label, JSON.stringify(lv.listview), nowIso()]
  );
}

export async function listListViewsForObject(
  db: SqlExecutor,
  objectApi: string
): Promise<ListViewRow[]> {
  const { rows } = await db.execute(`SELECT * FROM meta_listviews WHERE object_api=?`, [
    objectApi
  ]);
  return rows
    .map((r) => ({
      id: String(r.id),
      objectApi: String(r.object_api),
      developerName: String(r.developer_name),
      label: String(r.label),
      listview: JSON.parse(String(r.listview_json)) as ListViewRow['listview']
    }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

export async function upsertAction(
  db: SqlExecutor,
  action: {
    id: string;
    objectApi: string;
    name: string;
    label: string;
    action: unknown;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_actions (id, object_api, name, label, action_json, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      action.id,
      action.objectApi,
      action.name,
      action.label,
      JSON.stringify(action.action),
      nowIso()
    ]
  );
}

export async function listActionsForObject(
  db: SqlExecutor,
  objectApi: string
): Promise<ActionRow[]> {
  const { rows } = await db.execute(`SELECT * FROM meta_actions WHERE object_api=?`, [objectApi]);
  return rows
    .map((r) => ({
      id: String(r.id),
      objectApi: String(r.object_api),
      name: String(r.name),
      label: String(r.label),
      action: JSON.parse(String(r.action_json)) as ActionRow['action']
    }))
    .sort((a, b) => a.label.localeCompare(b.label));
}

export async function upsertCompactLayout(
  db: SqlExecutor,
  compact: {
    id: string;
    objectApi: string;
    name: string;
    compact: unknown;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO meta_compact_layouts (id, object_api, name, compact_json, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
    [
      compact.id,
      compact.objectApi,
      compact.name,
      JSON.stringify(compact.compact),
      nowIso()
    ]
  );
}

export async function getCompactLayoutForObject(
  db: SqlExecutor,
  objectApi: string
): Promise<CompactLayoutRow | null> {
  const { rows } = await db.execute(
    `SELECT * FROM meta_compact_layouts WHERE object_api=? LIMIT 1`,
    [objectApi]
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: String(r.id),
    objectApi: String(r.object_api),
    name: String(r.name),
    compact: JSON.parse(String(r.compact_json)) as CompactLayoutRow['compact']
  };
}

export type UserObjectPrefs = {
  objectApi: string;
  favourites: string[];
  pinnedListViewId: string | null;
  calendarField: string | null;
};

export async function upsertUserPrefs(
  db: SqlExecutor,
  prefs: UserObjectPrefs
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO user_prefs
      (object_api, favourites_json, pinned_list_view_id, calendar_field, updated_at)
     VALUES (?, ?, ?, ?, ?)`,
    [
      prefs.objectApi,
      JSON.stringify(prefs.favourites ?? []),
      prefs.pinnedListViewId ?? null,
      prefs.calendarField ?? null,
      nowIso()
    ]
  );
}

export async function getUserPrefs(
  db: SqlExecutor,
  objectApi: string
): Promise<UserObjectPrefs | null> {
  const { rows } = await db.execute(`SELECT * FROM user_prefs WHERE object_api=?`, [objectApi]);
  if (!rows[0]) return null;
  let favourites: string[] = [];
  try {
    favourites = JSON.parse(String(rows[0].favourites_json ?? '[]')) as string[];
  } catch {
    favourites = [];
  }
  return {
    objectApi: String(rows[0].object_api),
    favourites,
    pinnedListViewId: rows[0].pinned_list_view_id
      ? String(rows[0].pinned_list_view_id)
      : null,
    calendarField: rows[0].calendar_field ? String(rows[0].calendar_field) : null
  };
}

export async function listUserPrefs(db: SqlExecutor): Promise<UserObjectPrefs[]> {
  const { rows } = await db.execute(`SELECT * FROM user_prefs`);
  return rows.map((r) => {
    let favourites: string[] = [];
    try {
      favourites = JSON.parse(String(r.favourites_json ?? '[]')) as string[];
    } catch {
      favourites = [];
    }
    return {
      objectApi: String(r.object_api),
      favourites,
      pinnedListViewId: r.pinned_list_view_id ? String(r.pinned_list_view_id) : null,
      calendarField: r.calendar_field ? String(r.calendar_field) : null
    };
  });
}

/** Resolve a field's label from synced object describe. */
export function fieldLabelFromDescribe(
  describe: Record<string, unknown> | null | undefined,
  apiName: string
): string {
  if (!describe || !apiName) return apiName;
  const fields =
    (describe.fields as { name?: string; label?: string }[] | undefined) ?? [];
  const f = fields.find((x) => x.name === apiName);
  return f?.label || apiName;
}

export type DescribeFieldInfo = {
  name: string;
  label: string;
  type: string;
  referenceTo: string[];
  required?: boolean;
  picklistValues?: (string | { value?: string; label?: string })[];
};

/** Flat field list from synced describe_json. */
export function fieldsFromDescribe(
  describe: Record<string, unknown> | null | undefined
): DescribeFieldInfo[] {
  if (!describe) return [];
  const fields =
    (describe.fields as {
      name?: string;
      label?: string;
      type?: string;
      referenceTo?: string[];
      required?: boolean;
      nillable?: boolean;
      picklistValues?: (string | { value?: string; label?: string })[];
    }[] | undefined) ?? [];
  return fields
    .filter((f) => f.name)
    .map((f) => ({
      name: String(f.name),
      label: String(f.label ?? f.name),
      type: String(f.type ?? ''),
      referenceTo: Array.isArray(f.referenceTo) ? f.referenceTo.map(String) : [],
      required: Boolean(f.required) || f.nillable === false,
      picklistValues: Array.isArray(f.picklistValues) ? f.picklistValues : undefined
    }));
}

/** Date / DateTime fields suitable for calendar view. */
export function dateFieldsFromDescribe(
  describe: Record<string, unknown> | null | undefined
): DescribeFieldInfo[] {
  return fieldsFromDescribe(describe).filter(
    (f) => f.type === 'date' || f.type === 'datetime'
  );
}

const NAME_LIKE_FIELDS = [
  'Name',
  'Subject',
  'CaseNumber',
  'Title',
  'FirstName',
  'LastName',
  'Company'
];

/**
 * Resolve lookup Id → display name from local records when possible.
 * Prefer relationship payload `Account.Name` / `Foo__r.Name` if present on the row.
 */
export async function resolveLookupDisplay(
  db: SqlExecutor,
  field: DescribeFieldInfo,
  record: Record<string, unknown>
): Promise<{ id: string; name: string; objectApi: string | null }> {
  const id = String(record[field.name] ?? '');
  if (!id) return { id: '', name: '', objectApi: null };

  // Relationship object already on payload (REST / compound)
  const relKey =
    field.name.endsWith('Id') && field.name !== 'Id'
      ? field.name.slice(0, -2)
      : field.name.endsWith('__c')
        ? field.name.replace(/__c$/, '__r')
        : null;
  if (relKey) {
    const rel = record[relKey];
    if (rel && typeof rel === 'object') {
      const relObj = rel as Record<string, unknown>;
      for (const n of NAME_LIKE_FIELDS) {
        if (relObj[n] != null && String(relObj[n]) !== '') {
          return {
            id,
            name: String(relObj[n]),
            objectApi: field.referenceTo[0] ?? null
          };
        }
      }
    }
  }

  const target = field.referenceTo[0] ?? null;
  if (target) {
    const related = await getRecord(db, target, id);
    if (related) {
      for (const n of NAME_LIKE_FIELDS) {
        if (related[n] != null && String(related[n]) !== '') {
          return { id, name: String(related[n]), objectApi: target };
        }
      }
      return { id, name: String(related.Id ?? id), objectApi: target };
    }
  }
  return { id, name: id, objectApi: target };
}

const SEARCH_TITLE_FIELDS = [
  'Name',
  'Subject',
  'CaseNumber',
  'Title',
  'FirstName',
  'LastName',
  'Company'
];

/** Global offline search across synced records (Name/Subject/CaseNumber/…). */
export async function searchRecords(
  db: SqlExecutor,
  query: string,
  limit = 40
): Promise<{ objectApi: string; record: Record<string, unknown> }[]> {
  const q = query.trim().toLowerCase();
  if (!q || q.length < 2) return [];
  const { rows } = await db.execute(
    `SELECT object_api, payload_json FROM records WHERE deleted=0 LIMIT ?`,
    [8000]
  );
  const hits: { objectApi: string; record: Record<string, unknown>; score: number }[] = [];
  for (const row of rows) {
    const objectApi = String(row.object_api);
    let record: Record<string, unknown>;
    try {
      record = JSON.parse(String(row.payload_json));
    } catch {
      continue;
    }
    const id = String(record.Id ?? '').toLowerCase();
    let score = 0;
    if (id.includes(q)) score = 5;
    for (const f of SEARCH_TITLE_FIELDS) {
      const v = String(record[f] ?? '').toLowerCase();
      if (!v) continue;
      if (v === q) score = Math.max(score, 100);
      else if (v.startsWith(q)) score = Math.max(score, 80);
      else if (v.includes(q)) score = Math.max(score, 50);
    }
    if (score > 0) hits.push({ objectApi, record, score });
  }
  hits.sort((a, b) => b.score - a.score);
  return hits.slice(0, limit).map(({ objectApi, record }) => ({ objectApi, record }));
}

export async function relatedRecords(
  db: SqlExecutor,
  childObject: string,
  lookupField: string,
  parentId: string,
  limit = 100
): Promise<Record<string, unknown>[]> {
  const all = await listRecords(db, childObject, 2000);
  return all.filter((r) => String(r[lookupField] ?? '') === parentId).slice(0, limit);
}

export async function upsertFile(
  db: SqlExecutor,
  file: {
    contentVersionId: string;
    contentDocumentId?: string;
    title?: string;
    path: string;
    hash?: string;
    size?: number;
    mimeType?: string;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO files
      (content_version_id, content_document_id, title, path, hash, size, mime_type, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      file.contentVersionId,
      file.contentDocumentId ?? null,
      file.title ?? null,
      file.path,
      file.hash ?? null,
      file.size ?? null,
      file.mimeType ?? null,
      nowIso()
    ]
  );
}

export async function getFile(
  db: SqlExecutor,
  contentVersionId: string
): Promise<Record<string, unknown> | null> {
  const { rows } = await db.execute(
    `SELECT * FROM files WHERE content_version_id=?`,
    [contentVersionId]
  );
  return rows[0] ?? null;
}

export type OutboxOp =
  | 'create'
  | 'update'
  | 'delete'
  | 'apex-action'
  | 'visit.upsert'
  | 'clm.session'
  | 'planner.reschedule'
  | 'location.upsert';

export async function enqueueOutbox(
  db: SqlExecutor,
  entry: {
    id?: string;
    op: OutboxOp | string;
    objectApi?: string;
    recordId?: string;
    payload: unknown;
  }
): Promise<string> {
  const id = entry.id ?? newId('obx');
  const ts = nowIso();
  await db.run(
    `INSERT OR REPLACE INTO outbox
      (id, op, object_api, record_id, payload_json, status, attempts, last_error, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      entry.op,
      entry.objectApi ?? null,
      entry.recordId ?? null,
      JSON.stringify(entry.payload),
      'pending',
      0,
      null,
      ts,
      ts
    ]
  );
  return id;
}

export async function listPendingOutbox(
  db: SqlExecutor,
  limit = 50
): Promise<
  {
    id: string;
    op: string;
    objectApi?: string;
    recordId?: string;
    payload: unknown;
    attempts: number;
  }[]
> {
  return listOutboxForPush(db, limit, ['pending']);
}

/** Pending + retryable failed rows for the next push batch. */
export async function listOutboxForPush(
  db: SqlExecutor,
  limit = 50,
  statuses: ('pending' | 'failed')[] = ['pending', 'failed']
): Promise<
  {
    id: string;
    op: string;
    objectApi?: string;
    recordId?: string;
    payload: unknown;
    attempts: number;
  }[]
> {
  const placeholders = statuses.map(() => '?').join(',');
  const { rows } = await db.execute(
    `SELECT * FROM outbox WHERE status IN (${placeholders})
       AND (status='pending' OR attempts < 5)
     ORDER BY
       CASE op
         WHEN 'planner.reschedule' THEN 0
         WHEN 'visit.upsert' THEN 1
         ELSE 2
       END,
       created_at ASC
     LIMIT ?`,
    [...statuses, limit]
  );
  return rows.map((r) => ({
    id: String(r.id),
    op: String(r.op),
    objectApi: (r.object_api as string) ?? undefined,
    recordId: (r.record_id as string) ?? undefined,
    payload: JSON.parse(String(r.payload_json)),
    attempts: Number(r.attempts ?? 0)
  }));
}

export async function markOutbox(
  db: SqlExecutor,
  id: string,
  status: 'pending' | 'synced' | 'failed' | 'conflict',
  error?: string | null
): Promise<void> {
  const { rows } = await db.execute(`SELECT * FROM outbox WHERE id=?`, [id]);
  const attempts = Number(rows[0]?.attempts ?? 0) + (status === 'pending' || status === 'failed' ? 1 : 0);
  await db.run(
    `UPDATE outbox SET status=?, attempts=?, last_error=?, updated_at=? WHERE id=?`,
    [status, attempts, error ?? null, nowIso(), id]
  );
}

export async function getSyncCursor(
  db: SqlExecutor,
  channel: string
): Promise<{ cursor: string | null; lastOkAt: string | null; meta: unknown }> {
  const { rows } = await db.execute(`SELECT * FROM sync_state WHERE channel=?`, [channel]);
  if (!rows[0]) return { cursor: null, lastOkAt: null, meta: null };
  return {
    cursor: (rows[0].cursor as string) ?? null,
    lastOkAt: (rows[0].last_ok_at as string) ?? null,
    meta: rows[0].meta_json ? JSON.parse(String(rows[0].meta_json)) : null
  };
}

export async function setSyncCursor(
  db: SqlExecutor,
  channel: string,
  cursor: string | null,
  meta?: unknown
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO sync_state (channel, cursor, last_ok_at, meta_json) VALUES (?, ?, ?, ?)`,
    [channel, cursor, nowIso(), meta != null ? JSON.stringify(meta) : null]
  );
}

export async function addConflict(
  db: SqlExecutor,
  conflict: {
    id?: string;
    outboxId?: string;
    objectApi?: string;
    recordId?: string;
    server: unknown;
    client: unknown;
  }
): Promise<string> {
  const id = conflict.id ?? newId('cnf');
  await db.run(
    `INSERT OR REPLACE INTO conflicts
      (id, outbox_id, object_api, record_id, server_json, client_json, resolution, created_at)
     VALUES (?, ?, ?, ?, ?, ?, NULL, ?)`,
    [
      id,
      conflict.outboxId ?? null,
      conflict.objectApi ?? null,
      conflict.recordId ?? null,
      JSON.stringify(conflict.server),
      JSON.stringify(conflict.client),
      nowIso()
    ]
  );
  return id;
}

export async function listOpenConflicts(db: SqlExecutor): Promise<
  {
    id: string;
    outboxId?: string;
    objectApi?: string;
    recordId?: string;
    server: unknown;
    client: unknown;
  }[]
> {
  const { rows } = await db.execute(
    `SELECT * FROM conflicts WHERE resolution IS NULL ORDER BY created_at ASC`
  );
  return rows.map((r) => ({
    id: String(r.id),
    outboxId: (r.outbox_id as string) ?? undefined,
    objectApi: (r.object_api as string) ?? undefined,
    recordId: (r.record_id as string) ?? undefined,
    server: JSON.parse(String(r.server_json)),
    client: JSON.parse(String(r.client_json))
  }));
}

export async function resolveConflict(
  db: SqlExecutor,
  id: string,
  resolution: 'server-wins' | 'client-wins' | 'merged'
): Promise<void> {
  await db.run(`UPDATE conflicts SET resolution=? WHERE id=?`, [resolution, id]);
}

export async function replaceSharingIdSet(
  db: SqlExecutor,
  profileName: string,
  objectApi: string,
  ids: string[]
): Promise<void> {
  await db.run(`DELETE FROM sharing_id_sets WHERE profile_name=? AND object_api=?`, [
    profileName,
    objectApi
  ]);
  for (const id of ids) {
    await db.run(
      `INSERT OR REPLACE INTO sharing_id_sets (object_api, record_id, profile_name) VALUES (?, ?, ?)`,
      [objectApi, id, profileName]
    );
  }
}

export async function upsertLwcBundle(
  db: SqlExecutor,
  bundle: {
    bundleName: string;
    version: string;
    moduleUrl?: string;
    sourceJs?: string;
    sourceHtml?: string;
    sourceCss?: string;
    sourceJsRaw?: string;
    sourceMetaXml?: string;
    sourceKind?: string;
    hasOrgSource?: boolean;
    apexBindings?: string[];
    meta?: Record<string, unknown>;
  }
): Promise<void> {
  const metaJson =
    bundle.meta || bundle.apexBindings
      ? JSON.stringify({
          ...(bundle.meta ?? {}),
          apexBindings: bundle.apexBindings ?? []
        })
      : null;
  await db.run(
    `INSERT OR REPLACE INTO meta_lwc_registry (
      bundle_name, version, module_url, source_js, source_html, source_css,
      source_js_raw, source_meta_xml, source_kind, has_org_source, meta_json, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [
      bundle.bundleName,
      bundle.version,
      bundle.moduleUrl ?? null,
      bundle.sourceJs ?? null,
      bundle.sourceHtml ?? null,
      bundle.sourceCss ?? null,
      bundle.sourceJsRaw ?? null,
      bundle.sourceMetaXml ?? null,
      bundle.sourceKind ?? null,
      bundle.hasOrgSource ? 1 : 0,
      metaJson,
      nowIso()
    ]
  );
}

export type LwcBundleRow = {
  bundleName: string;
  version: string;
  moduleUrl?: string;
  sourceJs?: string;
  sourceHtml?: string;
  sourceCss?: string;
  sourceJsRaw?: string;
  sourceMetaXml?: string;
  sourceKind?: string;
  hasOrgSource?: boolean;
  apexBindings?: string[];
  meta?: Record<string, unknown>;
};

export async function getLwcBundle(
  db: SqlExecutor,
  bundleName: string
): Promise<LwcBundleRow | null> {
  const { rows } = await db.execute(
    `SELECT * FROM meta_lwc_registry WHERE bundle_name=?`,
    [bundleName]
  );
  if (!rows[0]) return null;
  let meta: Record<string, unknown> | undefined;
  let apexBindings: string[] | undefined;
  try {
    if (rows[0].meta_json) {
      meta = JSON.parse(String(rows[0].meta_json)) as Record<string, unknown>;
      if (Array.isArray(meta.apexBindings)) {
        apexBindings = meta.apexBindings as string[];
      }
    }
  } catch {
    /* ignore */
  }
  return {
    bundleName: String(rows[0].bundle_name),
    version: String(rows[0].version),
    moduleUrl: (rows[0].module_url as string) ?? undefined,
    sourceJs: (rows[0].source_js as string) ?? undefined,
    sourceHtml: (rows[0].source_html as string) ?? undefined,
    sourceCss: (rows[0].source_css as string) ?? undefined,
    sourceJsRaw: (rows[0].source_js_raw as string) ?? undefined,
    sourceMetaXml: (rows[0].source_meta_xml as string) ?? undefined,
    sourceKind: (rows[0].source_kind as string) ?? undefined,
    hasOrgSource: Number(rows[0].has_org_source ?? 0) === 1,
    apexBindings,
    meta
  };
}

export async function kvSet(db: SqlExecutor, key: string, value: string): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO kv_secure (key, value, updated_at) VALUES (?, ?, ?)`,
    [key, value, nowIso()]
  );
}

export async function kvGet(db: SqlExecutor, key: string): Promise<string | null> {
  const { rows } = await db.execute(`SELECT * FROM kv_secure WHERE key=?`, [key]);
  return rows[0] ? String(rows[0].value) : null;
}

export interface ApexPayloadCacheRow {
  cacheKey: string;
  payload: unknown;
  fetchedAt: string;
  etag?: string | null;
}

export async function upsertApexPayload(
  db: SqlExecutor,
  cacheKey: string,
  payload: unknown,
  etag?: string | null
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO apex_payload_cache (cache_key, payload_json, fetched_at, etag) VALUES (?, ?, ?, ?)`,
    [cacheKey, JSON.stringify(payload ?? null), nowIso(), etag ?? null]
  );
}

export async function upsertStaticResource(
  db: SqlExecutor,
  row: {
    name: string;
    contentType?: string | null;
    bodyBase64?: string | null;
    size?: number | null;
    cacheControl?: string | null;
  }
): Promise<void> {
  await db.run(
    `INSERT OR REPLACE INTO static_resources
      (name, content_type, body_b64, size, cache_control, updated_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [
      row.name,
      row.contentType ?? null,
      row.bodyBase64 ?? null,
      row.size ?? null,
      row.cacheControl ?? null,
      nowIso()
    ]
  );
}

export async function getStaticResource(
  db: SqlExecutor,
  name: string
): Promise<{
  name: string;
  contentType?: string;
  bodyBase64?: string;
  size?: number;
  cacheControl?: string;
} | null> {
  const { rows } = await db.execute(`SELECT * FROM static_resources WHERE name=?`, [name]);
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    name: String(r.name),
    contentType: r.content_type != null ? String(r.content_type) : undefined,
    bodyBase64: r.body_b64 != null ? String(r.body_b64) : undefined,
    size: r.size != null ? Number(r.size) : undefined,
    cacheControl: r.cache_control != null ? String(r.cache_control) : undefined
  };
}

export type LocationTrailPoint = {
  id: string;
  latitude: number;
  longitude: number;
  accuracyMeters?: number | null;
  recordedAt: string;
  deviceModel?: string | null;
  deviceOs?: string | null;
  appVersion?: string | null;
  deviceId?: string | null;
  source?: string;
  synced?: boolean;
};

export async function insertLocationTrail(
  db: SqlExecutor,
  point: Omit<LocationTrailPoint, 'id' | 'synced'> & { id?: string }
): Promise<string> {
  const id = point.id ?? newId('loc');
  const ts = nowIso();
  await db.run(
    `INSERT OR REPLACE INTO location_trail
      (id, latitude, longitude, accuracy_meters, recorded_at, device_model, device_os,
       app_version, device_id, source, synced, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)`,
    [
      id,
      point.latitude,
      point.longitude,
      point.accuracyMeters ?? null,
      point.recordedAt,
      point.deviceModel ?? null,
      point.deviceOs ?? null,
      point.appVersion ?? null,
      point.deviceId ?? null,
      point.source ?? 'Mobile',
      ts
    ]
  );
  return id;
}

export async function getLatestLocationTrail(
  db: SqlExecutor
): Promise<LocationTrailPoint | null> {
  const { rows } = await db.execute(
    `SELECT * FROM location_trail ORDER BY recorded_at DESC LIMIT 1`
  );
  if (!rows[0]) return null;
  const r = rows[0];
  return {
    id: String(r.id),
    latitude: Number(r.latitude),
    longitude: Number(r.longitude),
    accuracyMeters: r.accuracy_meters != null ? Number(r.accuracy_meters) : null,
    recordedAt: String(r.recorded_at),
    deviceModel: r.device_model != null ? String(r.device_model) : null,
    deviceOs: r.device_os != null ? String(r.device_os) : null,
    appVersion: r.app_version != null ? String(r.app_version) : null,
    deviceId: r.device_id != null ? String(r.device_id) : null,
    source: r.source != null ? String(r.source) : 'Mobile',
    synced: Number(r.synced) === 1
  };
}

export async function listUnsyncedLocationTrail(
  db: SqlExecutor,
  limit = 50
): Promise<LocationTrailPoint[]> {
  const { rows } = await db.execute(
    `SELECT * FROM location_trail WHERE synced=0 ORDER BY recorded_at ASC LIMIT ?`,
    [limit]
  );
  return rows.map((r) => ({
    id: String(r.id),
    latitude: Number(r.latitude),
    longitude: Number(r.longitude),
    accuracyMeters: r.accuracy_meters != null ? Number(r.accuracy_meters) : null,
    recordedAt: String(r.recorded_at),
    deviceModel: r.device_model != null ? String(r.device_model) : null,
    deviceOs: r.device_os != null ? String(r.device_os) : null,
    appVersion: r.app_version != null ? String(r.app_version) : null,
    deviceId: r.device_id != null ? String(r.device_id) : null,
    source: r.source != null ? String(r.source) : 'Mobile',
    synced: false
  }));
}

export async function markLocationTrailSynced(db: SqlExecutor, id: string): Promise<void> {
  await db.run(`UPDATE location_trail SET synced=1 WHERE id=?`, [id]);
}

export async function getApexPayload<T = unknown>(
  db: SqlExecutor,
  cacheKey: string
): Promise<ApexPayloadCacheRow & { payload: T } | null> {
  const { rows } = await db.execute(
    `SELECT cache_key, payload_json, fetched_at, etag FROM apex_payload_cache WHERE cache_key=?`,
    [cacheKey]
  );
  if (!rows[0]) return null;
  let payload: T;
  try {
    payload = JSON.parse(String(rows[0].payload_json)) as T;
  } catch {
    return null;
  }
  return {
    cacheKey: String(rows[0].cache_key),
    payload,
    fetchedAt: String(rows[0].fetched_at),
    etag: rows[0].etag != null ? String(rows[0].etag) : null
  };
}

export async function listApexPayloadKeys(db: SqlExecutor): Promise<string[]> {
  const { rows } = await db.execute(`SELECT cache_key FROM apex_payload_cache`);
  return rows.map((r) => String(r.cache_key));
}

/** Diagnostic / support log entry persisted locally for CloudAstick support exports. */
export type LogEntry = {
  id: string;
  category: string;
  source?: string | null;
  message: string;
  detail?: unknown;
  tags?: string[];
  createdAt: string;
};

const LOG_RING_MAX = 500;

export async function appendLog(
  db: SqlExecutor,
  entry: {
    category: string;
    source?: string | null;
    message: string;
    detail?: unknown;
    tags?: string[];
    id?: string;
  }
): Promise<string> {
  const id = entry.id ?? newId('log');
  const ts = nowIso();
  await db.run(
    `INSERT OR REPLACE INTO logs
      (id, category, source, message, detail_json, tags_json, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [
      id,
      entry.category,
      entry.source ?? null,
      entry.message.slice(0, 4000),
      entry.detail != null ? JSON.stringify(entry.detail) : null,
      entry.tags?.length ? JSON.stringify(entry.tags) : null,
      ts
    ]
  );
  try {
    await pruneLogs(db, LOG_RING_MAX);
  } catch {
    /* ignore prune failures */
  }
  return id;
}

function mapLogRow(r: Record<string, unknown>): LogEntry {
  let detail: unknown;
  if (r.detail_json != null && String(r.detail_json) !== '') {
    try {
      detail = JSON.parse(String(r.detail_json));
    } catch {
      detail = String(r.detail_json);
    }
  }
  let tags: string[] | undefined;
  if (r.tags_json != null && String(r.tags_json) !== '') {
    try {
      tags = JSON.parse(String(r.tags_json)) as string[];
    } catch {
      tags = undefined;
    }
  }
  return {
    id: String(r.id),
    category: String(r.category),
    source: r.source != null ? String(r.source) : null,
    message: String(r.message),
    detail,
    tags,
    createdAt: String(r.created_at)
  };
}

export async function listLogs(
  db: SqlExecutor,
  opts: { category?: string; limit?: number } = {}
): Promise<LogEntry[]> {
  const limit = opts.limit ?? 200;
  if (opts.category) {
    const { rows } = await db.execute(
      `SELECT * FROM logs WHERE category=? ORDER BY created_at DESC LIMIT ?`,
      [opts.category, limit]
    );
    return rows.map(mapLogRow);
  }
  const { rows } = await db.execute(
    `SELECT * FROM logs ORDER BY created_at DESC LIMIT ?`,
    [limit]
  );
  return rows.map(mapLogRow);
}

export async function countLogs(db: SqlExecutor, category?: string): Promise<number> {
  if (category) {
    const { rows } = await db.execute(`SELECT * FROM logs WHERE category=?`, [category]);
    return rows.length;
  }
  const { rows } = await db.execute(`SELECT * FROM logs`);
  return rows.length;
}

export async function clearLogs(db: SqlExecutor, category?: string): Promise<void> {
  if (category) {
    await db.run(`DELETE FROM logs WHERE category=?`, [category]);
    return;
  }
  await db.run(`DELETE FROM logs`);
}

/** Keep the newest `keep` log rows; drop older ones. */
export async function pruneLogs(db: SqlExecutor, keep = LOG_RING_MAX): Promise<void> {
  const rows = await listLogs(db, { limit: keep + 2000 });
  if (rows.length <= keep) return;
  for (const row of rows.slice(keep)) {
    await db.run(`DELETE FROM logs WHERE id=?`, [row.id]);
  }
}

export type OutboxRow = {
  id: string;
  op: string;
  objectApi?: string;
  recordId?: string;
  payload: unknown;
  status: string;
  attempts: number;
  lastError?: string | null;
  createdAt: string;
  updatedAt: string;
};

export async function listOutboxByStatus(
  db: SqlExecutor,
  statuses: Array<'pending' | 'synced' | 'failed' | 'conflict'>,
  limit = 100
): Promise<OutboxRow[]> {
  if (!statuses.length) return [];
  const placeholders = statuses.map(() => '?').join(',');
  const { rows } = await db.execute(
    `SELECT * FROM outbox WHERE status IN (${placeholders}) ORDER BY updated_at DESC LIMIT ?`,
    [...statuses, limit]
  );
  return rows.map((r) => ({
    id: String(r.id),
    op: String(r.op),
    objectApi: r.object_api != null ? String(r.object_api) : undefined,
    recordId: r.record_id != null ? String(r.record_id) : undefined,
    payload: (() => {
      try {
        return JSON.parse(String(r.payload_json));
      } catch {
        return r.payload_json;
      }
    })(),
    status: String(r.status),
    attempts: Number(r.attempts ?? 0),
    lastError: r.last_error != null ? String(r.last_error) : null,
    createdAt: String(r.created_at),
    updatedAt: String(r.updated_at)
  }));
}

export async function listSyncState(
  db: SqlExecutor
): Promise<{ channel: string; cursor: string | null; lastOkAt: string | null; meta: unknown }[]> {
  const { rows } = await db.execute(`SELECT * FROM sync_state`);
  return rows.map((r) => ({
    channel: String(r.channel),
    cursor: r.cursor != null ? String(r.cursor) : null,
    lastOkAt: r.last_ok_at != null ? String(r.last_ok_at) : null,
    meta: r.meta_json
      ? (() => {
          try {
            return JSON.parse(String(r.meta_json));
          } catch {
            return String(r.meta_json);
          }
        })()
      : null
  }));
}

export async function openDatabase(): Promise<SqlExecutor> {
  // Prefer memory for universal bootstrap; shell can swap in Capacitor SQLite later.
  const db = new MemorySqlExecutor();
  await migrate(db);
  return db;
}

export { xorObfuscate, xorDeobfuscate, ENCRYPTION_NOTES } from './crypto.js';
