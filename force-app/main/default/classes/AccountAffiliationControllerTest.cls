@IsTest
private class AccountAffiliationControllerTest {

    @TestSetup
    static void setupData() {
        Id hcpRtId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
              AND IsPersonType = TRUE
              AND IsActive = TRUE
            LIMIT 1
        ].Id;
        Id hcoRtId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
              AND DeveloperName = 'Institution_HCO'
              AND IsActive = TRUE
            LIMIT 1
        ].Id;

        Account primary = new Account(
            RecordTypeId = hcpRtId,
            FirstName = 'Root',
            LastName = 'HCP'
        );
        Account related1 = new Account(RecordTypeId = hcoRtId, Name = 'Practice A');
        Account related2 = new Account(RecordTypeId = hcoRtId, Name = 'Pharmacy B');
        insert as system new List<Account>{ primary, related1, related2 };

        Account_Affiliation__c activeAff = new Account_Affiliation__c(
            Primary_Account__c = primary.Id,
            Related_Account__c = related1.Id,
            Affiliation_Type__c = 'Practice',
            Role__c = 'Physician',
            Is_Active__c = true
        );
        Account_Affiliation__c inactiveAff = new Account_Affiliation__c(
            Primary_Account__c = primary.Id,
            Related_Account__c = related2.Id,
            Affiliation_Type__c = 'Partner',
            Role__c = 'Pharmacist',
            Is_Active__c = false
        );
        if (Schema.sObjectType.Account_Affiliation__c.fields.getMap().containsKey('Strength__c')
            && Schema.sObjectType.Account_Affiliation__c.fields.getMap().get('Strength__c').getDescribe().isCreateable()) {
            activeAff.put('Strength__c', 'Strong');
            inactiveAff.put('Strength__c', 'Medium');
        }
        if (Schema.sObjectType.Account_Affiliation__c.fields.getMap().containsKey('Outside_Territory__c')
            && Schema.sObjectType.Account_Affiliation__c.fields.getMap().get('Outside_Territory__c').getDescribe().isCreateable()) {
            activeAff.put('Outside_Territory__c', false);
            inactiveAff.put('Outside_Territory__c', true);
        }
        if (Schema.sObjectType.Account_Affiliation__c.fields.getMap().containsKey('Description__c')
            && Schema.sObjectType.Account_Affiliation__c.fields.getMap().get('Description__c').getDescribe().isCreateable()) {
            inactiveAff.put('Description__c', 'Inactive pharmacy link');
        }
        insert as system new List<Account_Affiliation__c>{ activeAff, inactiveAff };
    }

    @IsTest
    static void getAccountAffiliations_returnsActiveAffiliationsByDefault() {
        Account primary = [SELECT Id FROM Account WHERE LastName = 'HCP' LIMIT 1];

        Test.startTest();
        AccountAffiliationController.GraphData graph =
            AccountAffiliationController.getAccountAffiliations(
                primary.Id,
                JSON.serialize(new Map<String, Object>{
                    'relationType' => 'All',
                    'showInactive' => false,
                    'showOutsideTerritory' => true,
                    'direction' => 'All',
                    'role' => 'All',
                    'strength' => 'All',
                    'accountIds' => new List<String>{ String.valueOf(primary.Id) }
                }),
                0,
                25
            );
        Test.stopTest();

        System.assertEquals(2, graph.nodes.size(), 'Expected root and one active related account');
        System.assertEquals(1, graph.edges.size(), 'Inactive affiliation should be excluded');
    }

    @IsTest
    static void getAccountAffiliations_respectsTypeAndRoleFilters() {
        Account primary = [SELECT Id FROM Account WHERE LastName = 'HCP' LIMIT 1];

        AccountAffiliationController.GraphData graph =
            AccountAffiliationController.getAccountAffiliations(
                primary.Id,
                JSON.serialize(new Map<String, Object>{
                    'relationType' => 'Partner',
                    'showInactive' => true,
                    'showOutsideTerritory' => true,
                    'direction' => 'All',
                    'role' => 'Pharmacist',
                    'strength' => 'All',
                    'accountIds' => new List<String>{ String.valueOf(primary.Id) }
                }),
                0,
                25
            );

        System.assertEquals(1, graph.edges.size());
        System.assertEquals('Partner', graph.edges[0].relationType);
    }

    @IsTest
    static void getAccountDetails_returnsAccountHeader() {
        Account primary = [
            SELECT Id, Name, RecordType.Name
            FROM Account
            WHERE LastName = 'HCP'
            LIMIT 1
        ];

        AccountAffiliationController.AccountDetails details =
            AccountAffiliationController.getAccountDetails(primary.Id);

        System.assertEquals(primary.Id, details.id);
        System.assertEquals(primary.Name, details.name);
        System.assertEquals(primary.RecordType.Name, details.accountType);
    }

    @IsTest
    static void getPicklistValues_returnOptions() {
        List<AccountAffiliationController.PicklistValue> types =
            AccountAffiliationController.getRelationTypePicklistValues();
        List<AccountAffiliationController.PicklistValue> roles =
            AccountAffiliationController.getRolePicklistValues();
        AccountAffiliationController.getStrengthPicklistValues();

        System.assert(!types.isEmpty(), 'Affiliation type picklist should have values');
        System.assert(!roles.isEmpty(), 'Role picklist should have values');
    }

    @IsTest
    static void getAccountAffiliations_expandsChildAccounts() {
        Account primary = [SELECT Id FROM Account WHERE LastName = 'HCP' LIMIT 1];
        Account practice = [SELECT Id FROM Account WHERE Name = 'Practice A' LIMIT 1];

        Id hcoRtId = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
              AND DeveloperName = 'Institution_HCO'
              AND IsActive = TRUE
            LIMIT 1
        ].Id;
        Account child = new Account(RecordTypeId = hcoRtId, Name = 'Child Clinic');
        insert as system child;

        insert as system new Account_Affiliation__c(
            Primary_Account__c = practice.Id,
            Related_Account__c = child.Id,
            Affiliation_Type__c = 'Affiliate',
            Is_Active__c = true
        );

        AccountAffiliationController.GraphData graph =
            AccountAffiliationController.getAccountAffiliations(
                primary.Id,
                JSON.serialize(new Map<String, Object>{
                    'relationType' => 'All',
                    'showInactive' => false,
                    'showOutsideTerritory' => true,
                    'direction' => 'All',
                    'role' => 'All',
                    'strength' => 'All',
                    'accountIds' => new List<String>{
                        String.valueOf(primary.Id),
                        String.valueOf(practice.Id)
                    }
                }),
                0,
                25
            );

        System.assert(graph.nodes.size() >= 3, 'Expected expanded child node');
        System.assert(graph.edges.size() >= 2, 'Expected edge from expanded practice');
    }
}