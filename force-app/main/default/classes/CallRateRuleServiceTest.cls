@IsTest
private class CallRateRuleServiceTest {
    @IsTest
    static void orgRule_isUsedWhenNothingMoreSpecificExists() {
        CallRateRuleService.saveRule('Org', null, 12, 4, 8, true);
        Integer dmlBefore = Limits.getDmlStatements();
        CallRateRuleService.Resolution resolved = CallRateRuleService.resolveForTerritory(null);
        System.assertEquals(dmlBefore, Limits.getDmlStatements(), 'Resolver must not run DML');
        System.assertEquals(12, resolved.call);
        System.assertEquals(4, resolved.am);
        System.assertEquals(8, resolved.pm);
        System.assertEquals('Org', resolved.callSource);
    }

    @IsTest
    static void inactiveRule_isIgnored() {
        CallRateRuleService.saveRule('Org', null, 12, null, null, false);
        CallRateRuleService.Resolution resolved = CallRateRuleService.resolveForTerritory(null);
        System.assertEquals(null, resolved.call);
        System.assertEquals(15, CallRateRuleService.dailyCallRateOrDefault(15));
        System.assertEquals(
            CallRateRuleService.FRAMEWORK_DAILY_CALL_RATE,
            CallRateRuleService.dailyCallRateOrDefault(null)
        );
    }

    @IsTest
    static void saveRule_validatesInput() {
        try {
            CallRateRuleService.saveRule('Line', '', 10, null, null, true);
            System.assert(false, 'A line rule needs a key');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
        try {
            CallRateRuleService.saveRule('Org', null, -1, null, null, true);
            System.assert(false, 'Negative rates are rejected');
        } catch (AuraHandledException expected) {
            System.assert(true);
        }
    }

    @IsTest
    static void lineRule_beatsOrgRule_andTerritoryBeatsBoth() {
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        List<Territory2Model> models = [SELECT Id FROM Territory2Model LIMIT 1];
        if (types.isEmpty() || models.isEmpty()) {
            return;
        }
        Territory2 line = new Territory2(
            Name = 'CRR Test Line',
            DeveloperName = 'CRR_Test_Line',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            External_ID__c = 'TERR_LINE_CRRTEST',
            Territory_Type__c = 'Line'
        );
        insert line;
        Territory2 position = new Territory2(
            Name = 'CRR Test Position',
            DeveloperName = 'CRR_Test_Position',
            Territory2ModelId = models[0].Id,
            Territory2TypeId = types[0].Id,
            ParentTerritory2Id = line.Id,
            External_ID__c = 'TERR_POS_CRRTEST',
            Territory_Type__c = 'Position'
        );
        insert position;

        CallRateRuleService.saveRule('Org', null, 10, null, null, true);
        CallRateRuleService.saveRule('Line', 'CRR Test Line', 14, 3, null, true);

        CallRateRuleService.Resolution viaLine = CallRateRuleService.resolveForTerritory(position.Id);
        System.assertEquals(14, viaLine.call, 'Line rule beats Org');
        System.assertEquals('Line', viaLine.callSource);
        System.assertEquals(3, viaLine.am);

        position.put('Daily_Visit_Rate__c', 9);
        update position;
        CallRateRuleService.Resolution own = CallRateRuleService.resolveForTerritory(position.Id);
        System.assertEquals(9, own.call, 'Territory call rate beats Line and Org');
        System.assertEquals('Territory', own.callSource);
        System.assertEquals(3, own.am, 'Other components still resolve independently');
        System.assertEquals(2, CallRateRuleService.listRules().size(), 'Org + Line rules only');
    }
}
