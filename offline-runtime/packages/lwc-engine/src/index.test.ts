import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { listRegisteredLwcs, registerLwcModule } from './registry.js';

describe('lwc-engine registry', () => {
  it('registers modules', () => {
    class Demo {}
    registerLwcModule('c/helloOsr', Demo);
    assert.ok(listRegisteredLwcs().includes('c/helloOsr'));
  });
});
