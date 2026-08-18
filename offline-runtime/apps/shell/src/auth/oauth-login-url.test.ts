import assert from 'node:assert/strict';
import { describe, it } from 'node:test';
import {
  normalizeSalesforceLoginUrl,
  extractMyDomainLabel,
  myDomainLoginUrlFromLabel,
  loginUrlFromPageParams,
  isStandardSalesforceLogin,
  isOAuthCallbackUrl,
  oauthCallbackScheme,
  applyKnownCustomTabMetadata,
  PRODUCTION_LOGIN,
  SANDBOX_LOGIN
} from './oauth.js';

describe('login URL params / My Domain', () => {
  it('extracts only the short My Domain label', () => {
    assert.equal(extractMyDomainLabel('abcd'), 'abcd');
    assert.equal(extractMyDomainLabel('ABCD.my.salesforce.com'), 'abcd');
    assert.equal(extractMyDomainLabel('https://abcd.my.salesforce.com/'), 'abcd');
  });

  it('appends .my.salesforce.com from the short label', () => {
    assert.equal(myDomainLoginUrlFromLabel('abcd'), 'https://abcd.my.salesforce.com');
    assert.equal(
      myDomainLoginUrlFromLabel('abcd.my.salesforce.com'),
      'https://abcd.my.salesforce.com'
    );
  });

  it('normalizes bare My Domain labels', () => {
    assert.equal(normalizeSalesforceLoginUrl('zetapharma'), 'https://zetapharma.my.salesforce.com');
    assert.equal(
      normalizeSalesforceLoginUrl('ZetaPharma'),
      'https://zetapharma.my.salesforce.com'
    );
  });

  it('accepts hosts and full URLs', () => {
    assert.equal(
      normalizeSalesforceLoginUrl('zetapharma.my.salesforce.com'),
      'https://zetapharma.my.salesforce.com'
    );
    assert.equal(
      normalizeSalesforceLoginUrl('https://zetapharma--uat.sandbox.my.salesforce.com/'),
      'https://zetapharma--uat.sandbox.my.salesforce.com'
    );
  });

  it('reads domain and loginUrl query params', () => {
    assert.equal(
      loginUrlFromPageParams('?domain=zetapharma'),
      'https://zetapharma.my.salesforce.com'
    );
    assert.equal(
      loginUrlFromPageParams('?loginUrl=https://test.salesforce.com'),
      'https://test.salesforce.com'
    );
    assert.equal(loginUrlFromPageParams(''), null);
  });

  it('detects standard login hosts', () => {
    assert.equal(isStandardSalesforceLogin(PRODUCTION_LOGIN), true);
    assert.equal(isStandardSalesforceLogin(SANDBOX_LOGIN), true);
    assert.equal(isStandardSalesforceLogin('https://zetapharma.my.salesforce.com'), false);
  });

  it('detects native OAuth callback URLs', () => {
    assert.equal(
      isOAuthCallbackUrl('com.osr.offline://oauth/callback?code=abc&state=xyz'),
      true
    );
    assert.equal(isOAuthCallbackUrl('https://localhost:5173/oauth/callback?code=abc'), true);
    assert.equal(isOAuthCallbackUrl('com.osr.offline://home'), false);
  });

  it('extracts OAuth callback scheme from redirect URI', () => {
    assert.equal(oauthCallbackScheme('com.osr.offline://oauth/callback'), 'com.osr.offline');
  });

  it('normalizes Pharmacy Sales tab to direct LWC metadata', () => {
    const row = applyKnownCustomTabMetadata({
      developerName: 'Pharmacy_Sales_Dashboard',
      label: 'Pharmacy Sales',
      tab: {
        tabType: 'flexipage',
        pageDeveloperName: 'Pharmacy_Sales_Dashboard'
      }
    });
    assert.equal((row.tab as Record<string, unknown>).tabType, 'lwc');
    assert.equal((row.tab as Record<string, unknown>).lwcBundle, 'c/pharmacySalesDashboard');
    assert.equal((row.tab as Record<string, unknown>).pageDeveloperName, undefined);
  });
});
