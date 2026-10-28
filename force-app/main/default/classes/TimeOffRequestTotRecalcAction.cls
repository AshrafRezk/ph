/**
 * Invocable entry points replacing org-only TimeOffRequestTOTRecalc flows.
 */
public with sharing class TimeOffRequestTotRecalcAction {
    public class RecalcRequest {
        @InvocableVariable(required=true label='Employee User Id')
        public Id employeeId;
        @InvocableVariable(required=true label='Start Date')
        public Date startDate;
        @InvocableVariable(required=true label='End Date')
        public Date endDate;
    }

    @InvocableMethod(
        label='Recalc TOT For Employee Range'
        description='Recalculates TOT_Days on Employee Time Card day entries for the employee and date range.'
    )
    public static void recalcForRange(List<RecalcRequest> requests) {
        if (requests == null) {
            return;
        }
        for (RecalcRequest request : requests) {
            try {
                EmployeeTimeCardFlowHelper.recalcTOTForEmployeeAndRange(
                    request.employeeId,
                    request.startDate,
                    request.endDate
                );
            } catch (Exception ex) {
                System.debug(
                    LoggingLevel.WARN,
                    'TOT recalc skipped: ' + ex.getMessage()
                );
            }
        }
    }
}