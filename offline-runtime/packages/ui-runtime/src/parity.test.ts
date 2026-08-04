import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  applyListFilters,
  formFactorFromWidth,
  selectRegionsForFormFactor,
  isComponentVisible,
  parseFlexiPage,
  classifyActionKind,
  sortFieldHomeComponents,
  planFieldHomeRegions,
  isFieldHomeLayout,
  getFidelityEntry,
  listFidelityEntries,
  isFidelityBundle
} from './index.js';

describe('form factor', () => {
  it('maps viewport widths', () => {
    assert.equal(formFactorFromWidth(375), 'Small');
    assert.equal(formFactorFromWidth(800), 'Medium');
    assert.equal(formFactorFromWidth(1200), 'Large');
  });

  it('selects template regions', () => {
    const regions = [
      { name: 'header' },
      { name: 'main' },
      { name: 'sidebar' }
    ];
    const selected = selectRegionsForFormFactor(regions, 'Small', [
      { formFactor: 'Small', regions: ['header', 'main'] },
      { formFactor: 'Large', regions: ['header', 'main', 'sidebar'] }
    ]);
    assert.deepEqual(
      selected.map((r) => r.name),
      ['header', 'main']
    );
  });
});

describe('field home layout', () => {
  it('detects home layouts', () => {
    assert.equal(isFieldHomeLayout('HomePage', [{ name: 'main' }]), true);
    assert.equal(isFieldHomeLayout('AppPage', [{ name: 'bottomLeft' }]), true);
    assert.equal(isFieldHomeLayout('AppPage', [{ name: 'main' }]), false);
    assert.equal(
      isFieldHomeLayout('AppPage', [
        {
          name: 'main',
          components: [{ type: 'c:fieldRepHomeTodayPlan' }]
        }
      ]),
      true
    );
  });

  it('sorts AppPage stacks in product home order and hides location publisher', () => {
    const sorted = sortFieldHomeComponents([
      { type: 'c:repLocationPublisher' },
      { type: 'c:fieldRepHomeMetrics' },
      { type: 'c:fieldRepHomeTodayPlan' },
      { type: 'c:homeOfficeMessages' },
      { type: 'c:fieldRepHomeClmPrefetch' },
      { type: 'c:fieldRepHomeNextBestCustomer' },
      { type: 'c:reportsHub' }
    ]);
    assert.deepEqual(
      sorted.map((c) => c.type),
      [
        'c:fieldRepHomeClmPrefetch',
        'c:fieldRepHomeMetrics',
        'c:homeOfficeMessages',
        'c:fieldRepHomeTodayPlan',
        'c:fieldRepHomeNextBestCustomer',
        'c:reportsHub'
      ]
    );
  });

  it('flattens home into one column with product order', () => {
    const plan = planFieldHomeRegions(
      [
        {
          name: 'top',
          components: [
            { type: 'c:repLocationPublisher' },
            { type: 'c:fieldRepHomeClmPrefetch' },
            { type: 'c:fieldRepHomeMetrics' }
          ]
        },
        {
          name: 'bottomLeft',
          components: [{ type: 'c:fieldRepHomeTodayPlan' }]
        },
        {
          name: 'sidebar',
          components: [
            { type: 'c:homeOfficeMessages' },
            { type: 'c:fieldRepHomeNextBestCustomer' },
            { type: 'c:reportsHub' }
          ]
        }
      ],
      'Small'
    );
    assert.equal(plan.side, null);
    assert.equal(plan.main.length, 1);
    assert.deepEqual(
      plan.main[0].components.map((c) => c.type),
      [
        'c:fieldRepHomeClmPrefetch',
        'c:fieldRepHomeMetrics',
        'c:homeOfficeMessages',
        'c:fieldRepHomeTodayPlan',
        'c:fieldRepHomeNextBestCustomer',
        'c:reportsHub'
      ]
    );
  });

  it('never keeps a sidebar column on Large', () => {
    const plan = planFieldHomeRegions(
      [
        {
          name: 'bottomLeft',
          components: [{ type: 'c:fieldRepHomeTodayPlan' }]
        },
        {
          name: 'sidebar',
          components: [{ type: 'c:homeOfficeMessages' }]
        },
        {
          name: 'top',
          components: [{ type: 'c:repLocationPublisher' }]
        }
      ],
      'Large'
    );
    assert.equal(plan.side, null);
    assert.equal(plan.main.length, 1);
    assert.ok(!plan.main[0].components.some((c) => c.type === 'c:repLocationPublisher'));
  });
});

describe('list filters', () => {
  it('filters equals + booleanFilter', () => {
    const rows = [
      { Id: '1', Status__c: 'Planned' },
      { Id: '2', Status__c: 'Completed' }
    ];
    const result = applyListFilters(
      rows,
      [{ field: 'Status__c', operation: 'equals', value: 'Planned' }],
      '1'
    );
    assert.equal(result.supported, true);
    assert.equal(result.rows.length, 1);
    assert.equal(result.rows[0].Id, '1');
  });

  it('marks unsupported ops', () => {
    const result = applyListFilters(
      [{ Id: '1' }],
      [{ field: 'Name', operation: 'includes', value: 'x' }]
    );
    assert.equal(result.supported, false);
  });
});

describe('visibility + flexi parse', () => {
  it('parses fieldInstances and visibility', () => {
    const page = parseFlexiPage({
      type: 'RecordPage',
      regions: [
        {
          name: 'main',
          components: [
            {
              type: 'flexipage:fieldSection',
              fieldInstances: [{ fieldApiName: 'Name', uiBehavior: 'Required' }],
              visibilityRule: { criteria: 'false' }
            }
          ]
        }
      ]
    });
    assert.ok(page);
    assert.equal(page!.regions[0].components[0].fieldInstances?.[0].fieldApiName, 'Name');
    assert.equal(isComponentVisible({ criteria: 'false' }, {}), false);
  });
});

describe('actions', () => {
  it('classifies standard kinds', () => {
    assert.equal(classifyActionKind({ actionType: 'Edit' }), 'edit');
    assert.equal(classifyActionKind({ actionType: 'Delete' }), 'delete');
  });
});

describe('pharma field vite catalog', () => {
  it('maps Field journey bundles to vite mode', () => {
    const required = [
      'c/fieldRepHomeTodayPlan',
      'c/fieldRepPlanner',
      'c/visitCallShell',
      'c/accountsTab',
      'c/clmPresentationsHub',
      'c/timeOffSubmission',
      'c/accountVisitInsightsPanel',
      'c/coachingEventEvaluation'
    ];
    for (const b of required) {
      assert.equal(isFidelityBundle(b), true, b);
      assert.equal(getFidelityEntry(b)?.mode, 'vite', b);
    }
    assert.ok(listFidelityEntries().length >= required.length);
  });
});
