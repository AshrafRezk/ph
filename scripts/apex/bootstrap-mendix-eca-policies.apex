String appName = 'Mendix_Meetings_API';
String orgDomainUrl = URL.getOrgDomainUrl().toExternalForm();
String sessionId = UserInfo.getSessionId();
String metadataUrl = orgDomainUrl + '/services/Soap/m/64.0';
String body = '<?xml version="1.0" encoding="UTF-8"?>'
  + '<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:mdt="http://soap.sforce.com/2006/04/metadata">'
  + '<soapenv:Header><mdt:SessionHeader><mdt:sessionId>' + sessionId + '</mdt:sessionId></mdt:SessionHeader></soapenv:Header>'
  + '<soapenv:Body><mdt:upsertMetadata>'
  + '<mdt:metadata xsi:type="mdt:ExtlClntAppOauthConfigurablePolicies" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
  + '<mdt:fullName>' + appName + '</mdt:fullName>'
  + '<mdt:label>Mendix Meetings API OAuth Policies</mdt:label>'
  + '<mdt:externalClientApplication>' + appName + '</mdt:externalClientApplication>'
  + '<mdt:isClientCredentialsFlowEnabled>true</mdt:isClientCredentialsFlowEnabled>'
  + '<mdt:clientCredentialsFlowUser>mendix.api@zetapharma.com</mdt:clientCredentialsFlowUser>'
  + '</mdt:metadata>'
  + '</mdt:upsertMetadata></soapenv:Body></soapenv:Envelope>';
HttpRequest req = new HttpRequest();
req.setEndpoint(metadataUrl);
req.setMethod('POST');
req.setHeader('Content-Type', 'text/xml;charset=UTF-8');
req.setHeader('SOAPAction', '""');
req.setTimeout(120000);
req.setBody(body);
HttpResponse res = new Http().send(req);
System.debug(LoggingLevel.ERROR, res.getStatusCode() + ' ' + res.getBody());
