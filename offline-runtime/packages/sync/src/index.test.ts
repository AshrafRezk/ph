import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDatabase } from '@osr/db';
import { SyncEngine, createMockSyncClient, isSalesforceRecordId, localSaveRecord, parseUiNavRecords, shouldSyncUserNavForApp, syncChannelLabel, uiAppRecordId } from './index.js';

test('isSalesforceRecordId accepts 15/18-char ids only', () => {
  assert.equal(isSalesforceRecordId('06m3B000000CbQ3QAK'), true);
  assert.equal(isSalesforceRecordId('06m3B000000CbQ3'), true);
  assert.equal(isSalesforceRecordId('app_Pharma_Management'), false);
  assert.equal(isSalesforceRecordId('appPharmaManagem0'), false);
});

test('uiAppRecordId prefers appId from UI API catalog', () => {
  assert.equal(uiAppRecordId({ appId: '06mHu000004ygjXIAQ' }), '06mHu000004ygjXIAQ');
  assert.equal(uiAppRecordId({ id: '06mHu000004ygjXIAQ' }), '06mHu000004ygjXIAQ');
  assert.equal(uiAppRecordId({ appId: 'not-an-id' }), '');
});

test('parseUiNavRecords skips items without developerName', () => {
  const rows = parseUiNavRecords([
    { developerName: 'Visit__c', label: 'Visits', objectApiName: 'Visit__c' },
    { label: 'Orphan' }
  ]);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].developerName, 'Visit__c');
});

test('shouldSyncUserNavForApp skips bare portal apps', () => {
  assert.equal(
    shouldSyncUserNavForApp({
      developerName: 'LightningSales',
      app: {
        tabDeveloperNames: [
          'Field_Rep_Planner',
          'Accounts_Tab',
          'Visit__c',
          'CLM_Presentations'
        ]
      }
    }),
    true
  );
  assert.equal(
    shouldSyncUserNavForApp({
      developerName: 'Portal',
      app: { tabDeveloperNames: ['Account', 'Contact'] }
    }),
    false
  );
});

test('mock full sync primes metadata and data', async () => {
  const db = await openDatabase();
  const engine = new SyncEngine(db, createMockSyncClient());
  const hello = await engine.hello();
  assert.equal(hello.ok, true);
  const pull = await engine.pullAll();
  assert.equal(pull.channels.metadata.ok, true);
  assert.ok((pull.channels.metadata.count ?? 0) > 0);
  assert.equal(pull.channels.data.ok, true);
});

test('outbox push syncs local save', async () => {
  const db = await openDatabase();
  const engine = new SyncEngine(db, createMockSyncClient());
  await engine.pullAll();
  await localSaveRecord(db, 'Account', { Name: 'Local Co' }, true);
  const push = await engine.pushOutbox();
  assert.equal(push.synced, 1);
});

test('syncChannelLabel pluralizes common APIs', () => {
  assert.equal(syncChannelLabel('Account'), 'Accounts');
  assert.equal(syncChannelLabel('Visit__c'), 'Visits');
  assert.equal(syncChannelLabel('Opportunity'), 'Opportunities');
});

test('fullSync pushes outbox before pull', async () => {
  const db = await openDatabase();
  const calls: string[] = [];
  const base = createMockSyncClient();
  const client: typeof base = {
    get: async (path) => {
      calls.push(`GET ${path}`);
      return base.get(path);
    },
    post: async (path, body) => {
      calls.push(`POST ${path}`);
      return base.post(path, body);
    }
  };
  const engine = new SyncEngine(db, client);
  await localSaveRecord(db, 'Account', { Name: 'Queued Co' }, true);
  await engine.fullSync();
  const outboxIdx = calls.findIndex((c) => c.includes('/outbox'));
  const dataIdx = calls.findIndex((c) => c.includes('/data'));
  assert.ok(outboxIdx >= 0, 'outbox push expected');
  assert.ok(dataIdx >= 0, 'data pull expected');
  assert.ok(outboxIdx < dataIdx, 'outbox must run before data pull');
});

test('fullSync emits onProgress with channel steps', async () => {
  const db = await openDatabase();
  const engine = new SyncEngine(db, createMockSyncClient());
  const events: { channel: string; total: number }[] = [];
  await engine.fullSync({
    onProgress: (p) => events.push({ channel: p.channel, total: p.total })
  });
  assert.ok(events.length >= 3);
  assert.ok(events.some((e) => e.channel === 'Metadata' || e.channel.startsWith('Metadata')));
  assert.ok(events.some((e) => /Accounts/.test(e.channel)));
  assert.ok(events.some((e) => e.channel === 'Files'));
  assert.ok(events.some((e) => e.total > 0));
});
