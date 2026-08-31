import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  openDatabase,
  upsertRecord,
  upsertApp,
  upsertFlexiPage,
  upsertTab
} from '@osr/db';
import {
  putVisitPayload,
  getVisitPayload,
  enqueueClmSession,
  enqueuePlannerReschedule,
  bundleNameToTag,
  SYNC_BUDGETS,
  parseFlexiPage,
  loadNavigation,
  loadHomeView,
  lwcBundleFromComponent,
  isCustomLwcType,
  normalizeLwcBundleName,
  humanizeComponentLabel,
  extractRequiredFields,
  isSparseRecord
} from './index.js';

test('isSparseRecord detects Id-only cached rows', () => {
  assert.equal(isSparseRecord(null), true);
  assert.equal(isSparseRecord({ Id: '001xx' }), true);
  assert.equal(
    isSparseRecord({ Id: '001xx', SystemModstamp: '2026-01-01T00:00:00.000Z' }),
    true
  );
  assert.equal(isSparseRecord({ Id: '001xx', Name: 'Acme' }), false);
});

test('extractRequiredFields skips read-only system fields like IsDeleted', () => {
  const fields = extractRequiredFields(
    {
      fields: [
        {
          name: 'IsDeleted',
          label: 'Deleted',
          nillable: false,
          createable: false,
          updateable: false
        },
        {
          name: 'Status__c',
          label: 'Status',
          required: true,
          nillable: false,
          createable: true,
          updateable: true
        },
        {
          name: 'Event_Start__c',
          label: 'Event Start',
          nillable: false,
          createable: true,
          updateable: true
        }
      ]
    },
    { isNew: false }
  );
  assert.deepEqual(
    fields.filter((f) => f.required).map((f) => f.apiName),
    ['Status__c', 'Event_Start__c']
  );
});

test('visit/CLM/planner journey ports enqueue outbox', async () => {
  const db = await openDatabase();
  await upsertRecord(db, 'Visit__c', 'a0V1', {
    Id: 'a0V1',
    Account__c: '001A',
    Status__c: 'Planned'
  });
  await putVisitPayload(db, {
    visitId: 'a0V1',
    accountId: '001A',
    status: 'Completed',
    callReport: { Notes: 'Hi' },
    updatedAt: new Date().toISOString()
  });
  const payload = await getVisitPayload(db, 'a0V1');
  assert.equal(payload?.status, 'Completed');
  await enqueueClmSession(db, {
    actionType: 'START_SESSION',
    clientSessionKey: 'sess1',
    visitId: 'a0V1'
  });
  await enqueuePlannerReschedule(db, [{ visitId: 'a0V1', plannedDate: '2026-07-26' }]);
  assert.equal(bundleNameToTag('c/visitCallShellLite'), 'osr-visit-call-shell-lite');
  assert.ok(SYNC_BUDGETS.maxOutboxBatch > 0);
});

test('normalizes Tooling c: component names to c/ bundles', () => {
  assert.equal(isCustomLwcType('c:fieldRepHomeTodayPlan'), true);
  assert.equal(isCustomLwcType('c/fieldRepHomeTodayPlan'), true);
  assert.equal(isCustomLwcType('force:highlightsPanel'), false);
  assert.equal(normalizeLwcBundleName('c:fieldRepHomeMetrics'), 'c/fieldRepHomeMetrics');
  assert.equal(normalizeLwcBundleName('c/fieldRepHomeMetrics'), 'c/fieldRepHomeMetrics');
  assert.equal(
    lwcBundleFromComponent({ type: 'c:fieldRepHomeNextBestCustomer', attributes: {} }),
    'c/fieldRepHomeNextBestCustomer'
  );
  assert.equal(humanizeComponentLabel('c:fieldRepHomeTodayPlan'), "Today's Plan");
  assert.equal(humanizeComponentLabel('c:fieldRepHomeMetrics'), 'Your Performance');
  assert.equal(humanizeComponentLabel('c:homeOfficeMessages'), 'Home Office Messages');
});

test('apps home navigation and flexi parse', async () => {
  const db = await openDatabase();
  await upsertTab(db, {
    id: 't1',
    developerName: 'Account',
    label: 'Accounts',
    tab: { objectApi: 'Account' },
    sortOrder: 1
  });
  await upsertTab(db, {
    id: 't2',
    developerName: 'Visit__c',
    label: 'Visits',
    tab: { objectApi: 'Visit__c' },
    sortOrder: 2
  });
  await upsertApp(db, {
    id: 'a1',
    developerName: 'Pharma_Field',
    label: 'Pharma Field',
    app: {
      tabDeveloperNames: ['Account'],
      homeFlexiPageDeveloperName: 'Pharma_Field_Home',
      iconUrl: 'https://example.com/icon.png'
    }
  });
  await upsertFlexiPage(db, {
    id: 'fpH',
    developerName: 'Pharma_Field_Home',
    type: 'HomePage',
    page: {
      type: 'HomePage',
      regions: [
        {
          name: 'main',
          components: [
            { type: 'c/visitCallShellLite', attributes: { label: 'Visits' } },
            { type: 'c:fieldRepHomeTodayPlan', attributes: {} }
          ]
        }
      ]
    }
  });
  const nav = await loadNavigation(db, 'Pharma_Field');
  assert.equal(nav.apps.length, 1);
  assert.equal(nav.apps[0].iconUrl, 'https://example.com/icon.png');
  assert.equal(nav.tabs.length, 1);
  assert.equal(nav.tabs[0].developerName, 'Account');
  const home = await loadHomeView(db, 'Pharma_Field');
  assert.equal(home.homeDeveloperName, 'Pharma_Field_Home');
  assert.equal(home.lwcBundles[0], 'c/visitCallShellLite');
  assert.equal(home.lwcBundles[1], 'c/fieldRepHomeTodayPlan');
  const parsed = parseFlexiPage(home.flexiPage as unknown as Record<string, unknown>);
  assert.ok(parsed);
  assert.equal(lwcBundleFromComponent(parsed!.regions[0].components[0]), 'c/visitCallShellLite');
  assert.equal(lwcBundleFromComponent(parsed!.regions[0].components[1]), 'c/fieldRepHomeTodayPlan');
});
