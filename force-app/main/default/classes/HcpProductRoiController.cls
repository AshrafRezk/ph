public with sharing class HcpProductRoiController {
    @AuraEnabled(cacheable=true)
    public static HcpProductRoiService.RoiPayload getAccountRoi(Id accountId, Id productId) {
        try {
            return HcpProductRoiService.getAccountRoi(accountId, productId);
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            String message = String.isBlank(e.getMessage()) ? 'Unable to load HCP product ROI.' : e.getMessage();
            AuraHandledException wrapped = new AuraHandledException(message);
            wrapped.setMessage(message);
            throw wrapped;
        }
    }
}
