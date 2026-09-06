/** Offline stand-in for Lightning Message Service. */
export const APPLICATION_SCOPE = Symbol('APPLICATION_SCOPE');

export function createMessageContext() {
    return { __lms: true };
}

export function releaseMessageContext(_context) {
    return undefined;
}

export function subscribe(_messageContext, _channel, listener, _options) {
    if (typeof listener === 'function') {
        // No live LMS traffic offline.
    }
    return { unsubscribe() {} };
}

export function unsubscribe(_subscription) {
    return undefined;
}

export function publish(_messageContext, _channel, _payload) {
    return undefined;
}

/**
 * @wire(MessageContext) adapter — emits a fake context object.
 */
export function MessageContext(dataCallback) {
    if (!(this instanceof MessageContext)) {
        return createMessageContext();
    }
    this._dataCallback = dataCallback;
}
MessageContext.prototype.connect = function connect() {
    if (this._dataCallback) {
        this._dataCallback({ data: createMessageContext(), error: undefined });
    }
};
MessageContext.prototype.update = function update() {};
MessageContext.prototype.disconnect = function disconnect() {
    this._dataCallback = null;
};
