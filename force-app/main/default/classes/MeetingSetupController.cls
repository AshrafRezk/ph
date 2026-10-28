/**
 * Admin Console > Meetings Setup: meeting types (who, where, which screen parts) and the approval
 * levels per department and type, plus a preview of what a given user can plan and who approves it.
 * Editing needs the Manage Meeting Workflows or Meeting Super User permission, or edit access to Meeting Types.
 */
public without sharing class MeetingSetupController {
    private static final List<String> DEPARTMENTS = new List<String>{ 'Sales', 'Marketing', 'Medical', 'L&D' };
    private static final String MANAGERS =
        'District Manager;Area Manager;National Sales Manager;Product Manager;Brand Manager;Group Brand Lead;' +
        'Medical Manager;MSL;Business Unit Head;Business Excellence Manager';

    public class Setup {
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Boolean usesMetadataRules;
        @AuraEnabled public List<MeetingTypeService.TypeConfig> types;
        @AuraEnabled public List<LevelRow> levels;
        @AuraEnabled public List<String> departments;
        @AuraEnabled public List<Choice> recordTypes;
        @AuraEnabled public List<Choice> titles;
        @AuraEnabled public List<Choice> permissionSets;
        @AuraEnabled public List<Choice> territories;
    }

    public class LevelRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String department;
        @AuraEnabled public List<String> activityTypes;
        @AuraEnabled public Decimal stepOrder;
        @AuraEnabled public String roleLabel;
        @AuraEnabled public String roleValues;
        @AuraEnabled public String approverSource;
        @AuraEnabled public Id approverId;
        @AuraEnabled public String approverName;
        @AuraEnabled public Decimal minAmount;
        @AuraEnabled public Boolean strictlyGreater;
        @AuraEnabled public Boolean isActive;
    }

    public class Choice {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        Choice(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Preview {
        @AuraEnabled public MeetingTypeService.UserContext user;
        @AuraEnabled public List<MeetingTypeService.Eligibility> types;
        @AuraEnabled public List<PreviewStep> steps;
        @AuraEnabled public String chainError;
    }

    public class PreviewStep {
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public String role;
        @AuraEnabled public String approverName;
        @AuraEnabled public String status;
        @AuraEnabled public String note;
    }

    // ---------------------------------------------------------------- reads

    @AuraEnabled
    public static Setup getSetup() {
        try {
            Setup setup = new Setup();
            setup.canEdit = canEdit();
            setup.usesMetadataRules = MeetingApprovalChainService.usesMetadataRules();
            setup.types = MeetingTypeService.allTypes();
            setup.departments = DEPARTMENTS;
            setup.levels = new List<LevelRow>();
            for (Meeting_Approval_Level__c level : MeetingApprovalChainService.ruleSource()) {
                setup.levels.add(toRow(level));
            }
            setup.recordTypes = new List<Choice>();
            for (Schema.RecordTypeInfo info : Schema.SObjectType.Meeting__c.getRecordTypeInfos()) {
                if (info.isActive() && !info.isMaster()) {
                    setup.recordTypes.add(new Choice(info.getName(), info.getDeveloperName()));
                }
            }
            Set<String> titles = new Set<String>(MeetingTypeService.split(MANAGERS));
            titles.addAll(new List<String>{ 'Medical Rep', 'L&D Manager', 'Training Manager', 'Field Intelligence Manager', 'CEO' });
            for (AggregateResult row : [
                SELECT Title FROM User WHERE IsActive = TRUE AND UserType = 'Standard' AND Title != NULL GROUP BY Title LIMIT 500
            ]) {
                titles.add((String) row.get('Title'));
            }
            List<String> sortedTitles = new List<String>(titles);
            sortedTitles.sort();
            setup.titles = new List<Choice>();
            for (String title : sortedTitles) {
                setup.titles.add(new Choice(title, title));
            }
            setup.permissionSets = new List<Choice>();
            for (PermissionSet permissionSet : [
                SELECT Name, Label FROM PermissionSet
                WHERE IsOwnedByProfile = FALSE AND NamespacePrefix = NULL AND Type = 'Regular'
                ORDER BY Label LIMIT 500
            ]) {
                setup.permissionSets.add(new Choice(permissionSet.Label, permissionSet.Name));
            }
            setup.territories = new List<Choice>();
            for (Territory2 territory : [
                SELECT Name, ParentTerritory2.Name FROM Territory2
                WHERE Territory2Model.State = 'Active' ORDER BY Name LIMIT 2000
            ]) {
                String parent = territory.ParentTerritory2?.Name;
                setup.territories.add(new Choice(parent == null ? territory.Name : territory.Name + ' (in ' + parent + ')', territory.Name));
            }
            return setup;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static List<Choice> searchUsers(String term) {
        try {
            String pattern = '%' + (term == null ? '' : term.trim()) + '%';
            List<Choice> rows = new List<Choice>();
            for (User user : [
                SELECT Id, Name, Title FROM User
                WHERE IsActive = TRUE AND UserType = 'Standard' AND Name LIKE :pattern
                ORDER BY Name LIMIT 20
            ]) {
                rows.add(new Choice(user.Title == null ? user.Name : user.Name + ' · ' + user.Title, user.Id));
            }
            return rows;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /** What the user can plan, and the chain a meeting of this department, type and amount would get. */
    @AuraEnabled
    public static Preview preview(Id userId, String department, String activityType, Decimal amount) {
        try {
            requireEdit();
            Preview result = new Preview();
            result.user = MeetingTypeService.contextFor(userId);
            result.types = MeetingTypeService.eligibility(userId);
            result.steps = new List<PreviewStep>();
            if (String.isNotBlank(department)) {
                Meeting__c draft = new Meeting__c(
                    OwnerId = userId,
                    Originating_Department__c = department,
                    Activity_Type__c = activityType
                );
                try {
                    Integer position = 0;
                    for (Meeting_Approval_Step__c step : MeetingApprovalChainService.buildSteps(draft, amount == null ? 0 : amount, 1)) {
                        PreviewStep row = new PreviewStep();
                        row.stepNumber = ++position;
                        row.role = step.Approver_Role__c;
                        row.status = step.Status__c == MeetingApprovalChainService.STEP_SKIPPED ? 'Skipped' : 'Approves';
                        row.note = step.Comments__c;
                        row.approverName = step.Approver__c == null ? null : nameOf(step.Approver__c);
                        result.steps.add(row);
                    }
                } catch (MeetingApprovalChainService.ChainException e) {
                    result.chainError = e.getMessage();
                }
            }
            return result;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- writes

    @AuraEnabled
    public static Setup saveType(String payload) {
        try {
            requireEdit();
            MeetingTypeService.TypeConfig input = (MeetingTypeService.TypeConfig) JSON.deserialize(payload, MeetingTypeService.TypeConfig.class);
            if (String.isBlank(input.activityType)) {
                throw new SetupException('Choose the activity type.');
            }
            if (input.departments == null || input.departments.isEmpty()) {
                throw new SetupException('Pick at least one department that can raise this type.');
            }
            Meeting_Type__c row = toRecord(input);
            List<Meeting_Type__c> existing = [SELECT Id FROM Meeting_Type__c WHERE Activity_Type__c = :input.activityType LIMIT 1];
            if (!existing.isEmpty()) {
                row.Id = existing[0].Id;
            }
            upsert row;
            MeetingTypeService.clearCache();
            return getSetup();
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Setup saveLevel(String payload) {
        try {
            requireEdit();
            LevelRow input = (LevelRow) JSON.deserialize(payload, LevelRow.class);
            if (!DEPARTMENTS.contains(input.department)) {
                throw new SetupException('Choose the department.');
            }
            if (String.isBlank(input.roleLabel)) {
                throw new SetupException('Enter the role label shown on the approval path.');
            }
            if (input.approverSource == 'Specific User' && input.approverId == null) {
                throw new SetupException('Choose the approver for a Specific User step.');
            }
            // While the chain still comes from the deployed (metadata) setup, its steps have no record Id,
            // so copying and then saving the edited row would create a duplicate step.
            if (MeetingApprovalChainService.usesMetadataRules()) {
                throw new SetupException(
                    'The approval chain still comes from the deployed setup. Click "Load BRD defaults" once to make an editable copy, then edit the step.'
                );
            }
            upsert new Meeting_Approval_Level__c(
                Id = input.id,
                Department__c = input.department,
                Activity_Types__c = input.activityTypes == null || input.activityTypes.isEmpty() ? null : String.join(input.activityTypes, ';'),
                Step_Order__c = input.stepOrder,
                Role_Label__c = input.roleLabel.trim(),
                Role_Values__c = String.isBlank(input.roleValues) ? null : input.roleValues.trim(),
                Approver_Source__c = String.isBlank(input.approverSource) ? 'Chain Role' : input.approverSource,
                Approver__c = input.approverSource == 'Specific User' ? input.approverId : null,
                Min_Amount__c = input.minAmount,
                Strictly_Greater__c = input.strictlyGreater == true,
                Is_Active__c = input.isActive != false
            );
            return getSetup();
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Setup deleteLevel(Id levelId) {
        try {
            requireEdit();
            List<Meeting_Approval_Level__c> rows = [SELECT Id FROM Meeting_Approval_Level__c WHERE Id = :levelId];
            if (rows.isEmpty()) {
                throw new SetupException(
                    'This step comes from the deployed setup and was not removed. Click "Load BRD defaults" once to make an editable copy, then remove it.'
                );
            }
            delete rows;
            return getSetup();
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /** Creates the BRD default for any activity type that has no setup yet, and copies the metadata chain once. */
    @AuraEnabled
    public static Setup loadDefaults() {
        try {
            requireEdit();
            seedDefaults();
            return getSetup();
        } catch (Exception e) {
            throw fail(e);
        }
    }

    public static void seedDefaults() {
        Set<String> existing = new Set<String>();
        for (Meeting_Type__c row : [SELECT Activity_Type__c FROM Meeting_Type__c]) {
            existing.add(row.Activity_Type__c);
        }
        Set<String> picklist = new Set<String>();
        for (Schema.PicklistEntry entry : Meeting__c.Activity_Type__c.getDescribe().getPicklistValues()) {
            picklist.add(entry.getValue());
        }
        List<Meeting_Type__c> inserts = new List<Meeting_Type__c>();
        for (Meeting_Type__c row : brdDefaults()) {
            if (picklist.contains(row.Activity_Type__c) && !existing.contains(row.Activity_Type__c)) {
                inserts.add(row);
            }
        }
        insert inserts;
        copyMetadataRulesIfNeeded();
        MeetingTypeService.clearCache();
    }

    @TestVisible
    private static List<Meeting_Type__c> brdDefaults() {
        return new List<Meeting_Type__c>{
            hcpType('KOL Roundtable (RTD)', 'KOL Roundtable', 'RTD', 10, 'Sales;Marketing;Medical',
                'Round-table discussion with HCPs from your call-plan target list.', true, true),
            hcpType('Speaker Meeting', 'Speaker Meeting', 'Speaker_Meeting', 20, 'Marketing;Sales;Medical',
                'A speaker presents to target HCPs. Needs target-list HCPs and a brand.', true, true),
            withCreators(hcpType('Advisory Board', 'Advisory Board', 'Advisory_Board', 30, 'Medical;Marketing',
                'Closed expert panel. Managers only; no walk-in guests.', false, false), MANAGERS, false),
            hcpType('Seminar', 'Seminar', 'Promotional_Activity', 40, 'Marketing;Medical;Sales',
                'Scientific seminar for HCPs, colleagues and guests.', false, false),
            webinar(),
            withCreators(hcpType('Conference', 'Conference', 'Promotional_Activity', 60, 'Marketing;Medical',
                'Large external event. Managers only.', false, false), MANAGERS, true),
            withCreators(hcpType('Symposium', 'Symposium', 'Promotional_Activity', 70, 'Marketing;Medical',
                'Symposium with invited HCPs. Managers only.', false, false), MANAGERS, true),
            training()
        };
    }

    private static Meeting_Type__c hcpType(
        String label, String activityType, String recordType, Integer sortOrder, String departments,
        String description, Boolean targetHcps, Boolean brand
    ) {
        return new Meeting_Type__c(
            Name = label, Activity_Type__c = activityType, Record_Type__c = recordType, Sort_Order__c = sortOrder,
            Departments__c = departments, Description__c = description, Is_Active__c = true,
            Allow_HCPs__c = true, Require_Target_HCPs__c = targetHcps, Min_HCPs__c = 1,
            Allow_Colleagues__c = true, Allow_Guests__c = true,
            Show_Invitations__c = true, Allow_Door_Scan__c = true, Allow_Deposit__c = true,
            Show_Suggestions__c = true, Require_Invoice__c = true, Require_Brand__c = brand
        );
    }

    private static Meeting_Type__c withCreators(Meeting_Type__c row, String titles, Boolean guests) {
        row.Creator_Titles__c = titles;
        row.Allow_Guests__c = guests;
        row.Show_Suggestions__c = false;
        return row;
    }

    private static Meeting_Type__c webinar() {
        Meeting_Type__c row = hcpType('Webinar', 'Webinar', 'Promotional_Activity', 50, 'Marketing;Medical',
            'Online session. Personal links, no door scan and no deposit.', false, false);
        row.Min_HCPs__c = null;
        row.Allow_Door_Scan__c = false;
        row.Allow_Deposit__c = false;
        return row;
    }

    private static Meeting_Type__c training() {
        return new Meeting_Type__c(
            Name = 'L&D Training', Activity_Type__c = 'Training', Record_Type__c = 'Promotional_Activity', Sort_Order__c = 80,
            Departments__c = 'L&D', Is_Active__c = true,
            Description__c = 'Field Intelligence or classroom training for employees. Attendance is captured.',
            Creator_Titles__c = 'L&D Manager;Training Manager;Field Intelligence Manager;Product Manager;Business Excellence Manager',
            Allow_HCPs__c = false, Require_Target_HCPs__c = false, Min_HCPs__c = null,
            Allow_Colleagues__c = true, Allow_Guests__c = false,
            Show_Invitations__c = false, Allow_Door_Scan__c = false, Allow_Deposit__c = false,
            Show_Suggestions__c = false, Require_Invoice__c = true, Require_Brand__c = false,
            Min_Attendance_Pct__c = 80
        );
    }

    /** The first edit to the chain moves the metadata rules into records, so the full chain stays visible and editable. */
    private static void copyMetadataRulesIfNeeded() {
        if (!MeetingApprovalChainService.usesMetadataRules()) {
            return;
        }
        List<Meeting_Approval_Level__c> copies = new List<Meeting_Approval_Level__c>();
        for (Meeting_Approval_Level__c rule : MeetingApprovalChainService.ruleSource()) {
            copies.add(rule.clone(false, true));
        }
        insert copies;
    }

    // ---------------------------------------------------------------- helpers

    private static Meeting_Type__c toRecord(MeetingTypeService.TypeConfig input) {
        return new Meeting_Type__c(
            Name = String.isBlank(input.label) ? input.activityType : input.label.trim().left(80),
            Activity_Type__c = input.activityType,
            Record_Type__c = input.recordType,
            Is_Active__c = input.isActive != false,
            Sort_Order__c = input.sortOrder,
            Description__c = input.description == null ? null : input.description.left(255),
            Departments__c = join(input.departments),
            Territories__c = join(input.territories),
            Creator_Titles__c = join(input.creatorTitles),
            Creator_Permission_Sets__c = join(input.creatorPermissionSets),
            Allow_HCPs__c = input.allowHcps == true,
            Require_Target_HCPs__c = input.requireTargetHcps == true,
            Min_HCPs__c = input.minHcps,
            Allow_Colleagues__c = input.allowColleagues == true,
            Allow_Guests__c = input.allowGuests == true,
            Show_Invitations__c = input.showInvitations == true,
            Allow_Door_Scan__c = input.allowDoorScan == true,
            Allow_Deposit__c = input.allowDeposit == true,
            Show_Suggestions__c = input.showSuggestions == true,
            Require_Invoice__c = input.requireInvoice == true,
            Require_Brand__c = input.requireBrand == true,
            Min_Attendance_Pct__c = input.minAttendancePct,
            Workspace_Tabs__c = join(input.workspaceTabs)
        );
    }

    private static LevelRow toRow(Meeting_Approval_Level__c level) {
        LevelRow row = new LevelRow();
        row.id = level.Id;
        row.department = level.Department__c;
        row.activityTypes = MeetingTypeService.split(level.Activity_Types__c);
        row.stepOrder = level.Step_Order__c;
        row.roleLabel = level.Role_Label__c;
        row.roleValues = level.Role_Values__c;
        row.approverSource = String.isBlank(level.Approver_Source__c) ? 'Chain Role' : level.Approver_Source__c;
        row.approverId = level.Approver__c;
        row.approverName = level.Approver__c == null ? null : level.Approver__r?.Name;
        row.minAmount = level.Min_Amount__c;
        row.strictlyGreater = level.Strictly_Greater__c == true;
        row.isActive = level.Is_Active__c == true;
        return row;
    }

    private static String join(List<String> values) {
        return values == null || values.isEmpty() ? null : String.join(values, ';');
    }

    private static String nameOf(Id userId) {
        for (User user : [SELECT Name FROM User WHERE Id = :userId LIMIT 1]) {
            return user.Name;
        }
        return null;
    }

    private static Boolean canEdit() {
        return FeatureManagement.checkPermission('Manage_Meeting_Workflows')
            || MeetingApprovalChainService.isSuperUser()
            || Schema.SObjectType.Meeting_Type__c.isUpdateable();
    }

    private static void requireEdit() {
        if (!canEdit()) {
            throw new SetupException('You need the Manage Meeting Workflows permission to change Meetings Setup.');
        }
    }

    public class SetupException extends Exception {}

    private static AuraHandledException fail(Exception e) {
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}