import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';

function memoryStorage() {
    const map = new Map();
    return {
        get length() {
            return map.size;
        },
        key: (i) => [...map.keys()][i] ?? null,
        getItem: (k) => (map.has(k) ? map.get(k) : null),
        setItem: (k, v) => map.set(k, String(v)),
        removeItem: (k) => map.delete(k),
        clear: () => map.clear()
    };
}

globalThis.window = { localStorage: memoryStorage(), sessionStorage: memoryStorage() };
globalThis.document = { getElementById: () => null, documentElement: { classList: { remove() {} } } };

const {
    clearLoginAs,
    clearUserCaches,
    rememberLoginAs,
    restoreReturnSession,
    saveReturnSession,
    setLoginAsEndedNotice,
    takeLoginAsEndedNotice
} = await import('./loginAs.js');

const ls = window.localStorage;

beforeEach(() => {
    ls.clear();
    window.sessionStorage.clear();
});

test('Exit restores the session that was signed in before Login As', () => {
    ls.setItem('zeta.pwa.sfAccessToken', 'sfe-access');
    ls.setItem('zeta.pwa.sfRefreshToken', 'sfe-refresh');
    ls.setItem('zeta.pwa.sfUserName', 'SFE Admin');
    saveReturnSession();
    rememberLoginAs({ asName: 'Rep One', byName: 'SFE Admin' });

    // Login As replaces the device session, then logout wipes it.
    ls.setItem('zeta.pwa.sfAccessToken', 'rep-access');
    ls.removeItem('zeta.pwa.sfRefreshToken');
    ls.setItem('zeta.pwa.sfUserName', 'Rep One');
    ls.removeItem('zeta.pwa.sfAccessToken');
    ls.removeItem('zeta.pwa.sfUserName');
    clearLoginAs();

    assert.equal(restoreReturnSession(), true);
    assert.equal(ls.getItem('zeta.pwa.sfAccessToken'), 'sfe-access');
    assert.equal(ls.getItem('zeta.pwa.sfRefreshToken'), 'sfe-refresh');
    assert.equal(ls.getItem('zeta.pwa.sfUserName'), 'SFE Admin');
    assert.equal(ls.getItem('zeta.pwa.loginAsReturn'), null);
});

test('a second Login As keeps the original saved session', () => {
    ls.setItem('zeta.pwa.sfRefreshToken', 'sfe-refresh');
    saveReturnSession();
    rememberLoginAs({ asName: 'Rep One' });
    ls.setItem('zeta.pwa.sfAccessToken', 'rep-one-access');
    ls.removeItem('zeta.pwa.sfRefreshToken');
    saveReturnSession();

    ls.removeItem('zeta.pwa.sfAccessToken');
    assert.equal(restoreReturnSession(), true);
    assert.equal(ls.getItem('zeta.pwa.sfRefreshToken'), 'sfe-refresh');
    assert.equal(ls.getItem('zeta.pwa.sfAccessToken'), null);
});

test('nobody signed in before means nothing to restore', () => {
    saveReturnSession();
    assert.equal(restoreReturnSession(), false);
});

test('clearUserCaches drops cached reads but keeps tokens', () => {
    ls.setItem('zeta.pwa.sfAccessToken', 'keep');
    ls.setItem('zeta.pwa.tab.accounts', '{}');
    ls.setItem('zeta.pwa.appTabs.v11', '{}');
    ls.setItem('zeta.pwa.sfTerritoryContext', '{}');
    ls.setItem('zeta.pwa.planAccountId', '001');
    clearUserCaches();
    assert.equal(ls.getItem('zeta.pwa.sfAccessToken'), 'keep');
    assert.equal(ls.length, 1);
});

test('ended notice is shown once', () => {
    setLoginAsEndedNotice('back');
    assert.equal(takeLoginAsEndedNotice(), 'back');
    assert.equal(takeLoginAsEndedNotice(), '');
});
