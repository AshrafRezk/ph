/**
 * Capacitor FCM registration → Salesforce MobilePushServiceDevice.
 * Browser / web PWA skips this path (Salesforce push is native FCM/APNs only).
 *
 * Multi-org: one APK / one Firebase project; each Salesforce org stores its own
 * MobilePushServiceDevice. Storage keys are scoped by instance host so switching
 * orgs on the same device does not reuse another org's device Id.
 */

import { plannerApiFetch } from './apex/restHelper.js';
import { openNotificationFromPush, refreshApprovalInbox } from './approvalNotifications.js';

const API_VERSION = 'v64.0';
const DEVICE_ID_KEY_PREFIX = 'zeta.pwa.pushDeviceId.';
const TOKEN_KEY_PREFIX = 'zeta.pwa.pushToken.';
/** @deprecated unscoped keys — migrated away for multi-org */
const LEGACY_DEVICE_ID_KEY = 'zeta.pwa.pushDeviceId';
const LEGACY_TOKEN_KEY = 'zeta.pwa.pushToken';
const APP_BUNDLE = 'com.zetapharma.fieldpwa';
const ANDROID_SERVICE_TYPE = 'androidGcm';

let wired = false;
let registering = false;
let isNativeFn = () => false;

function readStored(key) {
    try {
        return window.localStorage.getItem(key) || '';
    } catch {
        return '';
    }
}

function writeStored(key, value) {
    try {
        if (value) {
            window.localStorage.setItem(key, value);
        } else {
            window.localStorage.removeItem(key);
        }
    } catch {
        /* ignore */
    }
}

/** Host key for the currently authenticated Salesforce instance (multi-org safe). */
function orgStorageSuffix() {
    try {
        const base =
            (typeof globalThis !== 'undefined' && globalThis.PLANNER_REST_BASE) ||
            readStored('zeta.pwa.sfInstanceUrl') ||
            '';
        if (!base) {
            return 'default';
        }
        const host = String(base)
            .replace(/^https?:\/\//i, '')
            .split('/')[0]
            .toLowerCase();
        return host || 'default';
    } catch {
        return 'default';
    }
}

function deviceIdKey() {
    return `${DEVICE_ID_KEY_PREFIX}${orgStorageSuffix()}`;
}

function tokenKey() {
    return `${TOKEN_KEY_PREFIX}${orgStorageSuffix()}`;
}

function platformIsAndroid() {
    try {
        const cap = window.Capacitor;
        if (cap && typeof cap.getPlatform === 'function') {
            return cap.getPlatform() === 'android';
        }
    } catch {
        /* ignore */
    }
    return false;
}

function extractPayload(notification) {
    const data = notification?.data || notification?.notification?.data || {};
    const nested = typeof data === 'object' && data !== null ? data : {};
    return {
        type:
            nested.type ||
            nested.notificationType ||
            nested.notification_type ||
            nested.nid ||
            '',
        targetId:
            nested.targetId ||
            nested.target_id ||
            nested.recordId ||
            nested.oid ||
            nested.id ||
            '',
        title: notification?.title || nested.title || '',
        body: notification?.body || nested.body || nested.message || ''
    };
}

function routePushTap(notification) {
    const payload = extractPayload(notification?.notification || notification);
    document.documentElement.classList.add('osr-has-session');
    void refreshApprovalInbox();
    void openNotificationFromPush(payload);
}

async function upsertMobilePushDevice(fcmToken) {
    if (!fcmToken || !platformIsAndroid()) {
        return null;
    }
    const idKey = deviceIdKey();
    const tokKey = tokenKey();
    const previousToken = readStored(tokKey) || readStored(LEGACY_TOKEN_KEY);
    const previousId = readStored(idKey) || readStored(LEGACY_DEVICE_ID_KEY);
    if (previousToken === fcmToken && previousId && readStored(idKey)) {
        return previousId;
    }
    if (previousId) {
        try {
            await plannerApiFetch(
                `/services/data/${API_VERSION}/sobjects/MobilePushServiceDevice/${previousId}`,
                { method: 'DELETE', fresh: true }
            );
        } catch {
            /* stale id — create fresh below */
        }
        writeStored(idKey, '');
        writeStored(LEGACY_DEVICE_ID_KEY, '');
    }

    const created = await plannerApiFetch(
        `/services/data/${API_VERSION}/sobjects/MobilePushServiceDevice/`,
        {
            method: 'POST',
            fresh: true,
            body: JSON.stringify({
                ConnectionToken: fcmToken,
                ServiceType: ANDROID_SERVICE_TYPE,
                ApplicationBundle: APP_BUNDLE
            })
        }
    );
    const id = created?.id || '';
    if (id) {
        writeStored(idKey, id);
        writeStored(tokKey, fcmToken);
        writeStored(LEGACY_DEVICE_ID_KEY, '');
        writeStored(LEGACY_TOKEN_KEY, '');
    }
    return id;
}

async function ensureAndroidChannel(PushNotifications) {
    if (!platformIsAndroid() || typeof PushNotifications.createChannel !== 'function') {
        return;
    }
    try {
        await PushNotifications.createChannel({
            id: 'salesforce_field',
            name: 'Zeta Co-Pilot',
            description: 'Field alerts',
            importance: 5,
            visibility: 1,
            sound: 'default',
            vibration: true
        });
    } catch (err) {
        console.warn('[Push] createChannel failed', err);
    }
}

/**
 * @param {{ isCapacitor: () => boolean }} options
 */
export async function initPushNotifications(options = {}) {
    isNativeFn = typeof options.isCapacitor === 'function' ? options.isCapacitor : () => false;
    if (!isNativeFn() || !platformIsAndroid()) {
        return;
    }
    if (wired) {
        await registerPushNotifications();
        return;
    }

    let PushNotifications;
    try {
        ({ PushNotifications } = await import('@capacitor/push-notifications'));
    } catch (err) {
        console.warn('[Push] plugin unavailable', err);
        return;
    }

    wired = true;
    await PushNotifications.addListener('registration', (token) => {
        const value = token?.value || '';
        if (!value) return;
        void upsertMobilePushDevice(value).catch((err) => {
            console.warn('[Push] MobilePushServiceDevice register failed', err);
        });
    });
    await PushNotifications.addListener('registrationError', (err) => {
        console.warn('[Push] registrationError', err?.error || err);
    });
    await PushNotifications.addListener('pushNotificationActionPerformed', (event) => {
        routePushTap(event);
    });
    await PushNotifications.addListener('pushNotificationReceived', () => {
        void refreshApprovalInbox();
    });

    await ensureAndroidChannel(PushNotifications);
    await registerPushNotifications();
}

export async function registerPushNotifications() {
    if (!isNativeFn() || !platformIsAndroid() || registering) {
        return;
    }
    registering = true;
    try {
        const { PushNotifications } = await import('@capacitor/push-notifications');
        let perm = await PushNotifications.checkPermissions();
        if (perm.receive === 'prompt' || perm.receive === 'prompt-with-rationale') {
            perm = await PushNotifications.requestPermissions();
        }
        if (perm.receive !== 'granted') {
            console.warn('[Push] permission not granted:', perm.receive);
            return;
        }
        await PushNotifications.register();
    } catch (err) {
        console.warn('[Push] register failed', err);
    } finally {
        registering = false;
    }
}

export async function teardownPushNotifications() {
    const deviceId = readStored(deviceIdKey()) || readStored(LEGACY_DEVICE_ID_KEY);
    if (deviceId) {
        try {
            await plannerApiFetch(`/services/data/${API_VERSION}/sobjects/MobilePushServiceDevice/${deviceId}`, {
                method: 'DELETE',
                fresh: true
            });
        } catch (err) {
            console.warn('[Push] unregister device failed', err);
        }
    }
    writeStored(deviceIdKey(), '');
    writeStored(tokenKey(), '');
    writeStored(LEGACY_DEVICE_ID_KEY, '');
    writeStored(LEGACY_TOKEN_KEY, '');

    if (!isNativeFn()) {
        return;
    }
    try {
        const { PushNotifications } = await import('@capacitor/push-notifications');
        if (typeof PushNotifications.unregister === 'function') {
            await PushNotifications.unregister();
        }
        await PushNotifications.removeAllListeners();
    } catch {
        /* ignore */
    }
    wired = false;
}
