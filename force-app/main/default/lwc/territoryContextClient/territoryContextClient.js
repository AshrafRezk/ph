import { subscribe, unsubscribe, publish, APPLICATION_SCOPE } from 'lightning/messageService';
import TERRITORY_CONTEXT_CHANNEL from '@salesforce/messageChannel/TerritoryContext__c';

const WINDOW_EVENT = 'pharma-territory-context';
const STORAGE_KEY = 'pharma-territory-context';
const BROADCAST_NAME = 'pharma-territory-context';

function toDetail(payload) {
    return {
        territoryId: payload?.territoryId || '',
        territoryName: payload?.territoryName || '',
        usingAllAssigned: payload?.usingAllAssigned === true
    };
}

function openBroadcastChannel() {
    if (typeof BroadcastChannel === 'undefined') {
        return null;
    }
    try {
        return new BroadcastChannel(BROADCAST_NAME);
    } catch (_error) {
        return null;
    }
}

export function getStoredTerritoryContext() {
    if (typeof window === 'undefined') {
        return null;
    }
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch (_error) {
        return null;
    }
}

export function publishTerritoryContextChanged(messageContext, payload) {
    const detail = toDetail(payload);
    if (messageContext) {
        publish(messageContext, TERRITORY_CONTEXT_CHANNEL, detail);
    }
    if (typeof window !== 'undefined') {
        try {
            window.dispatchEvent(new CustomEvent(WINDOW_EVENT, { detail, bubbles: true, composed: true }));
        } catch (_error) {
            // LWS may block Window CustomEvent dispatch; LMS remains the primary channel.
        }
        try {
            window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ ...detail, ts: Date.now() }));
        } catch (_error) {
            // private mode / disabled storage / LWS isolation
        }
    }
    const channel = openBroadcastChannel();
    if (channel) {
        try {
            channel.postMessage(detail);
        } catch (_error) {
            // Ignore BroadcastChannel isolation.
        }
        try {
            channel.close();
        } catch (_error) {
            // Ignore.
        }
    }
}

export function subscribeTerritoryContext(messageContext, onChange) {
    if (typeof onChange !== 'function') {
        return null;
    }

    let lastFiredAt = 0;
    const handleChange = (message) => {
        const now = Date.now();
        if (now - lastFiredAt < 300) {
            return;
        }
        lastFiredAt = now;
        onChange(message || {});
    };

    let subscription = null;
    if (messageContext) {
        subscription = subscribe(messageContext, TERRITORY_CONTEXT_CHANNEL, handleChange, {
            scope: APPLICATION_SCOPE
        });
    }

    const windowHandler = (event) => handleChange(event?.detail || {});
    const storageHandler = (event) => {
        if (event?.key && event.key !== STORAGE_KEY) {
            return;
        }
        handleChange(getStoredTerritoryContext() || {});
    };
    let broadcastChannel = openBroadcastChannel();
    const broadcastHandler = (event) => handleChange(event?.data || {});

    if (typeof window !== 'undefined') {
        try {
            window.addEventListener(WINDOW_EVENT, windowHandler);
        } catch (_error) {
            // LWS may block some Window listeners; LMS remains the primary channel.
        }
        try {
            window.addEventListener('storage', storageHandler);
        } catch (_error) {
            // Ignore LWS / private-mode storage listeners.
        }
    }
    if (broadcastChannel) {
        try {
            broadcastChannel.addEventListener('message', broadcastHandler);
        } catch (_error) {
            broadcastChannel = null;
        }
    }

    return { subscription, windowHandler, storageHandler, broadcastChannel, broadcastHandler };
}

export function unsubscribeTerritoryContext(handle) {
    if (!handle) {
        return;
    }
    if (handle.subscription) {
        unsubscribe(handle.subscription);
    }
    if (typeof window !== 'undefined' && handle.windowHandler) {
        try {
            window.removeEventListener(WINDOW_EVENT, handle.windowHandler);
        } catch (_error) {
            // Ignore LWS / teardown races.
        }
    }
    if (typeof window !== 'undefined' && handle.storageHandler) {
        try {
            window.removeEventListener('storage', handle.storageHandler);
        } catch (_error) {
            // Ignore LWS / teardown races.
        }
    }
    if (handle.broadcastChannel) {
        try {
            handle.broadcastChannel.removeEventListener('message', handle.broadcastHandler);
            handle.broadcastChannel.close();
        } catch (_error) {
            // Ignore.
        }
    }
}

/** Cache/offline key suffix for the active territory switcher selection. */
export function getTerritoryContextSuffix() {
    const stored = getStoredTerritoryContext();
    if (!stored || stored.usingAllAssigned) {
        return 'all';
    }
    return stored.territoryId || 'all';
}
