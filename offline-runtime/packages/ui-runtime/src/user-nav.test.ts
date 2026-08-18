import test from 'node:test';
import assert from 'node:assert/strict';
import {
  pickUserNavItems,
  resolveTabsFromUserNav,
  synthesizeTabFromUserNavItem
} from './user-nav.js';

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

test('resolveTabsFromUserNav synthesizes home tab from user nav', () => {
  const ordered = resolveTabsFromUserNav(
    [
      {
        developerName: 'Field_Rep_Home_App',
        label: 'Home',
        itemType: 'TabFlexiPage',
        pageReference: {
          type: 'standard__navItemPage',
          attributes: { apiName: 'Field_Rep_Home_App' }
        }
      },
      { developerName: 'Field_Rep_Planner', label: 'Planner', itemType: 'TabFlexiPage' }
    ],
    []
  );
  assert.equal(ordered.length, 2);
  assert.equal(ordered[0].developerName, 'Field_Rep_Home_App');
  assert.equal(ordered[0].tab.pageDeveloperName, 'Field_Rep_Home_App');
});

test('pickUserNavItems prefers Small on phone', () => {
  const app = {
    userNavItems: [{ developerName: 'Account' }],
    userNavItemsSmall: [{ developerName: 'Visit__c' }]
  };
  assert.equal(pickUserNavItems(app, 'Small')?.[0].developerName, 'Visit__c');
  assert.equal(pickUserNavItems(app, 'Large')?.[0].developerName, 'Account');
});

test('synthesizeTabFromUserNavItem maps entity tabs to objects', () => {
  const tab = synthesizeTabFromUserNavItem({
    developerName: 'Visit__c',
    label: 'Visits',
    itemType: 'Entity',
    objectApiName: 'Visit__c'
  });
  assert.equal(tab.tab.objectApi, 'Visit__c');
  assert.equal(tab.tab.tabType, 'object');
});
