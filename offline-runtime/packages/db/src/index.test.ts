import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  openDatabase,
  upsertRecord,
  getRecord,
  enqueueOutbox,
  listPendingOutbox,
  markOutbox,
  upsertValidationRule,
  getValidationRules,
  upsertListView,
  listListViewsForObject,
  searchRecords,
  upsertUserPrefs,
  getUserPrefs,
  fieldLabelFromDescribe,
  resolveLookupDisplay,
  appendLog,
  listLogs,
  countLogs,
  clearLogs
} from './index.js';

test('record CRUD + outbox', async () => {
  const db = await openDatabase();
  await upsertRecord(db, 'Account', '001AAA', { Id: '001AAA', Name: 'Acme' });
  const rec = await getRecord(db, 'Account', '001AAA');
  assert.equal(rec?.Name, 'Acme');

  const id = await enqueueOutbox(db, {
    op: 'update',
    objectApi: 'Account',
    recordId: '001AAA',
    payload: { Name: 'Acme Updated' }
  });
  const pending = await listPendingOutbox(db);
  assert.equal(pending[0].id, id);
  await markOutbox(db, id, 'synced');
  const after = await listPendingOutbox(db);
  assert.equal(after.length, 0);
});

test('validation rules persist', async () => {
  const db = await openDatabase();
  await upsertValidationRule(db, {
    id: 'vr1',
    objectApi: 'Account',
    name: 'Need_Name',
    active: true,
    errorCondition: 'ISBLANK(Name)',
    errorMessage: 'Name required',
    rule: {}
  });
  const rules = await getValidationRules(db, 'Account');
  assert.equal(rules.length, 1);
  assert.equal(rules[0].errorCondition, 'ISBLANK(Name)');
});

test('list views + global search', async () => {
  const db = await openDatabase();
  await upsertRecord(db, 'Account', '001AAA', { Id: '001AAA', Name: 'Cairo Central Pharmacy' });
  await upsertRecord(db, 'Visit__c', 'a0V001', {
    Id: 'a0V001',
    Name: 'V-1001',
    Status__c: 'Planned'
  });
  await upsertListView(db, {
    id: '00B1',
    objectApi: 'Visit__c',
    developerName: 'All',
    label: 'All Visits',
    listview: { recordIds: ['a0V001'] }
  });
  const views = await listListViewsForObject(db, 'Visit__c');
  assert.equal(views.length, 1);
  assert.equal(views[0].label, 'All Visits');
  const hits = await searchRecords(db, 'Cairo', 10);
  assert.equal(hits.length, 1);
  assert.equal(hits[0].objectApi, 'Account');
});

test('user prefs + lookup display + field labels', async () => {
  const db = await openDatabase();
  await upsertRecord(db, 'Account', '001AAA', { Id: '001AAA', Name: 'Cairo Central' });
  await upsertRecord(db, 'Visit__c', 'a0V001', {
    Id: 'a0V001',
    Name: 'V-1001',
    Account__c: '001AAA',
    Status__c: 'Planned'
  });
  await upsertUserPrefs(db, {
    objectApi: 'Visit__c',
    favourites: ['00B1', '00B2'],
    pinnedListViewId: '00B1',
    calendarField: 'Planned_Date__c'
  });
  const prefs = await getUserPrefs(db, 'Visit__c');
  assert.equal(prefs?.pinnedListViewId, '00B1');
  assert.equal(prefs?.favourites.length, 2);
  assert.equal(prefs?.calendarField, 'Planned_Date__c');

  const describe = {
    fields: [
      { name: 'Account__c', label: 'Account', type: 'reference', referenceTo: ['Account'] },
      { name: 'Status__c', label: 'Status', type: 'picklist', referenceTo: [] }
    ]
  };
  assert.equal(fieldLabelFromDescribe(describe, 'Status__c'), 'Status');
  const lookup = await resolveLookupDisplay(
    db,
    {
      name: 'Account__c',
      label: 'Account',
      type: 'reference',
      referenceTo: ['Account']
    },
    { Account__c: '001AAA' }
  );
  assert.equal(lookup.name, 'Cairo Central');
  assert.equal(lookup.objectApi, 'Account');
});

test('support logs table stores sync issues', async () => {
  const db = await openDatabase();
  const id = await appendLog(db, {
    category: 'sync',
    source: 'apexCache',
    message: 'SF POST /services/apexrest/osr/v1/apex-cache -> 500',
    detail: { errorCode: 'APEX_ERROR' },
    tags: ['auto', 'outbox 4']
  });
  const logs = await listLogs(db, { category: 'sync' });
  assert.equal(logs.length, 1);
  assert.equal(logs[0].id, id);
  assert.equal(logs[0].source, 'apexCache');
  assert.deepEqual(logs[0].tags, ['auto', 'outbox 4']);
  assert.equal(await countLogs(db, 'sync'), 1);
  await clearLogs(db, 'sync');
  assert.equal(await countLogs(db, 'sync'), 0);
});
