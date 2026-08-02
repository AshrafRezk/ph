import { test } from 'node:test';
import assert from 'node:assert/strict';
import { FormulaEvaluator, evaluateValidationRules, validateRecord } from './index.js';

test('ISBLANK and AND', () => {
  const ev = new FormulaEvaluator();
  const { value } = ev.evaluate("AND(ISBLANK(Name), ISPICKVAL(Status, 'Open'))", {
    Name: '',
    Status: 'Open'
  });
  assert.equal(value, true);
});

test('validation rule fires when condition true', () => {
  const result = evaluateValidationRules(
    [
      {
        id: '1',
        name: 'Need_Name',
        errorCondition: 'ISBLANK(Name)',
        errorMessage: 'Name required'
      }
    ],
    { Name: '' }
  );
  assert.equal(result.ok, false);
  assert.equal(result.errors[0].message, 'Name required');
});

test('validateRecord combines required + VR', () => {
  const result = validateRecord(
    { Name: 'Acme', Industry: '' },
    [],
    [{ apiName: 'Industry', label: 'Industry', required: true }]
  );
  assert.equal(result.ok, false);
});
