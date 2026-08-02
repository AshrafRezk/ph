import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { isBridgeMessage, OSR_BRIDGE_CHANNEL, newRequestId } from './index.js';

describe('bridge protocol', () => {
  it('validates messages', () => {
    assert.equal(
      isBridgeMessage({
        channel: OSR_BRIDGE_CHANNEL,
        type: 'req',
        id: '1',
        method: 'ping'
      }),
      true
    );
    assert.equal(isBridgeMessage({ type: 'req' }), false);
  });

  it('makes request ids', () => {
    assert.match(newRequestId(), /^br_/);
  });
});
