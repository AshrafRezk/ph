@IsTest
private class OrganogramBrickExportTest {
    @TestSetup
    static void setup() {
        Territory2Model model = [SELECT Id FROM Territory2Model WHERE DeveloperName = 'Current_FY' LIMIT 1];
        Territory2Type type = [SELECT Id FROM Territory2Type LIMIT 1];
        Territory2 bu = new Territory2(Name = 'BX Unit', DeveloperName = 'BX_Unit', External_ID__c = 'TERR_BU_BXTEST',
            Territory_Type__c = 'Business_Unit', Territory2ModelId = model.Id, Territory2TypeId = type.Id);
        insert bu;
        Territory2 line = new Territory2(Name = 'BX Line', DeveloperName = 'BX_Line', External_ID__c = 'TERR_LINE_BXTEST',
            Territory_Type__c = 'Line', ParentTerritory2Id = bu.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id);
        insert line;
        Territory2 district = new Territory2(Name = 'DM BX', DeveloperName = 'DM_BX', External_ID__c = 'TERR_DM_BXTEST',
            Territory_Type__c = 'District', ParentTerritory2Id = line.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id);
        insert district;
        insert new List<Territory2>{
            new Territory2(Name = 'BX POS A', DeveloperName = 'POS_BX_A', External_ID__c = 'TERR_POS_BX_A', Territory_Type__c = 'Position',
                ParentTerritory2Id = district.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id),
            new Territory2(Name = 'BX POS B', DeveloperName = 'POS_BX_B', External_ID__c = 'TERR_POS_BX_B', Territory_Type__c = 'Position',
                ParentTerritory2Id = district.Id, Territory2ModelId = model.Id, Territory2TypeId = type.Id)
        };

        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        Map<String, User> people = new Map<String, User>();
        for (String alias : new List<String>{ 'bxbum', 'bxnsm', 'bxdm', 'bxasm', 'bxrep' }) {
            people.put(alias, new User(
                Alias = alias, LastName = 'Brick ' + alias, Email = alias + '@brickexport.test',
                Username = alias + '.' + String.valueOf(Crypto.getRandomInteger()).replace('-', '') + '@brickexport.test',
                EmployeeNumber = 'BX-' + alias, ProfileId = standard.Id, EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'Africa/Cairo'
            ));
        }
        insert people.values();
        Id posA = [SELECT Id FROM Territory2 WHERE External_ID__c = 'TERR_POS_BX_A'].Id;
        insert new List<UserTerritory2Association>{
            new UserTerritory2Association(UserId = people.get('bxbum').Id, Territory2Id = bu.Id, RoleInTerritory2 = 'Business Unit Manager'),
            new UserTerritory2Association(UserId = people.get('bxnsm').Id, Territory2Id = line.Id, RoleInTerritory2 = 'National Sales Manager'),
            new UserTerritory2Association(UserId = people.get('bxdm').Id, Territory2Id = district.Id, RoleInTerritory2 = 'District Manager'),
            new UserTerritory2Association(UserId = people.get('bxasm').Id, Territory2Id = district.Id, RoleInTerritory2 = 'Area Manager'),
            new UserTerritory2Association(UserId = people.get('bxrep').Id, Territory2Id = posA, RoleInTerritory2 = 'Medical Rep')
        };
    }

    static void insertBricks(Id positionId) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Brick__c b70 = new Brick__c(Name = 'BX 70', External_ID__c = 'BX_70', Is_Active__c = true);
            insert b70;
            Brick__c b148 = new Brick__c(Name = 'BX 148', External_ID__c = 'BX_148', Is_Active__c = true, Parent_Brick__c = b70.Id);
            insert b148;
            Brick__c b702 = new Brick__c(Name = 'BX 702', External_ID__c = 'BX_702', Is_Active__c = true, Parent_Brick__c = b148.Id);
            insert b702;
            insert new Brick_Territory_Alignment__c(
                Brick__c = b702.Id, External_ID__c = 'BX_702|TERR_POS_BX_A', Territory_External_ID__c = 'TERR_POS_BX_A',
                Territory2_Id__c = String.valueOf(positionId), Share__c = 0.5, Is_Active__c = true
            );
        }
    }

    @IsTest
    static void exportsOneRowPerBrickWithTheManagerChain() {
        Id posA = [SELECT Id FROM Territory2 WHERE External_ID__c = 'TERR_POS_BX_A'].Id;
        insertBricks(posA);
        Id lineId = [SELECT Id FROM Territory2 WHERE External_ID__c = 'TERR_LINE_BXTEST'].Id;

        Test.startTest();
        List<OrganogramBrickExport.BrickRow> rows = OrganogramBrickExport.getBrickRows(lineId);
        Test.stopTest();

        System.assertEquals(2, rows.size(), JSON.serialize(rows));
        OrganogramBrickExport.BrickRow a = rows[0];
        System.assertEquals('BX POS A', a.positionName);
        System.assertEquals('BX 702', a.brick702);
        System.assertEquals('BX 148', a.brick148);
        System.assertEquals('BX 70', a.brick70);
        System.assertEquals(0.5, a.share);
        System.assertEquals('BX Line', a.line);
        System.assertEquals('DM BX', a.districtName);
        System.assertEquals('Brick bxbum', a.bum.name);
        System.assertEquals('Brick bxnsm', a.nsm.name);
        System.assertEquals('Brick bxasm', a.asm.name);
        System.assertEquals('BX-bxdm', a.dm.employeeNumber);
        System.assertEquals('Brick bxrep', a.rep.name);
        OrganogramBrickExport.BrickRow b = rows[1];
        System.assertEquals('VACANT BX POS B', b.rep.name, 'A position without bricks or a rep still shows.');
        System.assertEquals(null, b.brick702);
    }

    @IsTest
    static void guardsMissingLine() {
        try {
            OrganogramBrickExport.getBrickRows(null);
            System.assert(false, 'Expected an error');
        } catch (AuraHandledException ex) {
            System.assert(true);
        }
        Id missing = [SELECT Id FROM Territory2 WHERE External_ID__c = 'TERR_POS_BX_B'].Id;
        System.assertEquals(0, OrganogramBrickExport.getBrickRows(missing).size(), 'A position has no districts below it.');
    }
}
