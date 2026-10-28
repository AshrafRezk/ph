@IsTest
private class ClassificationApprovalRouterTest {
    @IsTest
    static void resolve_fallsBackToManagerWithoutApprovers() {
        User me = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId()];
        Test.startTest();
        System.assertEquals(me.ManagerId, ClassificationApprovalRouter.resolveApproverId(me.Id));
        System.assertEquals(null, ClassificationApprovalRouter.resolveApproverId(null));
        Test.stopTest();
    }

    @IsTest
    static void resolve_prefersTheBusinessUnitSfeOverAllLines() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
            SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false),
            SfeApproverTestData.row(data.allLinesSfe.Id, null, true)
        });

        Test.startTest();
        Id forRep = ClassificationApprovalRouter.resolveApproverId(data.rep.Id);
        Id forOtherRep = ClassificationApprovalRouter.resolveApproverId(data.otherRep.Id);
        Id forTrainee = ClassificationApprovalRouter.resolveApproverId(data.trainee.Id);
        Id forTraineeOnSeat = ClassificationApprovalRouter.resolveApproverId(data.trainee.Id, data.seat.Id);
        Test.stopTest();

        System.assertEquals(data.businessUnitSfe.Id, forRep);
        System.assertEquals(data.allLinesSfe.Id, forOtherRep, 'Lines without their own SFE go to All Lines.');
        System.assertEquals(data.allLinesSfe.Id, forTrainee, 'All Lines covers users without a seat.');
        System.assertEquals(data.businessUnitSfe.Id, forTraineeOnSeat, 'The cycle territory decides the line.');
    }

    @IsTest
    static void resolve_skipsTheEmployeeAndNewAccountOnlyRows() {
        SfeApproverTestData data = SfeApproverTestData.build();
        if (data == null) {
            return;
        }
        SFE_Approver_Assignment__c accountsOnly = SfeApproverTestData.row(data.lineSfe.Id, data.line.Name, false);
        accountsOnly.Approves_Classification__c = false;
        SfeApproverTestData.assign(new List<SFE_Approver_Assignment__c>{
            accountsOnly,
            SfeApproverTestData.row(data.businessUnitSfe.Id, data.businessUnit.Name, false)
        });

        Test.startTest();
        Id forRep = ClassificationApprovalRouter.resolveApproverId(data.rep.Id);
        Id forSfeOwnCycle = ClassificationApprovalRouter.resolveApproverId(data.businessUnitSfe.Id, data.seat.Id);
        Test.stopTest();

        System.assertEquals(data.businessUnitSfe.Id, forRep, 'Rows for new accounts only do not route cycles.');
        System.assertEquals(data.manager.Id, forSfeOwnCycle, 'An SFE never approves their own cycle.');
    }
}
