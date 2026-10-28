import test from 'node:test';
import assert from 'node:assert/strict';

const store = {};
const listeners = [];
globalThis.window = {
    localStorage: { getItem: (k) => (k in store ? store[k] : null) },
    addEventListener: (name, fn) => listeners.push({ name, fn })
};
const KEY = 'zeta.pwa.sfTerritoryContext';
const { territoryScopeKey, createScopeTracker } = await import('./_territoryScope.js');

function announceSwitch() {
    listeners.filter((l) => l.name === 'pharma-territory-context').forEach((l) => l.fn());
}

test('territory key follows the switcher', () => {
    delete store[KEY];
    assert.equal(territoryScopeKey(), 'all');
    store[KEY] = JSON.stringify({ usingAllAssigned: true, tree: [] });
    assert.equal(territoryScopeKey(), 'all');
    store[KEY] = JSON.stringify({ usingAllAssigned: false, selectedTerritoryId: '0MIabc', tree: [] });
    assert.equal(territoryScopeKey(), '0MIabc');
    store[KEY] = '{broken';
    assert.equal(territoryScopeKey(), 'all');
});

test('first call after a switch waits on the network, then the saved copy is used again', () => {
    store[KEY] = JSON.stringify({ usingAllAssigned: false, selectedTerritoryId: 'EAST', tree: [] });
    const next = createScopeTracker();
    assert.deepEqual(next(), { scope: 'EAST', fresh: false }, 'page load paints the saved copy');
    assert.deepEqual(next(), { scope: 'EAST', fresh: false });
    announceSwitch();
    assert.deepEqual(next(), { scope: 'EAST', fresh: true }, 'switch announced even though the key did not change');
    assert.deepEqual(next(), { scope: 'EAST', fresh: false });
    store[KEY] = JSON.stringify({ usingAllAssigned: true, tree: [] });
    assert.deepEqual(next(), { scope: 'all', fresh: true }, 'territory key changed');
});
