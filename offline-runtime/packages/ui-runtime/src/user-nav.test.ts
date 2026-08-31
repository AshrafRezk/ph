import test from 'node:test';
import assert from 'node:assert/strict';
import { resolveTabsFromUserNav } from './user-nav.js';

test('resolveTabsFromUserNav orders by user preference', () => {
  const tabs = [
    { developerName: 'Account', label: 'Accounts', tab: { objectApi: 'Account' } },
    { developerName: 'Field_Rep_Planner', label: 'Planner', tab: { pageDeveloperName: 'Field_Rep_Planner' } },
    { developerName: 'Accounts_Tab', label: 'Accounts Tab', tab: { lwcBundle: 'c/accountsTab' } }
  ];
  const ordered = resolveTabsFromUserNav(
    [
      { developerName: 'Field_Rep_Planner', label: 'My Planner', iconUrl: 'https://x/icon.png' },
      { developerName: 'standard-Account', objectApiName: 'Account' }
    ],
    tabs
  );
  assert.equal(ordered.length, 2);
  assert.equal(ordered[0].developerName, 'Field_Rep_Planner');
  assert.equal(ordered[0].label, 'My Planner');
  assert.equal(ordered[1].developerName, 'Account');
});
