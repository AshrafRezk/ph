/**
 * Bootstrap OAuth for Mendix_Meetings_API External Client App.
 * Enables Client Credentials flow for server-to-server auth.
 */
String appName = 'Mendix_Meetings_API';
String scopes = 'Api, RefreshToken, Full';
String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();
String metadataUrl = orgDomainUrl + '/services/Soap/m/64.0';

String buildSoapEnvelope(String metadataXml) {
  return '<?xml version="1.0" encoding="UTF-8"?>'
    + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" '
    + 'xmlns:mdt="http://soap.sforce.com/2006/04/metadata">'
    + '<soapenv:Header>'
    + '<mdt:SessionHeader><mdt:sessionId>' + sessionId + '</mdt:sessionId></mdt:SessionHeader>'
    + '</soapenv:Header>'
    + '<soapenv:Body>'
    + '<mdt:upsertMetadata>'
    + metadataXml
    + '</mdt:upsertMetadata>'
    + '</soapenv:Body>'
    + '</soapenv:Envelope>';
}

String callMetadataApi(String soapBody) {
  HttpRequest req = new HttpRequest();
  req.setEndpoint(metadataUrl);
  req.setMethod('POST');
  req.setHeader('Content-Type', 'text/xml;charset=UTF-8');
  req.setHeader('SOAPAction', '""');
  req.setTimeout(120000);
  req.setBody(soapBody);
  HttpResponse res = new Http().send(req);
  System.debug(LoggingLevel.ERROR, 'HTTP ' + res.getStatusCode() + ' body=' + res.getBody());
  return res.getBody();
}

// Remote site for self-callout
try {
  String rssMdt =
    '<mdt:metadata xsi:type="mdt:RemoteSiteSetting" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
    + '<mdt:fullName>Mendix_Meetings_API_Bootstrap</mdt:fullName>'
    + '<mdt:description>Bootstrap remote site for Mendix ECA OAuth</mdt:description>'
    + '<mdt:disableProtocolSecurity>false</mdt:disableProtocolSecurity>'
    + '<mdt:isActive>true</mdt:isActive>'
    + '<mdt:url>' + orgDomainUrl + '</mdt:url>'
    + '</mdt:metadata>';
  callMetadataApi(buildSoapEnvelope(rssMdt));
} catch (Exception e) {
  System.debug('RSS: ' + e.getMessage());
}

// OAuth settings
callMetadataApi(
  buildSoapEnvelope(
    '<mdt:metadata xsi:type="mdt:ExtlClntAppOauthSettings" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      + '<mdt:fullName>' + appName + '</mdt:fullName>'
      + '<mdt:label>Mendix Meetings API OAuth</mdt:label>'
      + '<mdt:commaSeparatedOauthScopes>' + scopes + '</mdt:commaSeparatedOauthScopes>'
      + '<mdt:externalClientApplication>' + appName + '</mdt:externalClientApplication>'
      + '<mdt:isFirstPartyAppEnabled>false</mdt:isFirstPartyAppEnabled>'
      + '</mdt:metadata>'
  )
);

// Global OAuth (creates consumer key/secret) — client credentials ON
callMetadataApi(
  buildSoapEnvelope(
    '<mdt:metadata xsi:type="mdt:ExtlClntAppGlobalOauthSettings" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      + '<mdt:fullName>' + appName + '</mdt:fullName>'
      + '<mdt:label>Mendix Meetings API Global OAuth</mdt:label>'
      + '<mdt:callbackUrl>https://oauth.pstmn.io/v1/callback</mdt:callbackUrl>'
      + '<mdt:externalClientApplication>' + appName + '</mdt:externalClientApplication>'
      + '<mdt:isClientCredentialsFlowEnabled>true</mdt:isClientCredentialsFlowEnabled>'
      + '<mdt:isCodeCredFlowEnabled>false</mdt:isCodeCredFlowEnabled>'
      + '<mdt:isCodeCredPostOnly>false</mdt:isCodeCredPostOnly>'
      + '<mdt:isConsumerSecretOptional>false</mdt:isConsumerSecretOptional>'
      + '<mdt:isDeviceFlowEnabled>false</mdt:isDeviceFlowEnabled>'
      + '<mdt:isIntrospectAllTokens>false</mdt:isIntrospectAllTokens>'
      + '<mdt:isPkceRequired>false</mdt:isPkceRequired>'
      + '<mdt:isRefreshTokenRotationEnabled>false</mdt:isRefreshTokenRotationEnabled>'
      + '<mdt:isSecretRequiredForRefreshToken>true</mdt:isSecretRequiredForRefreshToken>'
      + '<mdt:isSecretRequiredForTokenExchange>true</mdt:isSecretRequiredForTokenExchange>'
      + '<mdt:isTokenExchangeEnabled>false</mdt:isTokenExchangeEnabled>'
      + '<mdt:shouldRotateConsumerKey>false</mdt:shouldRotateConsumerKey>'
      + '<mdt:shouldRotateConsumerSecret>false</mdt:shouldRotateConsumerSecret>'
      + '</mdt:metadata>'
  )
);

// Enable OAuth plugin
callMetadataApi(
  buildSoapEnvelope(
    '<mdt:metadata xsi:type="mdt:ExtlClntAppConfigurablePolicies" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      + '<mdt:fullName>' + appName + '</mdt:fullName>'
      + '<mdt:label>Mendix Meetings API Policies</mdt:label>'
      + '<mdt:externalClientApplication>' + appName + '</mdt:externalClientApplication>'
      + '<mdt:isEnabled>true</mdt:isEnabled>'
      + '<mdt:isOauthPluginEnabled>true</mdt:isOauthPluginEnabled>'
      + '</mdt:metadata>'
  )
);

// Client credentials run-as user
callMetadataApi(
  buildSoapEnvelope(
    '<mdt:metadata xsi:type="mdt:ExtlClntAppOauthConfigurablePolicies" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      + '<mdt:fullName>' + appName + '</mdt:fullName>'
      + '<mdt:label>Mendix Meetings API OAuth Policies</mdt:label>'
      + '<mdt:externalClientApplication>' + appName + '</mdt:externalClientApplication>'
      + '<mdt:isClientCredentialsFlowEnabled>true</mdt:isClientCredentialsFlowEnabled>'
      + '<mdt:clientCredentialsFlowUser>mendix.api@zetapharma.com</mdt:clientCredentialsFlowUser>'
      + '<mdt:ipRelaxationPolicy>BYPASS</mdt:ipRelaxationPolicy>'
      + '<mdt:refreshTokenPolicy>infinite</mdt:refreshTokenPolicy>'
      + '<mdt:permittedUsersPolicy>AllGuestUsers</mdt:permittedUsersPolicy>'
      + '</mdt:metadata>'
  )
);

System.debug('Mendix ECA OAuth bootstrap finished');
