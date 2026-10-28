/**
 * Demo account for store review (Google Play "App access").
 * The reviewer picks "Demo account (app review)" on the Welcome screen and signs in with
 * static credentials. Only a SHA-256 of `username\npassword` ships in the bundle.
 * Demo mode never talks to Salesforce: every request to DEMO_INSTANCE_URL (or through the
 * sf-api proxy) is answered by demoRouter.js from fictional sample data.
 */
import { demoResponse } from './demoRouter.js';

const DEMO_KEY = 'zeta.pwa.demoMode';
export const DEMO_INSTANCE_URL = 'https://demo.salesforceoffline.com';
export const DEMO_ACCESS_TOKEN = 'demo-session';
const DEMO_CREDENTIAL_SHA256 = 'b27c8bfe238cba60f38730394c5aa0cf52fe2f370f1ab24e4a00fcf9309500c5';
const API_PROXY_PATH = '/.netlify/functions/sf-api';

let fetchWrapped = false;

export function isDemoMode() {
    try {
        return window.localStorage.getItem(DEMO_KEY) === '1';
    } catch (_err) {
        return false;
    }
}

async function sha256Hex(text) {
    const bytes = new TextEncoder().encode(text);
    const digest = await crypto.subtle.digest('SHA-256', bytes);
    return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function demoCredentialsMatch(username, password) {
    const user = String(username || '').trim().toLowerCase();
    if (!user || !password) return false;
    return (await sha256Hex(`${user}\n${password}`)) === DEMO_CREDENTIAL_SHA256;
}

/** Token response the normal sign-in path can apply. */
export function startDemoSession() {
    try {
        window.localStorage.setItem(DEMO_KEY, '1');
    } catch (_err) {
        /* private mode */
    }
    installDemoFetch();
    return {
        access_token: DEMO_ACCESS_TOKEN,
        instance_url: DEMO_INSTANCE_URL,
        issued_at: String(Date.now())
    };
}

export function endDemoSession() {
    try {
        window.localStorage.removeItem(DEMO_KEY);
        window.localStorage.removeItem('zeta.pwa.demoVisitEdits');
    } catch (_err) {
        /* ignore */
    }
}

function jsonResponse(body, status = 200) {
    return new Response(body == null ? null : JSON.stringify(body), {
        status,
        headers: { 'Content-Type': 'application/json' }
    });
}

async function answer(url, method, body) {
    const parsed = new URL(url, DEMO_INSTANCE_URL);
    const result = await demoResponse(`${parsed.pathname}${parsed.search}`, String(method || 'GET').toUpperCase(), body);
    return jsonResponse(result.body, result.status);
}

/** Route Salesforce-bound requests to the demo data while demo mode is on. */
export function installDemoFetch() {
    if (fetchWrapped || typeof window === 'undefined' || !isDemoMode()) return;
    fetchWrapped = true;
    const realFetch = window.fetch.bind(window);
    window.fetch = async (input, init = {}) => {
        if (!isDemoMode()) return realFetch(input, init);
        const url = typeof input === 'string' ? input : input?.url || String(input);
        const method = init.method || (typeof input === 'object' && input?.method) || 'GET';
        if (url.startsWith(DEMO_INSTANCE_URL)) {
            return answer(url, method, init.body);
        }
        if (url.endsWith(API_PROXY_PATH) || url.includes(`${API_PROXY_PATH}?`)) {
            let payload = {};
            try {
                payload = JSON.parse(init.body || '{}');
            } catch (_err) {
                payload = {};
            }
            return answer(payload.url || '', payload.method || 'GET', payload.body);
        }
        if (url.includes('/.netlify/functions/sf-token')) {
            return jsonResponse({ error: 'demo', error_description: 'Demo session has no refresh.' }, 400);
        }
        return realFetch(input, init);
    };
}

/** Thin bar on every screen so nobody mistakes the demo for live data. */
export function mountDemoBanner(onExit) {
    if (!isDemoMode() || document.getElementById('demo-banner')) return;
    const bar = document.createElement('div');
    bar.id = 'demo-banner';
    bar.className = 'login-as-banner demo-banner';
    bar.setAttribute('role', 'status');
    const text = document.createElement('span');
    text.textContent = 'Demo account: sample data only. Changes stay on this device.';
    const exit = document.createElement('button');
    exit.type = 'button';
    exit.className = 'login-as-exit';
    exit.textContent = 'Exit demo';
    exit.addEventListener('click', () => onExit());
    bar.append(text, exit);
    document.body.append(bar);
    document.documentElement.classList.add('osr-demo');
}

export function removeDemoBanner() {
    document.getElementById('demo-banner')?.remove();
    document.documentElement.classList.remove('osr-demo');
}
