/**
 * "Download full organogram (bricks)" on the Territories tab: the layout of the Details sheet in
 * Zeta's Total Organogram workbook, one row per 702-brick per position with the BUM / NSM / ASM / DM /
 * Medical Rep chain. The browser asks for one line per call (about 700 rows, 450 KB), so a full
 * export stays far inside the heap limit.
 * The workbook's numeric Territory ID is added in the browser from the ZetaOrganogramTerritories
 * static resource, since Territory2 has no field for it.
 */
public without sharing class OrganogramBrickExport {
    public class Person {
        @AuraEnabled public String name;
        @AuraEnabled public String employeeNumber;
        @AuraEnabled public Date hireDate;
    }

    public class BrickRow {
        @AuraEnabled public String brick702;
        @AuraEnabled public String brick148;
        @AuraEnabled public String brick70;
        @AuraEnabled public Decimal share;
        @AuraEnabled public String line;
        @AuraEnabled public String positionName;
        @AuraEnabled public String positionExternalId;
        @AuraEnabled public String districtName;
        @AuraEnabled public Person bum;
        @AuraEnabled public Person nsm;
        @AuraEnabled public Person asm;
        @AuraEnabled public Person dm;
        @AuraEnabled public Person rep;
    }

    @AuraEnabled
    public static List<BrickRow> getBrickRows(Id lineId) {
        if (lineId == null) {
            throw new AuraHandledException('Line is required.');
        }
        List<Territory2> lineRows = [
            SELECT Id, Name, ParentTerritory2Id FROM Territory2 WHERE Id = :lineId WITH SYSTEM_MODE LIMIT 1
        ];
        if (lineRows.isEmpty()) {
            throw new AuraHandledException('Line not found.');
        }
        Territory2 line = lineRows[0];
        Map<Id, Territory2> districts = new Map<Id, Territory2>([
            SELECT Id, Name
            FROM Territory2
            WHERE ParentTerritory2Id = :line.Id AND Territory_Type__c = 'District'
            WITH SYSTEM_MODE
        ]);
        List<Territory2> positions = [
            SELECT Id, Name, External_ID__c, ParentTerritory2Id, ParentTerritory2.Name
            FROM Territory2
            WHERE ParentTerritory2Id IN :districts.keySet() AND Territory_Type__c = 'Position'
            WITH SYSTEM_MODE
            ORDER BY ParentTerritory2.Name, Name
        ];

        Set<Id> seatIds = new Set<Id>(districts.keySet());
        seatIds.add(line.Id);
        if (line.ParentTerritory2Id != null) {
            seatIds.add(line.ParentTerritory2Id);
        }
        Set<String> positionKeys = new Set<String>();
        for (Territory2 position : positions) {
            seatIds.add(position.Id);
            positionKeys.add(String.valueOf(position.Id));
        }

        // Holders per seat and title.
        Boolean hasHireDate = User.SObjectType.getDescribe().fields.getMap().containsKey('Hire_Date__c');
        String soql =
            'SELECT Territory2Id, RoleInTerritory2, User.Name, User.EmployeeNumber'
            + (hasHireDate ? ', User.Hire_Date__c' : '')
            + ' FROM UserTerritory2Association WHERE Territory2Id IN :seatIds AND User.IsActive = TRUE'
            + ' WITH SYSTEM_MODE ORDER BY User.Name';
        Map<String, Person> holderByKey = new Map<String, Person>();
        for (UserTerritory2Association link : Database.query(soql)) {
            String key = link.Territory2Id + ':' + (String.isBlank(link.RoleInTerritory2) ? '' : link.RoleInTerritory2.toLowerCase());
            Person person = new Person();
            person.name = link.User.Name;
            person.employeeNumber = link.User.EmployeeNumber;
            person.hireDate = hasHireDate ? (Date) link.User.get('Hire_Date__c') : null;
            holderByKey.put(key, join(holderByKey.get(key), person));
        }

        Map<Id, List<Brick_Territory_Alignment__c>> bricksByPosition = new Map<Id, List<Brick_Territory_Alignment__c>>();
        for (Brick_Territory_Alignment__c alignment : [
            SELECT Territory2_Id__c, Share__c, Brick__r.Name, Brick__r.Parent_Brick__r.Name,
                Brick__r.Parent_Brick__r.Parent_Brick__r.Name
            FROM Brick_Territory_Alignment__c
            WHERE Is_Active__c = TRUE AND Territory2_Id__c IN :positionKeys
            WITH SYSTEM_MODE
            ORDER BY Brick__r.Name
        ]) {
            Id positionId = (Id) alignment.Territory2_Id__c;
            if (!bricksByPosition.containsKey(positionId)) {
                bricksByPosition.put(positionId, new List<Brick_Territory_Alignment__c>());
            }
            bricksByPosition.get(positionId).add(alignment);
        }

        Person bum = holderByKey.get(line.ParentTerritory2Id + ':business unit manager');
        Person nsm = holderByKey.get(line.Id + ':national sales manager');
        List<BrickRow> rows = new List<BrickRow>();
        for (Territory2 position : positions) {
            Id districtId = position.ParentTerritory2Id;
            Person rep = join(holderByKey.get(position.Id + ':medical rep'), holderByKey.get(position.Id + ':'));
            if (rep == null) {
                rep = new Person();
                rep.name = 'VACANT ' + position.Name;
            }
            List<Brick_Territory_Alignment__c> bricks = bricksByPosition.containsKey(position.Id)
                ? bricksByPosition.get(position.Id)
                : new List<Brick_Territory_Alignment__c>{ null };
            for (Brick_Territory_Alignment__c alignment : bricks) {
                BrickRow row = new BrickRow();
                row.line = line.Name;
                row.positionName = position.Name;
                row.positionExternalId = position.External_ID__c;
                row.districtName = position.ParentTerritory2?.Name;
                row.bum = bum;
                row.nsm = nsm;
                row.asm = holderByKey.get(districtId + ':area manager');
                row.dm = holderByKey.get(districtId + ':district manager');
                row.rep = rep;
                if (alignment != null) {
                    row.brick702 = alignment.Brick__r?.Name;
                    row.brick148 = alignment.Brick__r?.Parent_Brick__r?.Name;
                    row.brick70 = alignment.Brick__r?.Parent_Brick__r?.Parent_Brick__r?.Name;
                    row.share = alignment.Share__c;
                }
                rows.add(row);
            }
        }
        return rows;
    }

    /** Two people in the same seat and title show as "A / B", like the workbook does for shared seats. */
    private static Person join(Person current, Person extra) {
        if (current == null) {
            return extra;
        }
        if (extra == null) {
            return current;
        }
        Person both = new Person();
        both.name = current.name + ' / ' + extra.name;
        both.employeeNumber = String.isBlank(current.employeeNumber) ? extra.employeeNumber
            : String.isBlank(extra.employeeNumber) ? current.employeeNumber
            : current.employeeNumber + ' / ' + extra.employeeNumber;
        both.hireDate = current.hireDate != null ? current.hireDate : extra.hireDate;
        return both;
    }
}
