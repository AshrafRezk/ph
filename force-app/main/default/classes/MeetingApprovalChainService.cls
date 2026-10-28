/**
 * Department-and-amount approval chain for meetings (BRD 5.4.5).
 * Steps come from Meeting_Approval_Rule__mdt and are rebuilt for every approval round.
 * Runs without sharing because approvers and the chain walk need users and meetings
 * the requester cannot see; every public entry point checks the caller first.
 */
public without sharing class MeetingApprovalChainService {
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_PENDING = 'PendingApproval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_CONCLUDED = 'Concluded';

    public static final String APPROVAL_NOT_SUBMITTED = 'Not Submitted';
    public static final String APPROVAL_IN_APPROVAL = 'In Approval';
    public static final String APPROVAL_FULLY_APPROVED = 'Fully Approved';
    public static final String APPROVAL_REJECTED = 'Rejected';

    public static final String PAYMENT_ACTUAL_ENTERED = 'Actual Cost Entered';
    public static final String PAYMENT_IN_ACCOUNTING = 'In Accounting';
    public static final String PAYMENT_RETURNED = 'Returned to Business';

    public static final String STEP_WAITING = 'Waiting';
    public static final String STEP_PENDING = 'Pending';
    public static final String STEP_APPROVED = 'Approved';
    public static final String STEP_REJECTED = 'Rejected';
    public static final String STEP_SKIPPED = 'Skipped';

    private static final Integer MAX_CHAIN_DEPTH = 12;

    public class ChainException extends Exception {}

    @TestVisible
    private static List<Meeting_Approval_Rule__mdt> rulesOverride;
    @TestVisible
    private static List<Meeting_Approval_Level__c> levelsOverride;

    public static Meeting__c loadMeeting(Id meetingId) {
        if (meetingId == null) {
            throw new ChainException('Meeting Id is required.');
        }
        List<Meeting__c> rows = [
            SELECT Id, Name, OwnerId, Owner.Name, Status__c, Approval_Status__c, Payment_Status__c,
                Originating_Department__c, Activity_Type__c, Current_Approver__c, Current_Approver__r.Name,
                Planned_Cost__c, Approved_Planned_Cost__c, Deposit_Amount__c, Actual_Cost__c,
                Paid_Amount__c, Remaining_Amount__c, Approval_Round__c, Accounting_Notes__c,
                Objectives__c, Agenda__c, Venue__c, Brand__c, Brand__r.Name, Start_Date_Time__c,
                End_Date_Time__c, Was_Approved__c, Comments__c, Estimated_Participants__c,
                RecordType.DeveloperName, RecordType.Name, CreatedDate, LastModifiedDate
            FROM Meeting__c
            WHERE Id = :meetingId
            LIMIT 1
        ];
        if (rows.isEmpty()) {
            throw new ChainException('Meeting not found.');
        }
        return rows[0];
    }

    public static Boolean isLifecycleMeeting(Meeting__c meeting) {
        return meeting != null && String.isNotBlank(meeting.Originating_Department__c);
    }

    public static Boolean isSuperUser() {
        return FeatureManagement.checkPermission('Meeting_Super_User');
    }

    // ---------------------------------------------------------------- submit

    public static void submit(Id meetingId) {
        Meeting__c meeting = loadMeeting(meetingId);
        if (meeting.OwnerId != UserInfo.getUserId() && !isSuperUser()) {
            throw new ChainException('Only the meeting owner can submit it for approval.');
        }
        if (!isLifecycleMeeting(meeting)) {
            throw new ChainException('Choose the originating department before submitting.');
        }
        if (meeting.Status__c != STATUS_DRAFT) {
            throw new ChainException('Only draft meetings can be submitted.');
        }
        if (String.isBlank(meeting.Activity_Type__c)) {
            throw new ChainException('Choose the activity type before submitting.');
        }
        if (meeting.Start_Date_Time__c == null || meeting.End_Date_Time__c == null) {
            throw new ChainException('Set the meeting start and end time before submitting.');
        }
        String typeMessage = MeetingTypeService.submitProblem(meeting);
        if (String.isBlank(typeMessage) && MeetingTypeService.forMeeting(meeting).requireTargetHcps) {
            typeMessage = MeetingHcpAttendeeService.validateSubmit(meetingId);
        }
        if (String.isNotBlank(typeMessage)) {
            throw new ChainException(typeMessage);
        }
        Decimal amount = meeting.Planned_Cost__c == null ? 0 : meeting.Planned_Cost__c;
        String fromStatus = meeting.Status__c;
        startRound(meeting, amount);
        meeting.Status__c = STATUS_PENDING;
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromStatus, STATUS_PENDING, 'submit',
            'Submitted for ' + meeting.Originating_Department__c + ' approval (' + formatAmount(amount) + ')');
    }

    /** Starts a new approval round for the amount. Caller updates the meeting. */
    public static void startRound(Meeting__c meeting, Decimal amount) {
        skipOpenSteps(meeting.Id, 'Superseded by a new approval round');
        Integer round = meeting.Approval_Round__c == null ? 1 : meeting.Approval_Round__c.intValue() + 1;
        List<Meeting_Approval_Step__c> steps = buildSteps(meeting, amount, round);
        insert steps;

        Meeting_Approval_Step__c first;
        for (Meeting_Approval_Step__c step : steps) {
            if (step.Status__c == STEP_WAITING) {
                first = step;
                break;
            }
        }
        first.Status__c = STEP_PENDING;
        update first;

        Set<Id> approverIds = new Set<Id>();
        for (Meeting_Approval_Step__c step : steps) {
            if (step.Approver__c != null) {
                approverIds.add(step.Approver__c);
            }
        }
        shareWithUsers(meeting.Id, meeting.OwnerId, approverIds);

        meeting.Approval_Round__c = round;
        meeting.Approval_Status__c = APPROVAL_IN_APPROVAL;
        meeting.Current_Approver__c = first.Approver__c;
    }

    // ---------------------------------------------------------------- decide

    public static void approve(Id meetingId, String comments) {
        Meeting__c meeting = loadMeeting(meetingId);
        Meeting_Approval_Step__c step = requireActionableStep(meeting);
        step.Status__c = STEP_APPROVED;
        step.Decided_At__c = System.now();
        step.Comments__c = trimTo(comments, 4000);
        update step;

        Meeting_Approval_Step__c next = nextWaitingStep(meeting);
        String fromStatus = meeting.Status__c;
        if (next != null) {
            next.Status__c = STEP_PENDING;
            update next;
            meeting.Current_Approver__c = next.Approver__c;
            update meeting;
            MeetingHistoryService.writeTransition(meetingId, fromStatus, meeting.Status__c, 'approve-step',
                step.Approver_Role__c + ' approved' + suffix(comments));
            return;
        }

        meeting.Current_Approver__c = null;
        meeting.Approval_Status__c = APPROVAL_FULLY_APPROVED;
        if (meeting.Actual_Cost__c != null) {
            meeting.Payment_Status__c = PAYMENT_IN_ACCOUNTING;
            meeting.Status__c = STATUS_CONCLUDED;
        } else {
            meeting.Status__c = STATUS_APPROVED;
            meeting.Was_Approved__c = true;
            meeting.Approved_Planned_Cost__c = meeting.Planned_Cost__c == null ? 0 : meeting.Planned_Cost__c;
        }
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromStatus, meeting.Status__c, 'approve',
            'Fully approved by ' + step.Approver_Role__c + suffix(comments));
    }

    public static void reject(Id meetingId, String reason) {
        if (String.isBlank(reason)) {
            throw new ChainException('A rejection reason is required.');
        }
        Meeting__c meeting = loadMeeting(meetingId);
        Meeting_Approval_Step__c step = requireActionableStep(meeting);
        step.Status__c = STEP_REJECTED;
        step.Decided_At__c = System.now();
        step.Comments__c = trimTo(reason.trim(), 4000);
        update step;
        skipOpenSteps(meetingId, 'Closed after rejection');

        String fromStatus = meeting.Status__c;
        meeting.Current_Approver__c = null;
        meeting.Approval_Status__c = APPROVAL_REJECTED;
        if (meeting.Actual_Cost__c != null) {
            meeting.Payment_Status__c = PAYMENT_RETURNED;
        } else {
            meeting.Status__c = STATUS_DRAFT;
        }
        update meeting;
        MeetingHistoryService.writeTransition(meetingId, fromStatus, meeting.Status__c, 'reject',
            step.Approver_Role__c + ' rejected: ' + reason.trim());
    }

    public static Meeting_Approval_Step__c currentStep(Id meetingId, Decimal round) {
        List<Meeting_Approval_Step__c> rows = [
            SELECT Id, Approver__c, Approver_Role__c, Status__c, Step_Number__c, Round__c
            FROM Meeting_Approval_Step__c
            WHERE Meeting__c = :meetingId AND Round__c = :round AND Status__c = :STEP_PENDING
            ORDER BY Step_Number__c ASC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static Boolean canDecide(Meeting__c meeting, Id userId) {
        if (meeting.Approval_Status__c != APPROVAL_IN_APPROVAL) {
            return false;
        }
        Meeting_Approval_Step__c step = currentStep(meeting.Id, meeting.Approval_Round__c);
        if (step == null) {
            return false;
        }
        if (step.Approver__c == userId) {
            return true;
        }
        return meeting.OwnerId != userId && isSuperUser();
    }

    private static Meeting_Approval_Step__c requireActionableStep(Meeting__c meeting) {
        if (meeting.Approval_Status__c != APPROVAL_IN_APPROVAL) {
            throw new ChainException('This meeting is not waiting for approval.');
        }
        Meeting_Approval_Step__c step = currentStep(meeting.Id, meeting.Approval_Round__c);
        if (step == null) {
            throw new ChainException('No approval step is waiting on this meeting.');
        }
        if (!canDecide(meeting, UserInfo.getUserId())) {
            throw new ChainException('This approval is assigned to another approver.');
        }
        return step;
    }

    private static Meeting_Approval_Step__c nextWaitingStep(Meeting__c meeting) {
        List<Meeting_Approval_Step__c> rows = [
            SELECT Id, Approver__c, Approver_Role__c, Status__c, Step_Number__c
            FROM Meeting_Approval_Step__c
            WHERE Meeting__c = :meeting.Id AND Round__c = :meeting.Approval_Round__c AND Status__c = :STEP_WAITING
            ORDER BY Step_Number__c ASC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static void skipOpenSteps(Id meetingId, String comment) {
        List<Meeting_Approval_Step__c> open = [
            SELECT Id, Comments__c
            FROM Meeting_Approval_Step__c
            WHERE Meeting__c = :meetingId AND Status__c IN (:STEP_WAITING, :STEP_PENDING)
        ];
        for (Meeting_Approval_Step__c step : open) {
            step.Status__c = STEP_SKIPPED;
            step.Comments__c = comment;
        }
        if (!open.isEmpty()) {
            update open;
        }
    }

    // ---------------------------------------------------------------- chain building

    public static List<Meeting_Approval_Level__c> rulesFor(String department, Decimal amount) {
        return rulesFor(department, null, amount);
    }

    /**
     * Steps for a department, activity type and amount. Levels listing the activity type replace the
     * department's default levels (those with no activity types) for that type.
     */
    public static List<Meeting_Approval_Level__c> rulesFor(String department, String activityType, Decimal amount) {
        List<Meeting_Approval_Level__c> departmentRules = new List<Meeting_Approval_Level__c>();
        List<Meeting_Approval_Level__c> typeRules = new List<Meeting_Approval_Level__c>();
        for (Meeting_Approval_Level__c rule : ruleSource()) {
            if (rule.Is_Active__c != true || rule.Department__c != department) {
                continue;
            }
            List<String> types = MeetingTypeService.split(rule.Activity_Types__c);
            if (types.isEmpty()) {
                departmentRules.add(rule);
            } else if (String.isNotBlank(activityType) && types.contains(activityType)) {
                typeRules.add(rule);
            }
        }
        List<RuleSort> sorted = new List<RuleSort>();
        for (Meeting_Approval_Level__c rule : typeRules.isEmpty() ? departmentRules : typeRules) {
            if (rule.Min_Amount__c != null) {
                Boolean passes = rule.Strictly_Greater__c == true
                    ? amount > rule.Min_Amount__c
                    : amount >= rule.Min_Amount__c;
                if (!passes) {
                    continue;
                }
            }
            sorted.add(new RuleSort(rule));
        }
        sorted.sort();
        List<Meeting_Approval_Level__c> result = new List<Meeting_Approval_Level__c>();
        for (RuleSort item : sorted) {
            result.add(item.rule);
        }
        return result;
    }

    /** Approval levels from Meetings Setup; the Meeting Approval Rule metadata until the first level is saved. */
    public static List<Meeting_Approval_Level__c> ruleSource() {
        if (levelsOverride != null) {
            return levelsOverride;
        }
        if (rulesOverride == null) {
            List<Meeting_Approval_Level__c> levels = [
                SELECT Id, Department__c, Activity_Types__c, Step_Order__c, Role_Label__c, Role_Values__c,
                    Approver_Source__c, Approver__c, Approver__r.Name, Min_Amount__c, Strictly_Greater__c, Is_Active__c
                FROM Meeting_Approval_Level__c
                ORDER BY Department__c, Activity_Types__c NULLS FIRST, Step_Order__c
                LIMIT 1000
            ];
            if (!levels.isEmpty()) {
                return levels;
            }
        }
        List<Meeting_Approval_Level__c> fromMetadata = new List<Meeting_Approval_Level__c>();
        for (Meeting_Approval_Rule__mdt rule : rulesOverride != null ? rulesOverride : Meeting_Approval_Rule__mdt.getAll().values()) {
            fromMetadata.add(new Meeting_Approval_Level__c(
                Department__c = rule.Department__c,
                Step_Order__c = rule.Step_Order__c,
                Role_Label__c = rule.Role_Label__c,
                Role_Values__c = rule.Role_Values__c,
                Approver_Source__c = rule.Approver_Source__c,
                Min_Amount__c = rule.Min_Amount__c,
                Strictly_Greater__c = rule.Strictly_Greater__c,
                Is_Active__c = rule.Is_Active__c
            ));
        }
        return fromMetadata;
    }

    public static Boolean usesMetadataRules() {
        return levelsOverride == null && [SELECT COUNT() FROM Meeting_Approval_Level__c] == 0;
    }

    public static List<Meeting_Approval_Step__c> buildSteps(Meeting__c meeting, Decimal amount, Integer round) {
        List<Meeting_Approval_Level__c> rules = rulesFor(meeting.Originating_Department__c, meeting.Activity_Type__c, amount);
        Map<Id, User> users = new Map<Id, User>([
            SELECT Id, Name, ManagerId, Title, IsActive
            FROM User
            WHERE IsActive = TRUE AND UserType = 'Standard'
            LIMIT 5000
        ]);
        User owner = users.get(meeting.OwnerId);
        List<User> managerChain = managerChain(owner, users);
        Id brandManagerId = brandManager(meeting.Brand__c, users);
        ownerTerritoryLevels = territoryLevels(meeting.OwnerId);

        List<Meeting_Approval_Step__c> steps = new List<Meeting_Approval_Step__c>();
        Set<Id> used = new Set<Id>();
        Id previousApprover;
        Integer stepNumber = 0;
        for (Meeting_Approval_Level__c rule : rules) {
            Id approverId = brandManagerId != null && roleValues(rule).contains('brand manager')
                ? brandManagerId
                : resolveApprover(rule, owner, managerChain, previousApprover, users);
            stepNumber++;
            Meeting_Approval_Step__c step = new Meeting_Approval_Step__c(
                Meeting__c = meeting.Id,
                Approver_Role__c = trimTo(rule.Role_Label__c, 80),
                Step_Number__c = stepNumber,
                Round__c = round
            );
            if (approverId == null) {
                step.Status__c = STEP_SKIPPED;
                step.Comments__c = 'No active user holds this role in the requester\'s line.';
            } else if (approverId == meeting.OwnerId || used.contains(approverId)) {
                step.Approver__c = approverId;
                step.Status__c = STEP_SKIPPED;
                step.Comments__c = approverId == meeting.OwnerId
                    ? 'Requester holds this role.'
                    : 'Same approver as an earlier step.';
                previousApprover = approverId;
            } else {
                step.Approver__c = approverId;
                step.Status__c = STEP_WAITING;
                used.add(approverId);
                previousApprover = approverId;
            }
            steps.add(step);
        }

        if (used.isEmpty()) {
            Id fallback = owner?.ManagerId;
            if (fallback == null || !users.containsKey(fallback)) {
                throw new ChainException(
                    'No approver could be found for the ' + meeting.Originating_Department__c +
                    ' chain. Ask an admin to set your manager or territory role.'
                );
            }
            steps.add(new Meeting_Approval_Step__c(
                Meeting__c = meeting.Id,
                Approver__c = fallback,
                Approver_Role__c = 'Line Manager',
                Step_Number__c = stepNumber + 1,
                Round__c = round,
                Status__c = STEP_WAITING,
                Comments__c = 'Fallback to the requester\'s manager.'
            ));
        }
        return steps;
    }

    private static Id brandManager(Id brandId, Map<Id, User> users) {
        if (brandId == null) {
            return null;
        }
        List<Product2> brands = [SELECT Brand_Manager__c FROM Product2 WHERE Id = :brandId LIMIT 1];
        Id managerId = brands.isEmpty() ? null : brands[0].Brand_Manager__c;
        return managerId != null && users.containsKey(managerId) ? managerId : null;
    }

    private static List<User> managerChain(User owner, Map<Id, User> users) {
        List<User> chain = new List<User>();
        Set<Id> seen = new Set<Id>();
        Id cursor = owner?.ManagerId;
        while (cursor != null && chain.size() < MAX_CHAIN_DEPTH && !seen.contains(cursor)) {
            seen.add(cursor);
            User manager = users.get(cursor);
            if (manager == null) {
                break;
            }
            chain.add(manager);
            cursor = manager.ManagerId;
        }
        return chain;
    }

    private static Id resolveApprover(
        Meeting_Approval_Level__c rule,
        User owner,
        List<User> managerChain,
        Id previousApprover,
        Map<Id, User> users
    ) {
        Set<String> wanted = roleValues(rule);
        String source = String.isBlank(rule.Approver_Source__c) ? 'Chain Role' : rule.Approver_Source__c;
        if (source == 'Specific User') {
            return rule.Approver__c != null && users.containsKey(rule.Approver__c) ? rule.Approver__c : null;
        }
        if (source == 'Manager') {
            return owner?.ManagerId != null && users.containsKey(owner.ManagerId) ? owner.ManagerId : null;
        }
        if (source == 'Manager Of Previous') {
            if (previousApprover != null) {
                User previous = users.get(previousApprover);
                if (previous?.ManagerId != null && users.containsKey(previous.ManagerId)) {
                    return previous.ManagerId;
                }
            }
            return chainRole(wanted, owner, managerChain);
        }
        if (source == 'Title') {
            for (User candidate : managerChain) {
                if (matches(candidate.Title, wanted)) {
                    return candidate.Id;
                }
            }
            for (User candidate : users.values()) {
                if (matches(candidate.Title, wanted)) {
                    return candidate.Id;
                }
            }
            return null;
        }
        return chainRole(wanted, owner, managerChain);
    }

    private static Id chainRole(Set<String> wanted, User owner, List<User> managerChain) {
        if (wanted.isEmpty()) {
            return null;
        }
        for (User candidate : managerChain) {
            if (matches(candidate.Title, wanted)) {
                return candidate.Id;
            }
        }
        return territoryRole(wanted, owner?.Id);
    }

    /** Territory members from the requester's territories upwards, nearest level first; loaded once per chain. */
    private static List<List<UserTerritory2Association>> ownerTerritoryLevels;

    private static Id territoryRole(Set<String> wanted, Id ownerId) {
        if (ownerId == null) {
            return null;
        }
        if (ownerTerritoryLevels == null) {
            ownerTerritoryLevels = territoryLevels(ownerId);
        }
        for (List<UserTerritory2Association> level : ownerTerritoryLevels) {
            for (UserTerritory2Association member : level) {
                if (matches(member.RoleInTerritory2, wanted)) {
                    return member.UserId;
                }
            }
        }
        return null;
    }

    private static List<List<UserTerritory2Association>> territoryLevels(Id ownerId) {
        List<List<UserTerritory2Association>> levels = new List<List<UserTerritory2Association>>();
        if (ownerId == null) {
            return levels;
        }
        Set<Id> level = new Set<Id>();
        for (UserTerritory2Association assignment : [
            SELECT Territory2Id FROM UserTerritory2Association WHERE UserId = :ownerId
        ]) {
            level.add(assignment.Territory2Id);
        }
        List<Set<Id>> ladder = new List<Set<Id>>();
        Set<Id> visited = new Set<Id>(level);
        for (Integer depth = 0; depth < MAX_CHAIN_DEPTH && !level.isEmpty(); depth++) {
            ladder.add(level);
            Set<Id> parents = new Set<Id>();
            for (Territory2 territory : [SELECT ParentTerritory2Id FROM Territory2 WHERE Id IN :level]) {
                if (territory.ParentTerritory2Id != null && !visited.contains(territory.ParentTerritory2Id)) {
                    parents.add(territory.ParentTerritory2Id);
                }
            }
            visited.addAll(parents);
            level = parents;
        }
        Map<Id, List<UserTerritory2Association>> byTerritory = new Map<Id, List<UserTerritory2Association>>();
        for (UserTerritory2Association member : [
            SELECT UserId, RoleInTerritory2, Territory2Id
            FROM UserTerritory2Association
            WHERE Territory2Id IN :visited AND UserId != :ownerId AND User.IsActive = TRUE
        ]) {
            if (!byTerritory.containsKey(member.Territory2Id)) {
                byTerritory.put(member.Territory2Id, new List<UserTerritory2Association>());
            }
            byTerritory.get(member.Territory2Id).add(member);
        }
        for (Set<Id> territoryIds : ladder) {
            List<UserTerritory2Association> members = new List<UserTerritory2Association>();
            for (Id territoryId : territoryIds) {
                if (byTerritory.containsKey(territoryId)) {
                    members.addAll(byTerritory.get(territoryId));
                }
            }
            levels.add(members);
        }
        return levels;
    }

    private static Set<String> roleValues(Meeting_Approval_Level__c rule) {
        Set<String> values = new Set<String>();
        String raw = String.isBlank(rule.Role_Values__c) ? rule.Role_Label__c : rule.Role_Values__c;
        if (String.isBlank(raw)) {
            return values;
        }
        for (String part : raw.split(';')) {
            if (String.isNotBlank(part)) {
                values.add(part.trim().toLowerCase());
            }
        }
        return values;
    }

    private static Boolean matches(String value, Set<String> wanted) {
        return String.isNotBlank(value) && wanted.contains(value.trim().toLowerCase());
    }

    // ---------------------------------------------------------------- sharing and helpers

    public static void shareWithUsers(Id meetingId, Id ownerId, Set<Id> userIds) {
        List<Meeting__Share> shares = new List<Meeting__Share>();
        for (Id userId : userIds) {
            if (userId == null || userId == ownerId) {
                continue;
            }
            shares.add(new Meeting__Share(
                ParentId = meetingId,
                UserOrGroupId = userId,
                AccessLevel = 'Read',
                RowCause = Schema.Meeting__Share.RowCause.Manual
            ));
        }
        if (!shares.isEmpty()) {
            Database.insert(shares, false);
        }
    }

    public static String formatAmount(Decimal amount) {
        Decimal value = amount == null ? 0 : amount.setScale(2);
        return value.format() + ' ' + MeetingFinanceService.currencyCode();
    }

    public static String trimTo(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() > maxLength ? value.left(maxLength) : value;
    }

    private static String suffix(String comments) {
        return String.isBlank(comments) ? '' : ': ' + comments.trim();
    }

    private class RuleSort implements Comparable {
        Meeting_Approval_Level__c rule;
        RuleSort(Meeting_Approval_Level__c rule) {
            this.rule = rule;
        }
        public Integer compareTo(Object other) {
            Decimal mine = rule.Step_Order__c == null ? 0 : rule.Step_Order__c;
            Decimal theirs = ((RuleSort) other).rule.Step_Order__c;
            theirs = theirs == null ? 0 : theirs;
            return mine == theirs ? 0 : (mine > theirs ? 1 : -1);
        }
    }
}
