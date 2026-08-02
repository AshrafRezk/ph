import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { apexMethodKey } from './apex.js';

describe('platform apex', () => {
  it('normalizes apex import paths', () => {
    assert.equal(
      apexMethodKey('@salesforce/apex/HomeOfficeMessageController.getActiveMessages'),
      'HomeOfficeMessageController.getActiveMessages'
    );
    assert.equal(
      apexMethodKey('FieldRepHomeController.getTodayPlan'),
      'FieldRepHomeController.getTodayPlan'
    );
  });
});
