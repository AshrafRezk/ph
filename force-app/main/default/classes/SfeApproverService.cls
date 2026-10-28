/**
 * SFE approvers by business unit or line (SFE_Approver_Assignment__c, Admin Console > SFE Approvers).
 * The same rows decide who approves Class Engine cycles and who approves new accounts at Pending SFE.
 * A business unit or line covers every district and seat under it. All Lines covers everyone,
 * including users without a seat.
 */
public without sharing class SfeApproverService {
    public static final String CLASSIFICATION = 'classification';
    public static final String NEW_ACCOUNTS = 'newAccounts';

    private static final Set<String> SCOPE_TYPES = new Set<String>{ 'Business_Unit', 'Line' };
    private static final Integer ALL_LINES_RANK = 1000;

    private class Assignment {
        Id approverId;
        String approverName;
        Boolean allLines = false;
        Boolean classification = false;
        Boolean newAccounts = false;
        Set<Id> anchorIds = new Set<Id>();
    }

    private class RankedApprover implements Comparable {
        Id approverId;
        String approverName;
        Integer rank;

        public Integer compareTo(Object other) {
            RankedApprover that = (RankedApprover) other;
            if (rank != that.rank) {
                return rank < that.rank ? -1 : 1;
            }
            String left = approverName == null ? '' : approverName.toLowerCase();
            String right = that.approverName == null ? '' : that.approverName.toLowerCase();
            return left.compareTo(right);
        }
    }

    private static List<Assignment> cachedAssignments;
    private static Map<Id, List<Id>> cachedChains = new Map<Id, List<Id>>();
    private static Map<Id, Set<Id>> cachedSeatIds = new Map<Id, Set<Id>>();
    private static Map<Id, String> cachedNames = new Map<Id, String>();
    private static Boolean cachedIsAdmin;
    private static Id cachedAdminUserId;
    @TestVisible
    private static Boolean testIsSystemAdministrator;

    public static void clearCache() {
        cachedAssignments = null;
        cachedChains = new Map<Id, List<Id>>();
        cachedSeatIds = new Map<Id, Set<Id>>();
        cachedNames = new Map<Id, String>();
    }

    public static Boolean isApprover(Id userId, String purpose) {
        return !assignmentsOf(userId, purpose).isEmpty();
    }

    public static Boolean coversAllLines(Id userId, String purpose) {
        for (Assignment row : assignmentsOf(userId, purpose)) {
            if (row.allLines) {
                return true;
            }
        }
        return false;
    }

    /** Approvers whose lines cover the territory: line approvers first, then business unit, then All Lines. */
    public static List<Id> approversForTerritory(Id territoryId, String purpose) {
        List<List<Id>> chains = new List<List<Id>>();
        if (territoryId != null) {
            chains.add(chainsFor(new Set<Id>{ territoryId }).get(territoryId));
        }
        return rank(chains, purpose);
    }

    /** Approvers covering any of the user's active seats. The user never approves their own work. */
    public static List<Id> approversForUser(Id userId, String purpose) {
        List<List<Id>> chains = new List<List<Id>>();
        if (userId != null) {
            Set<Id> seatIds = seatIdsOf(userId);
            Map<Id, List<Id>> bySeat = chainsFor(seatIds);
            for (Id seatId : seatIds) {
                chains.add(bySeat.get(seatId));
            }
        }
        List<Id> approvers = rank(chains, purpose);
        Integer self = approvers.indexOf(userId);
        if (self >= 0) {
            approvers.remove(self);
        }
        return approvers;
    }

    public static Boolean coversTerritory(Id approverId, Id territoryId, String purpose) {
        return approverId != null
            && isApprover(approverId, purpose)
            && approversForTerritory(territoryId, purpose).contains(approverId);
    }

    public static Boolean coversUser(Id approverId, Id userId, String purpose) {
        return approverId != null
            && approverId != userId
            && isApprover(approverId, purpose)
            && approversForUser(userId, purpose).contains(approverId);
    }

    /** Every territory under the approver's business units and lines. All Lines rows add nothing here. */
    public static Set<Id> territoryIdsFor(Id approverId, String purpose) {
        Set<Id> anchors = new Set<Id>();
        for (Assignment row : assignmentsOf(approverId, purpose)) {
            if (!row.allLines) {
                anchors.addAll(row.anchorIds);
            }
        }
        return anchors.isEmpty() ? new Set<Id>() : TerritoryHierarchyService.expandTerritoryHierarchy(anchors);
    }

    /** Users with an active seat under the approver's business units and lines, without the approver. */
    public static Set<Id> seatedUserIdsFor(Id approverId, String purpose) {
        Set<Id> userIds = new Set<Id>();
        Set<Id> territoryIds = territoryIdsFor(approverId, purpose);
        if (territoryIds.isEmpty()) {
            return userIds;
        }
        for (UserTerritory2Association seat : [
            SELECT UserId
            FROM UserTerritory2Association
            WHERE Territory2Id IN :territoryIds AND IsActive = TRUE
            WITH SYSTEM_MODE
        ]) {
            userIds.add(seat.UserId);
        }
        userIds.remove(approverId);
        return userIds;
    }

    /** "Hamsa DiaaElDin, Aya Adel" for a waiting-on line. */
    public static String namesOf(List<Id> approverIds) {
        loadAssignments();
        List<String> names = new List<String>();
        for (Id approverId : approverIds == null ? new List<Id>() : approverIds) {
            String name = cachedNames.get(approverId);
            if (String.isNotBlank(name)) {
                names.add(name);
            }
        }
        return String.join(names, ', ');
    }

    public static Boolean isSystemAdministrator() {
        if (Test.isRunningTest() && testIsSystemAdministrator != null) {
            return testIsSystemAdministrator;
        }
        if (cachedIsAdmin == null || cachedAdminUserId != UserInfo.getUserId()) {
            cachedAdminUserId = UserInfo.getUserId();
            cachedIsAdmin = [
                SELECT COUNT()
                FROM Profile
                WHERE Id = :UserInfo.getProfileId() AND Name = 'System Administrator'
                WITH SYSTEM_MODE
            ] > 0;
        }
        return cachedIsAdmin;
    }

    public static List<String> splitLines(String raw) {
        List<String> lines = new List<String>();
        if (String.isBlank(raw)) {
            return lines;
        }
        Set<String> seen = new Set<String>();
        for (String part : raw.split('[;,\\n]')) {
            String name = part == null ? '' : part.trim();
            if (String.isNotBlank(name) && seen.add(name.toLowerCase())) {
                lines.add(name);
            }
        }
        return lines;
    }

    private static List<Id> rank(List<List<Id>> chains, String purpose) {
        Map<Id, RankedApprover> best = new Map<Id, RankedApprover>();
        for (Assignment row : forPurpose(purpose)) {
            Integer rowRank = row.allLines ? ALL_LINES_RANK : closestMatch(chains, row.anchorIds);
            if (rowRank == null) {
                continue;
            }
            RankedApprover current = best.get(row.approverId);
            if (current == null) {
                current = new RankedApprover();
                current.approverId = row.approverId;
                current.approverName = row.approverName;
                current.rank = rowRank;
                best.put(row.approverId, current);
            } else if (rowRank < current.rank) {
                current.rank = rowRank;
            }
        }
        List<RankedApprover> ordered = best.values();
        ordered.sort();
        List<Id> approverIds = new List<Id>();
        for (RankedApprover approver : ordered) {
            approverIds.add(approver.approverId);
        }
        return approverIds;
    }

    /** Distance from the seat to the nearest covered ancestor, so a line beats its business unit. */
    private static Integer closestMatch(List<List<Id>> chains, Set<Id> anchorIds) {
        Integer closest;
        for (List<Id> chain : chains) {
            if (chain == null) {
                continue;
            }
            for (Integer depth = 0; depth < chain.size(); depth++) {
                if (anchorIds.contains(chain[depth])) {
                    if (closest == null || depth < closest) {
                        closest = depth;
                    }
                    break;
                }
            }
        }
        return closest;
    }

    private static List<Assignment> assignmentsOf(Id userId, String purpose) {
        List<Assignment> rows = new List<Assignment>();
        if (userId == null) {
            return rows;
        }
        for (Assignment row : forPurpose(purpose)) {
            if (row.approverId == userId) {
                rows.add(row);
            }
        }
        return rows;
    }

    private static List<Assignment> forPurpose(String purpose) {
        List<Assignment> rows = new List<Assignment>();
        for (Assignment row : loadAssignments()) {
            if (
                (CLASSIFICATION.equals(purpose) && row.classification) ||
                (NEW_ACCOUNTS.equals(purpose) && row.newAccounts)
            ) {
                rows.add(row);
            }
        }
        return rows;
    }

    private static List<Assignment> loadAssignments() {
        if (cachedAssignments != null) {
            return cachedAssignments;
        }
        List<SFE_Approver_Assignment__c> records = [
            SELECT
                Approver__c,
                Approver__r.Name,
                Approver__r.FirstName,
                Approver__r.LastName,
                All_Lines__c,
                Lines__c,
                Approves_Classification__c,
                Approves_New_Accounts__c
            FROM SFE_Approver_Assignment__c
            WHERE Is_Active__c = TRUE AND Approver__c != NULL AND Approver__r.IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Approver__r.Name ASC
            LIMIT 500
        ];
        Map<String, Set<Id>> anchorsByName = needsAnchors(records) ? scopeAnchorsByName() : new Map<String, Set<Id>>();
        cachedAssignments = new List<Assignment>();
        for (SFE_Approver_Assignment__c record : records) {
            Assignment row = new Assignment();
            row.approverId = record.Approver__c;
            row.approverName = shortName(record.Approver__r);
            row.allLines = record.All_Lines__c == true;
            row.classification = record.Approves_Classification__c == true;
            row.newAccounts = record.Approves_New_Accounts__c == true;
            for (String line : splitLines(record.Lines__c)) {
                Set<Id> anchors = anchorsByName.get(line.toLowerCase());
                if (anchors != null) {
                    row.anchorIds.addAll(anchors);
                }
            }
            if (row.allLines || !row.anchorIds.isEmpty()) {
                cachedAssignments.add(row);
                cachedNames.put(row.approverId, row.approverName);
            }
        }
        return cachedAssignments;
    }

    private static Boolean needsAnchors(List<SFE_Approver_Assignment__c> records) {
        for (SFE_Approver_Assignment__c record : records) {
            if (record.All_Lines__c != true && String.isNotBlank(record.Lines__c)) {
                return true;
            }
        }
        return false;
    }

    private static Map<String, Set<Id>> scopeAnchorsByName() {
        Map<String, Set<Id>> byName = new Map<String, Set<Id>>();
        for (Territory2 territory : [
            SELECT Id, Name
            FROM Territory2
            WHERE Territory_Type__c IN :SCOPE_TYPES AND Territory2Model.State = 'Active'
            WITH SYSTEM_MODE
        ]) {
            String key = territory.Name == null ? '' : territory.Name.trim().toLowerCase();
            if (!byName.containsKey(key)) {
                byName.put(key, new Set<Id>());
            }
            byName.get(key).add(territory.Id);
        }
        return byName;
    }

    /** Seat first, then each parent up to five levels (seat, district, line, business unit, head office). */
    private static Map<Id, List<Id>> chainsFor(Set<Id> territoryIds) {
        Set<Id> missing = new Set<Id>();
        for (Id territoryId : territoryIds) {
            if (territoryId != null && !cachedChains.containsKey(territoryId)) {
                missing.add(territoryId);
            }
        }
        if (!missing.isEmpty()) {
            for (Territory2 territory : [
                SELECT
                    Id,
                    ParentTerritory2Id,
                    ParentTerritory2.ParentTerritory2Id,
                    ParentTerritory2.ParentTerritory2.ParentTerritory2Id,
                    ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id,
                    ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2.ParentTerritory2Id
                FROM Territory2
                WHERE Id IN :missing
                WITH SYSTEM_MODE
            ]) {
                List<Id> chain = new List<Id>{ territory.Id };
                SObject node = territory;
                for (Integer depth = 0; depth < 5 && node != null; depth++) {
                    Id parentId = (Id) node.get('ParentTerritory2Id');
                    if (parentId == null) {
                        break;
                    }
                    chain.add(parentId);
                    node = depth < 4 ? node.getSObject('ParentTerritory2') : null;
                }
                cachedChains.put(territory.Id, chain);
            }
        }
        Map<Id, List<Id>> chains = new Map<Id, List<Id>>();
        for (Id territoryId : territoryIds) {
            if (cachedChains.containsKey(territoryId)) {
                chains.put(territoryId, cachedChains.get(territoryId));
            }
        }
        return chains;
    }

    private static Set<Id> seatIdsOf(Id userId) {
        if (!cachedSeatIds.containsKey(userId)) {
            Set<Id> seatIds = new Set<Id>();
            for (UserTerritory2Association seat : [
                SELECT Territory2Id
                FROM UserTerritory2Association
                WHERE UserId = :userId AND IsActive = TRUE
                WITH SYSTEM_MODE
            ]) {
                seatIds.add(seat.Territory2Id);
            }
            cachedSeatIds.put(userId, seatIds);
        }
        return cachedSeatIds.get(userId);
    }

    private static String shortName(User approver) {
        if (approver == null) {
            return null;
        }
        String last = approver.LastName == null ? '' : approver.LastName.trim().split('\\s+')[0];
        String full = ((approver.FirstName == null ? '' : approver.FirstName.trim()) + ' ' + last).trim();
        return String.isBlank(full) ? approver.Name : full;
    }
}
