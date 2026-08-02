import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  scanLwcSource,
  rewriteApexImportsToInvoker,
  compileLwcModule
} from './index.js';

describe('lwc-compile', () => {
  it('scans imports and apex bindings', () => {
    const finding = scanLwcSource(
      'c/homeOfficeMessages',
      `import { LightningElement } from 'lwc';
import getActiveMessages from '@salesforce/apex/HomeOfficeMessageController.getActiveMessages';
import { NavigationMixin } from 'lightning/navigation';`,
      `<template><lightning-card><lightning-icon></lightning-icon></lightning-card></template>`
    );
    assert.ok(finding.apexBindings.includes('HomeOfficeMessageController.getActiveMessages'));
    assert.equal(finding.usesNavigation, true);
    assert.ok(finding.usesLightningBase.includes('lightning-card'));
  });

  it('rewrites apex imports', () => {
    const out = rewriteApexImportsToInvoker(
      `import getActiveMessages from '@salesforce/apex/HomeOfficeMessageController.getActiveMessages';`
    );
    assert.ok(out.includes('createApexInvoker'));
    assert.ok(out.includes('HomeOfficeMessageController.getActiveMessages'));
  });

  it('compiles a trivial LWC', async () => {
    const result = await compileLwcModule({
      bundleName: 'c/helloOsr',
      name: 'helloOsr',
      js: `import { LightningElement, api } from 'lwc';
export default class HelloOsr extends LightningElement {
  @api name = 'OSR';
}`,
      html: `<template><h1>Hello, {name}</h1></template>`
    });
    assert.equal(result.ok, true);
    assert.ok(result.code && result.code.length > 50);
  });
});
