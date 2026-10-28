/**
 * SFE "Login As" handoff from Territory Management (FieldLoginAsController).
 * The console opens https://www.salesforceoffline.com/#login-as&access_token=…&instance_url=…&as=…&by=…
 * The fragment never reaches a server. We read it once, strip it from the address bar,
 * and run the device as that field user until Exit or the org session timeout.
 * There is no refresh token, so the SFE's own session can never be refreshed in by mistake.
 * The session that was signed in before is saved, and Exit (or timeout) restores it.
 */

const LOGIN_AS_KEY = 'zeta.pwa.loginAs';
const RETURN_SESSION_KEY = 'zeta.pwa.loginAsReturn';
const ENDED_NOTICE_KEY = 'zeta.pwa.loginAsEnded';
const HASH_PREFIX = '#login-as';
const BANNER_ID = 'login-as-banner';

/** Whoever was signed in before Login As: tokens, login host, identity, last screen. */
const RETURN_SESSION_KEYS = [
    'zeta.pwa.sfAccessToken',
    'zeta.pwa.sfRefreshToken',
    'zeta.pwa.sfTokenIssuedAt',
    'zeta.pwa.sfInstanceUrl',
    'zeta.pwa.sfLoginUrl',
    'zeta.pwa.sfLoginEnv',
    'zeta.pwa.sfCustomDomain',
    'zeta.pwa.sfUserName',
    'zeta.pwa.sfUserUsername',
    'zeta.pwa.sfUserId',
    'zeta.pwa.sfUserPicture',
    'zeta.pwa.sfUserFirstName',
    'zeta.pwa.sfUserLastName',
    'zeta.pwa.sessionConfirmed',
    'zeta.pwa.lastWorkspace'
];

/** Per-user reads cached in localStorage. The REST GET cache in IndexedDB is cleared by the caller. */
const USER_CACHE_PREFIXES = [
    'zeta.pwa.tab.',
    'zeta.pwa.apps.',
    'zeta.pwa.appTabs.',
    'zeta.pwa.allTabs.',
    'zeta.pwa.fieldFeatures.',
    'zeta.pwa.bootstrap.',
    'zeta.pwa.sfUserProfile',
    'zeta.pwa.sfTerritoryContext',
    'zeta.pwa.plannerViewerContext',
    'zeta.pwa.planAccount',
    'zeta.pwa.activeVisitId',
    'zeta.pwa.openVisitCoaching',
    'zeta.pwa.openTotApproval',
    'zeta.pwa.openNewAccount'
];

/** Token response shape (access_token, instance_url, issued_at) plus who/by, or null. */
export function readLoginAsHandoff(hash = window.location.hash) {
    if (!hash || !hash.startsWith(HASH_PREFIX)) return null;
    const params = new URLSearchParams(hash.slice(HASH_PREFIX.length).replace(/^&/, ''));
    const accessToken = (params.get('access_token') || '').trim();
    const instanceUrl = (params.get('instance_url') || '').trim();
    if (!accessToken || !/^https:\/\/[^/]+\.salesforce\.com\/?$/.test(instanceUrl)) return null;
    return {
        access_token: accessToken,
        instance_url: instanceUrl,
        issued_at: params.get('issued_at') || String(Date.now()),
        asName: params.get('as') || '',
        byName: params.get('by') || ''
    };
}

export function clearLoginAsHash() {
    if (window.location.hash.startsWith(HASH_PREFIX)) {
        window.history.replaceState({}, document.title, window.location.pathname || '/');
    }
}

export function rememberLoginAs(handoff) {
    try {
        window.localStorage.setItem(
            LOGIN_AS_KEY,
            JSON.stringify({ asName: handoff.asName, byName: handoff.byName, startedAt: new Date().toISOString() })
        );
    } catch (_err) {
        /* private mode */
    }
}

export function readLoginAs() {
    try {
        const raw = window.localStorage.getItem(LOGIN_AS_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch (_err) {
        return null;
    }
}

export function clearLoginAs() {
    try {
        window.localStorage.removeItem(LOGIN_AS_KEY);
    } catch (_err) {
        /* ignore */
    }
    document.getElementById(BANNER_ID)?.remove();
    document.documentElement.classList.remove('osr-login-as');
}

/**
 * Keep the signed-in person's session so Exit can hand the device back to them.
 * Call before the Login As tokens overwrite it. A second Login As keeps the first saved session.
 */
export function saveReturnSession() {
    if (readLoginAs()) return;
    try {
        const saved = {};
        for (const key of RETURN_SESSION_KEYS) {
            const value = window.localStorage.getItem(key);
            if (value !== null) saved[key] = value;
        }
        if (saved['zeta.pwa.sfAccessToken'] || saved['zeta.pwa.sfRefreshToken']) {
            window.localStorage.setItem(RETURN_SESSION_KEY, JSON.stringify(saved));
        } else {
            window.localStorage.removeItem(RETURN_SESSION_KEY);
        }
    } catch (_err) {
        /* private mode */
    }
}

/** Put the saved session back. Returns true when there was one to restore. */
export function restoreReturnSession() {
    try {
        const raw = window.localStorage.getItem(RETURN_SESSION_KEY);
        window.localStorage.removeItem(RETURN_SESSION_KEY);
        if (!raw) return false;
        const saved = JSON.parse(raw);
        if (!saved || typeof saved !== 'object') return false;
        for (const key of RETURN_SESSION_KEYS) {
            if (typeof saved[key] === 'string') window.localStorage.setItem(key, saved[key]);
        }
        return !!(saved['zeta.pwa.sfAccessToken'] || saved['zeta.pwa.sfRefreshToken']);
    } catch (_err) {
        return false;
    }
}

export function dropReturnSession() {
    try {
        window.localStorage.removeItem(RETURN_SESSION_KEY);
    } catch (_err) {
        /* ignore */
    }
}

/** Remove the field user's cached reads so the next person never sees them. */
export function clearUserCaches() {
    try {
        const keys = [];
        for (let i = 0; i < window.localStorage.length; i++) {
            const key = window.localStorage.key(i);
            if (key && USER_CACHE_PREFIXES.some((prefix) => key.startsWith(prefix))) keys.push(key);
        }
        keys.forEach((key) => window.localStorage.removeItem(key));
    } catch (_err) {
        /* ignore */
    }
}

/** One-time message shown after the reload that hands the device back. */
export function setLoginAsEndedNotice(message) {
    try {
        window.sessionStorage.setItem(ENDED_NOTICE_KEY, message);
    } catch (_err) {
        /* ignore */
    }
}

export function takeLoginAsEndedNotice() {
    try {
        const message = window.sessionStorage.getItem(ENDED_NOTICE_KEY) || '';
        window.sessionStorage.removeItem(ENDED_NOTICE_KEY);
        return message;
    } catch (_err) {
        return '';
    }
}

/** Orange bar on every screen while a Login As session is active. */
export function mountLoginAsBanner(onExit) {
    const state = readLoginAs();
    if (!state) return;
    let bar = document.getElementById(BANNER_ID);
    if (!bar) {
        bar = document.createElement('div');
        bar.id = BANNER_ID;
        bar.className = 'login-as-banner';
        bar.setAttribute('role', 'status');
        document.body.append(bar);
    }
    bar.replaceChildren();
    const text = document.createElement('span');
    text.className = 'login-as-text';
    const who = state.asName || 'a field user';
    text.textContent = state.byName
        ? `Signed in as ${who} by ${state.byName}. Anything you save is saved as ${who}.`
        : `Signed in as ${who}. Anything you save is saved as ${who}.`;
    const exit = document.createElement('button');
    exit.type = 'button';
    exit.className = 'login-as-exit';
    exit.textContent = 'Exit';
    exit.addEventListener('click', () => onExit());
    bar.append(text, exit);
    document.documentElement.classList.add('osr-login-as');
}
