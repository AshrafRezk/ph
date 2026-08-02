import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  searchableFieldsForObject,
  filterRowsByTextSearch,
  detectKanbanFieldSmart,
  suggestDefaultListMode,
  crmHubSearchPlaceholder
} from './crmhub-list.js';

describe('crmhub-list smart helpers', () => {
  it('searches describe + column fields dynamically', () => {
    const fields = searchableFieldsForObject(
      [
        { name: 'Name', label: 'Name', type: 'string', referenceTo: [] },
        { name: 'Specialty__c', label: 'Specialty', type: 'string', referenceTo: [] },
        { name: 'Amount', label: 'Amount', type: 'currency', referenceTo: [] }
      ],
      ['Status__c'],
      [{ Name: 'Acme', Specialty__c: 'Cardio', Extra_Note__c: 'hello' }]
    );
    assert.ok(fields.includes('Specialty__c'));
    assert.ok(fields.includes('Status__c'));
    assert.ok(fields.includes('Extra_Note__c'));
    const rows = filterRowsByTextSearch(
      [
        { Name: 'Acme', Specialty__c: 'Cardio' },
        { Name: 'Beta', Specialty__c: 'Oncology' }
      ],
      'cardio',
      fields
    );
    assert.equal(rows.length, 1);
    assert.equal(rows[0].Name, 'Acme');
  });

  it('picks kanban from picklist describe', () => {
    const field = detectKanbanFieldSmart(
      [{ Status__c: 'Open' }, { Status__c: 'Done' }],
      null,
      [{ name: 'Status__c', label: 'Status', type: 'picklist', referenceTo: [] }]
    );
    assert.equal(field, 'Status__c');
  });

  it('suggests calendar for visit-like objects', () => {
    assert.equal(
      suggestDefaultListMode({
        formFactor: 'Large',
        hasDate: true,
        hasKanban: true,
        objectApi: 'Visit__c',
        rowCount: 20
      }),
      'calendar'
    );
    assert.equal(
      suggestDefaultListMode({
        formFactor: 'Small',
        hasDate: true,
        hasKanban: true,
        objectApi: 'Visit__c',
        rowCount: 20
      }),
      'cards'
    );
    assert.match(crmHubSearchPlaceholder('Visits', 12), /Visits/);
  });
});
