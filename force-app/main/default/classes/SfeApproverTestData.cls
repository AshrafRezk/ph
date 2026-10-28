/**
 * Test fixture for SFE approver routing. One business unit has a line, district, and seat with a rep;
 * a second business unit has one seat with another rep. The trainee has no seat. Everyone except the
 * manager reports to the manager.
 */
@IsTest
public class SfeApproverTestData {
    public Territory2 businessUnit;
    public Territory2 line;
    public Territory2 district;
    public Territory2 seat;
    public Territory2 otherBusinessUnit;
    public Territory2 otherSeat;
    public User manager;
    public User lineSfe;
    public User businessUnitSfe;
    public User allLinesSfe;
    public User rep;
    public User otherRep;
    public User trainee;

    /** Null when the org has no active territory model to build on. */
    public static SfeApproverTestData build() {
        List<Territory2Model> models = [SELECT Id FROM Territory2Model WHERE State = 'Active' LIMIT 1];
        List<Territory2Type> types = [SELECT Id FROM Territory2Type LIMIT 1];
        if (models.isEmpty() || types.isEmpty()) {
            return null;
        }
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        String uniq = String.valueOf(Math.abs(Crypto.getRandomInteger()));
        SfeApproverTestData data = new SfeApproverTestData();

        data.manager = newUser('Mona', 'Manager Test', 'mgr', uniq, profileId);
        insert data.manager;
        data.lineSfe = newUser('Lina', 'Line Test', 'lsfe', uniq, profileId);
        data.businessUnitSfe = newUser('Hamsa', 'DiaaElDin Test', 'bsfe', uniq, profileId);
        data.allLinesSfe = newUser('Aya', 'Adel Test', 'asfe', uniq, profileId);
        data.rep = newUser('Rami', 'Rep Test', 'rep', uniq, profileId);
        data.otherRep = newUser('Omar', 'Rep Test', 'orep', uniq, profileId);
        data.trainee = newUser('Tarek', 'Trainee Test', 'trn', uniq, profileId);
        List<User> reports = new List<User>{
            data.lineSfe,
            data.businessUnitSfe,
            data.allLinesSfe,
            data.rep,
            data.otherRep,
            data.trainee
        };
        for (User report : reports) {
            report.ManagerId = data.manager.Id;
        }
        insert reports;

        // AccountStageService reads the stage fields in user mode; this permission set grants them.
        List<PermissionSet> accountFields = [SELECT Id FROM PermissionSet WHERE Name = 'Pharma_Account_Module' LIMIT 1];
        if (!accountFields.isEmpty()) {
            List<PermissionSetAssignment> grants = new List<PermissionSetAssignment>{
                new PermissionSetAssignment(AssigneeId = data.manager.Id, PermissionSetId = accountFields[0].Id)
            };
            for (User report : reports) {
                grants.add(new PermissionSetAssignment(AssigneeId = report.Id, PermissionSetId = accountFields[0].Id));
            }
            insert grants;
        }

        Id modelId = models[0].Id;
        Id typeId = types[0].Id;
        data.businessUnit = newTerritory('SFEA Diabetes ' + uniq, 'SFEA_BU_' + uniq, 'Business_Unit', null, modelId, typeId);
        data.otherBusinessUnit = newTerritory('SFEA CHC ' + uniq, 'SFEA_BU2_' + uniq, 'Business_Unit', null, modelId, typeId);
        insert new List<Territory2>{ data.businessUnit, data.otherBusinessUnit };
        data.line = newTerritory('SFEA Line ' + uniq, 'SFEA_Line_' + uniq, 'Line', data.businessUnit.Id, modelId, typeId);
        data.otherSeat = newTerritory('SFEA Seat2 ' + uniq, 'SFEA_Seat2_' + uniq, 'Position', data.otherBusinessUnit.Id, modelId, typeId);
        insert new List<Territory2>{ data.line, data.otherSeat };
        data.district = newTerritory('SFEA District ' + uniq, 'SFEA_District_' + uniq, 'District', data.line.Id, modelId, typeId);
        insert data.district;
        data.seat = newTerritory('SFEA Seat ' + uniq, 'SFEA_Seat_' + uniq, 'Position', data.district.Id, modelId, typeId);
        insert data.seat;

        insert new List<UserTerritory2Association>{
            new UserTerritory2Association(UserId = data.rep.Id, Territory2Id = data.seat.Id),
            new UserTerritory2Association(UserId = data.otherRep.Id, Territory2Id = data.otherSeat.Id)
        };
        return data;
    }

    /** Line SFE on the line, business unit SFE on the business unit, and an All Lines SFE. */
    public void assignDefaults() {
        assign(new List<SFE_Approver_Assignment__c>{
            row(lineSfe.Id, line.Name, false),
            row(businessUnitSfe.Id, businessUnit.Name, false),
            row(allLinesSfe.Id, null, true)
        });
    }

    /** Both approvals on. */
    public static SFE_Approver_Assignment__c row(Id approverId, String lines, Boolean allLines) {
        return new SFE_Approver_Assignment__c(
            Approver__c = approverId,
            Lines__c = lines,
            All_Lines__c = allLines,
            Approves_Classification__c = true,
            Approves_New_Accounts__c = true,
            Is_Active__c = true
        );
    }

    /** Runs in its own runAs block: custom records after User and Territory2 DML in one context is mixed DML. */
    public static void assign(List<SFE_Approver_Assignment__c> rows) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert rows;
        }
        SfeApproverService.clearCache();
    }

    private static User newUser(String firstName, String lastName, String prefix, String uniq, Id profileId) {
        String username = prefix + '.' + uniq + '@sfe-approver.example.com.invalid';
        return new User(
            Alias = (prefix + uniq).left(8),
            Email = username,
            EmailEncodingKey = 'UTF-8',
            FirstName = firstName,
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = profileId,
            TimeZoneSidKey = 'Africa/Cairo',
            Username = username
        );
    }

    private static Territory2 newTerritory(
        String name,
        String developerName,
        String territoryType,
        Id parentId,
        Id modelId,
        Id typeId
    ) {
        return new Territory2(
            Name = name,
            DeveloperName = developerName,
            Territory2ModelId = modelId,
            Territory2TypeId = typeId,
            ParentTerritory2Id = parentId,
            Territory_Type__c = territoryType,
            External_ID__c = 'TERR_' + developerName.toUpperCase()
        );
    }
}
