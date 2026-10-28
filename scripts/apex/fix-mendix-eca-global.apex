String appName = 'Mendix_Meetings_API';
String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();
String body = '<?xml version="1.0" encoding="UTF-8"?>'
  + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:mdt="http://soap.sforce.com/2006/04/metadata">'
  + '<soapenv:Header><mdt:SessionHeader><mdt:sessionId>' + sessionId + '</mdt:sessionId></mdt:SessionHeader></soapenv:Header>'
  + '<soapenv:Body><mdt:upsertMetadata>'
  + '<mdt:metadata xsi:type="mdt:ExtlClntAppGlobalOauthSettings" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
  + '<mdt:fullName>' + appName + '</mdt:fullName>'
  + '<mdt:label>Mendix Meetings API Global OAuth</mdt:label>'
  + '<mdt:callbackUrl>https://oauth.pstmn.io/v1/callback</mdt:callbackUrl>'
  + '<mdt:externalClientApplication>' + appName + '</mdt:externalClientApplication>'
  + '<mdt:isClientCredentialsFlowEnabled>true</mdt:isClientCredentialsFlowEnabled>'
  + '<mdt:isPkceRequired>false</mdt:isPkceRequired>'
  + '<mdt:isConsumerSecretOptional>false</mdt:isConsumerSecretOptional>'
  + '<mdt:isRefreshTokenRotationEnabled>false</mdt:isRefreshTokenRotationEnabled>'
  + '<mdt:shouldRotateConsumerSecret>false</mdt:shouldRotateConsumerSecret>'
  + '</mdt:metadata>'
  + '</mdt:upsertMetadata></soapenv:Body></soapenv:Envelope>';
HttpRequest req = new HttpRequest();
req.setEndpoint(orgDomainUrl + '/services/Soap/m/64.0');
req.setMethod('POST');
req.setHeader('Content-Type', 'text/xml;charset=UTF-8');
req.setHeader('SOAPAction', '""');
req.setBody(body);
HttpResponse res = new Http().send(req);
System.debug(LoggingLevel.ERROR, res.getStatusCode() + ' ' + res.getBody());
