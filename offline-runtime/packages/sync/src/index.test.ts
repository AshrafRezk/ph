import { test } from 'node:test';
import assert from 'node:assert/strict';
import { openDatabase } from '@osr/db';
import { SyncEngine, createMockSyncClient, localSaveRecord, syncChannelLabel } from './index.js';

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
