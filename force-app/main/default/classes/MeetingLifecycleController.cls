/**
 * One API for the meetings home, workspace, and accounting desk (Lightning and the field shell).
 * Meeting__c is private, so reads run in system mode after canView() confirms the caller is the
 * owner, an approver in the chain, the owner's manager, accounting, or a meeting super user.
 */
public without sharing class MeetingLifecycleController {
    private static final Map<String, String> RECORD_TYPE_BY_ACTIVITY = new Map<String, String>{
        'Speaker Meeting' => 'Speaker_Meeting',
        'KOL Roundtable' => 'RTD',
        'Advisory Board' => 'Advisory_Board'
    };
    private static final String DEFAULT_RECORD_TYPE = 'Promotional_Activity';
    private static final Set<String> ATTENDEE_EDIT_STATUSES = new Set<String>{ 'Draft', 'Approved' };
    private static final Set<String> ATTENDANCE_STATUSES = new Set<String>{ 'Approved', 'Concluded', 'Incomplete' };
    /** Invitations can go out while a meeting is still in draft or approval, so guests can arrive in any of these. */
    private static final Set<String> SCAN_STATUSES = new Set<String>{
        'Draft', 'PendingApproval', 'Pending GPM Approval', 'Pending NLM Approval', 'Approved', 'Concluded', 'Incomplete'
    };
    private static final Set<String> HCP_ACCOUNT_RECORD_TYPES = new Set<String>{
        'SDO_PersonAccounts', 'Medical_Professional_HCP', 'PersonAccount'
    };

    // ---------------------------------------------------------------- DTOs

    public class MeetingCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String status;
        @AuraEnabled public String approvalStatus;
        @AuraEnabled public String paymentStatus;
        @AuraEnabled public String department;
        @AuraEnabled public String activityType;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public DateTime startDateTime;
        @AuraEnabled public DateTime endDateTime;
        @AuraEnabled public String venue;
        @AuraEnabled public Id ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String brandName;
        @AuraEnabled public Decimal plannedCost;
        @AuraEnabled public Decimal approvedPlannedCost;
        @AuraEnabled public Decimal depositAmount;
        @AuraEnabled public Decimal actualCost;
        @AuraEnabled public Decimal paidAmount;
        @AuraEnabled public Decimal remainingAmount;
        @AuraEnabled public String currentApproverName;
        @AuraEnabled public String stage;
        @AuraEnabled public Boolean lifecycle;
        @AuraEnabled public String waitingRole;
        @AuraEnabled public DateTime waitingSince;
        @AuraEnabled public Integer attendeeCount;
        @AuraEnabled public Integer serviceCount;
    }

    public class HomeData {
        @AuraEnabled public String userName;
        @AuraEnabled public Boolean isAccounting;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public List<MeetingCard> mine;
        @AuraEnabled public List<MeetingCard> approvals;
        @AuraEnabled public Integer accountingCount;
    }

    public class StepRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Integer stepNumber;
        @AuraEnabled public Integer round;
        @AuraEnabled public String role;
        @AuraEnabled public String approverName;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime decidedAt;
        @AuraEnabled public String comments;
    }

    public class MemberRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String kind;
        @AuraEnabled public String name;
        @AuraEnabled public String detail;
        @AuraEnabled public String status;
        @AuraEnabled public String attendance;
        @AuraEnabled public Id recordId;
    }

    public class ServiceRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String serviceName;
        @AuraEnabled public String vendorName;
        @AuraEnabled public String description;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal unitCost;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String speakerName;
        @AuraEnabled public String chargedToName;
    }

    public class PaymentRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Date paidOn;
        @AuraEnabled public String reference;
        @AuraEnabled public String paymentFor;
    }

    public class FileRow {
        @AuraEnabled public Id documentId;
        @AuraEnabled public Id versionId;
        @AuraEnabled public String title;
        @AuraEnabled public String extension;
        @AuraEnabled public Integer size;
        @AuraEnabled public DateTime createdDate;
        @AuraEnabled public String downloadUrl;
    }

    public class HistoryRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String fromStatus;
        @AuraEnabled public String toStatus;
        @AuraEnabled public String action;
        @AuraEnabled public String reason;
        @AuraEnabled public String changedBy;
        @AuraEnabled public DateTime changedAt;
    }

    public class Actions {
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public Boolean canSubmit = false;
        @AuraEnabled public Boolean canApprove = false;
        @AuraEnabled public Boolean canReject = false;
        @AuraEnabled public Boolean canManageAttendees = false;
        @AuraEnabled public Boolean canMarkAttendance = false;
        @AuraEnabled public Boolean canExecute = false;
        @AuraEnabled public Boolean canDeposit = false;
        @AuraEnabled public Boolean canActualCost = false;
        @AuraEnabled public Boolean canPay = false;
        @AuraEnabled public Boolean canSendBack = false;
        @AuraEnabled public Boolean canClose = false;
        @AuraEnabled public Boolean canCancel = false;
        @AuraEnabled public Boolean canInvite = false;
        @AuraEnabled public Boolean canScan = false;
    }

    public class Workspace {
        @AuraEnabled public MeetingCard meeting;
        @AuraEnabled public String objectives;
        @AuraEnabled public String agenda;
        @AuraEnabled public Id brandId;
        @AuraEnabled public Decimal estimatedParticipants;
        @AuraEnabled public String accountingNotes;
        @AuraEnabled public Boolean isOwner;
        @AuraEnabled public Boolean requiresHcp;
        @AuraEnabled public String submitBlocker;
        @AuraEnabled public Decimal thresholdPct;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal actualIncreasePct;
        @AuraEnabled public Integer currentRound;
        @AuraEnabled public List<StepRow> steps;
        @AuraEnabled public List<StepRow> earlierSteps;
        @AuraEnabled public List<MemberRow> members;
        @AuraEnabled public List<ServiceRow> services;
        @AuraEnabled public List<PaymentRow> payments;
        @AuraEnabled public List<FileRow> files;
        @AuraEnabled public List<HistoryRow> history;
        @AuraEnabled public List<MeetingInvitationService.InvitationRow> invitations;
        @AuraEnabled public Boolean siteReady;
        @AuraEnabled public Actions actions;
        @AuraEnabled public MeetingTypeService.TypeConfig typeConfig;
        @AuraEnabled public Integer attendanceMarked;
        @AuraEnabled public Decimal attendancePct;
        @AuraEnabled public Boolean approvalPreview;
        @AuraEnabled public String approvalNote;
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String detail;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public Boolean flag;
        @AuraEnabled public Boolean honorarium;
        Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    public class Options {
        @AuraEnabled public List<Option> departments;
        @AuraEnabled public List<Option> activityTypes;
        @AuraEnabled public List<MeetingTypeService.TypeConfig> types;
        @AuraEnabled public List<Option> services;
        @AuraEnabled public List<Option> vendors;
        @AuraEnabled public List<Option> brands;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Decimal thresholdPct;
    }

    public class PersonRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String detail;
        @AuraEnabled public Boolean onTargetList;
        @AuraEnabled public Decimal honorariumFee;
    }

    public class MeetingInput {
        public Id id;
        public String title;
        public String department;
        public String activityType;
        public DateTime startDateTime;
        public DateTime endDateTime;
        public String venue;
        public Id brandId;
        public String agenda;
        public Decimal estimatedParticipants;
    }

    // ---------------------------------------------------------------- reads

    @AuraEnabled
    public static HomeData getHome() {
        try {
            Id me = UserInfo.getUserId();
            HomeData data = new HomeData();
            data.userName = UserInfo.getName();
            data.isAccounting = MeetingFinanceService.isAccounting() || MeetingApprovalChainService.isSuperUser();
            data.currencyCode = MeetingFinanceService.currencyCode();
            data.mine = new List<MeetingCard>();
            data.approvals = new List<MeetingCard>();

            List<Meeting__c> mine = Database.query(
                cardSelect() + ' WHERE OwnerId = :me ORDER BY Start_Date_Time__c DESC NULLS LAST LIMIT 200'
            );
            for (Meeting__c meeting : mine) {
                data.mine.add(toCard(meeting));
            }

            Map<Id, Meeting_Approval_Step__c> stepByMeeting = new Map<Id, Meeting_Approval_Step__c>();
            for (Meeting_Approval_Step__c step : [
                SELECT Meeting__c, Approver_Role__c, LastModifiedDate
                FROM Meeting_Approval_Step__c
                WHERE Approver__c = :me AND Status__c = :MeetingApprovalChainService.STEP_PENDING
                ORDER BY LastModifiedDate ASC
                LIMIT 200
            ]) {
                stepByMeeting.put(step.Meeting__c, step);
            }
            if (!stepByMeeting.isEmpty()) {
                Set<Id> ids = stepByMeeting.keySet();
                for (Meeting__c meeting : Database.query(cardSelect() + ' WHERE Id IN :ids ORDER BY Start_Date_Time__c ASC')) {
                    MeetingCard card = toCard(meeting);
                    Meeting_Approval_Step__c step = stepByMeeting.get(meeting.Id);
                    card.waitingRole = step.Approver_Role__c;
                    card.waitingSince = step.LastModifiedDate;
                    data.approvals.add(card);
                }
            }
            data.accountingCount = data.isAccounting
                ? [SELECT COUNT() FROM Meeting__c WHERE Payment_Status__c IN ('In Accounting', 'Partial Paid')]
                : 0;
            return data;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace getWorkspace(Id meetingId) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireView(meeting);
            return buildWorkspace(meeting);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static Options getOptions() {
        try {
            Options options = new Options();
            options.currencyCode = MeetingFinanceService.currencyCode();
            options.thresholdPct = MeetingFinanceService.reapprovalThresholdPct();
            options.departments = picklist(Meeting__c.Originating_Department__c);
            options.types = MeetingTypeService.creatableTypes(UserInfo.getUserId());
            options.activityTypes = new List<Option>();
            for (MeetingTypeService.TypeConfig config : options.types) {
                Option option = new Option(config.label, config.activityType);
                option.detail = config.description;
                options.activityTypes.add(option);
            }
            options.services = new List<Option>();
            for (Meeting_Service__c service : [
                SELECT Id, Name, Department__c, Default_Unit_Cost__c, Requires_Vendor__c
                FROM Meeting_Service__c
                WHERE Is_Active__c = TRUE
                ORDER BY Name
                LIMIT 500
            ]) {
                Option option = new Option(service.Name, service.Id);
                option.detail = service.Department__c;
                option.amount = service.Default_Unit_Cost__c;
                option.flag = service.Requires_Vendor__c;
                option.honorarium = isHonorariumService(service.Name);
                options.services.add(option);
            }
            options.vendors = new List<Option>();
            for (Meeting_Vendor__c vendor : [
                SELECT Id, Name, Category__c FROM Meeting_Vendor__c WHERE Is_Active__c = TRUE ORDER BY Name LIMIT 500
            ]) {
                Option option = new Option(vendor.Name, vendor.Id);
                option.detail = vendor.Category__c;
                options.vendors.add(option);
            }
            options.brands = new List<Option>();
            for (Product2 brand : [
                SELECT Id, Name FROM Product2 WHERE IsActive = TRUE AND Product_Type__c = 'Brand' ORDER BY Name LIMIT 500
            ]) {
                options.brands.add(new Option(brand.Name, brand.Id));
            }
            return options;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static List<MeetingCard> getAccountingQueue() {
        try {
            if (!MeetingFinanceService.isAccounting() && !MeetingApprovalChainService.isSuperUser()) {
                throw auraError('You need the Meeting Accounting permission.');
            }
            List<MeetingCard> rows = new List<MeetingCard>();
            for (Meeting__c meeting : Database.query(
                cardSelect() +
                ' WHERE Payment_Status__c IN (\'In Accounting\', \'Partial Paid\', \'Returned to Business\', \'Paid\')' +
                ' AND Status__c NOT IN (\'Cancelled\')' +
                ' ORDER BY LastModifiedDate DESC LIMIT 300'
            )) {
                rows.add(toCard(meeting));
            }
            return rows;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static List<PersonRow> searchPeople(Id meetingId, String kind, String term) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            List<PersonRow> rows = new List<PersonRow>();
            String pattern = String.isBlank(term) ? '%' : '%' + term.trim() + '%';
            MeetingTypeService.requireKind(meeting, kind);
            if (kind == 'employee') {
                for (User user : [
                    SELECT Id, Name, Title
                    FROM User
                    WHERE IsActive = TRUE AND UserType = 'Standard' AND Name LIKE :pattern AND Id != :meeting.OwnerId
                    ORDER BY Name
                    LIMIT 25
                ]) {
                    rows.add(person(user.Id, user.Name, user.Title));
                }
                return rows;
            }
            if (kind != 'hcp') {
                return rows;
            }
            for (MeetingHcpAttendeeService.HcpCandidate candidate :
                    MeetingHcpAttendeeService.searchAlignedHcpCandidates(meeting, term)) {
                PersonRow row = person(candidate.accountId, candidate.accountName, candidate.detail);
                row.onTargetList = candidate.onTargetList;
                row.honorariumFee = candidate.honorariumFee;
                rows.add(row);
            }
            return rows;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- meeting edits

    @AuraEnabled
    public static Id saveMeeting(String payload) {
        try {
            MeetingInput input = (MeetingInput) JSON.deserialize(payload, MeetingInput.class);
            if (String.isBlank(input.title)) {
                throw auraError('Give the meeting a title.');
            }
            if (input.startDateTime == null || input.endDateTime == null || input.endDateTime <= input.startDateTime) {
                throw auraError('Set a start time and an end time after it.');
            }
            Meeting__c meeting;
            if (input.id != null) {
                meeting = MeetingApprovalChainService.loadMeeting(input.id);
                requireOwner(meeting);
                if (meeting.Status__c != 'Draft') {
                    throw auraError('Only draft meetings can be edited.');
                }
            }
            if (meeting == null || meeting.Activity_Type__c != input.activityType
                    || meeting.Originating_Department__c != input.department) {
                MeetingTypeService.requireCanCreate(input.activityType, input.department);
            }
            if (meeting == null) {
                meeting = new Meeting__c(
                    OwnerId = UserInfo.getUserId(),
                    Status__c = 'Draft',
                    Approval_Status__c = MeetingApprovalChainService.APPROVAL_NOT_SUBMITTED,
                    Payment_Status__c = MeetingFinanceService.PAYMENT_NOT_STARTED
                );
            }
            meeting.Objectives__c = input.title.trim();
            meeting.Originating_Department__c = input.department;
            meeting.Activity_Type__c = input.activityType;
            meeting.Start_Date_Time__c = input.startDateTime;
            meeting.End_Date_Time__c = input.endDateTime;
            meeting.Venue__c = MeetingApprovalChainService.trimTo(input.venue, 255);
            meeting.Brand__c = input.brandId;
            meeting.Agenda__c = input.agenda;
            meeting.Estimated_Participants__c = input.estimatedParticipants;
            Id recordTypeId = recordTypeFor(input.activityType, MeetingTypeService.forType(input.activityType).recordType);
            if (recordTypeId != null) {
                meeting.RecordTypeId = recordTypeId;
            }
            upsert meeting;
            if (input.id == null) {
                MeetingHistoryService.writeTransition(meeting.Id, null, 'Draft', 'create', 'Meeting created');
            }
            return meeting.Id;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    public static void addServiceItem(Id meetingId, Id serviceId, Id vendorId, String description, Decimal quantity, Decimal unitCost) {
        addServiceItem(meetingId, serviceId, vendorId, description, quantity, unitCost, null, null);
    }

    @AuraEnabled
    public static void addServiceItem(
        Id meetingId, Id serviceId, Id vendorId, String description, Decimal quantity, Decimal unitCost,
        Id speakerId, Id chargedToId
    ) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            requireDraft(meeting);
            if (serviceId == null) {
                throw auraError('Choose a service.');
            }
            Meeting_Service__c service = [
                SELECT Name FROM Meeting_Service__c WHERE Id = :serviceId LIMIT 1
            ];
            if (isHonorariumService(service.Name)) {
                if (speakerId == null) {
                    throw auraError('Choose the HCP. The honorarium comes from their standard fee.');
                }
                if (!MeetingHcpAttendeeService.isSelectableHcp(meeting, speakerId)) {
                    throw auraError('Choose an HCP aligned to your territory.');
                }
                Account speaker = [
                    SELECT Name, Honorarium_Fee__c FROM Account WHERE Id = :speakerId LIMIT 1
                ];
                if (speaker.Honorarium_Fee__c == null) {
                    throw auraError(speaker.Name + ' has no honorarium standard fee on the account.');
                }
                unitCost = speaker.Honorarium_Fee__c;
                if (String.isBlank(description)) {
                    description = 'Honorarium · ' + speaker.Name;
                }
            }
            if (unitCost == null || unitCost < 0) {
                throw auraError('Enter the unit cost.');
            }
            if (chargedToId != null && [SELECT COUNT() FROM User WHERE Id = :chargedToId AND IsActive = TRUE] == 0) {
                throw auraError('Choose the rep this expense is assigned to.');
            }
            insert new Meeting_Service_Item__c(
                Meeting__c = meetingId,
                Service__c = serviceId,
                Vendor__c = vendorId,
                Speaker__c = speakerId,
                Charged_To__c = chargedToId,
                Description__c = MeetingApprovalChainService.trimTo(description, 255),
                Quantity__c = quantity == null || quantity <= 0 ? 1 : quantity,
                Unit_Cost__c = unitCost
            );
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace setMeetingBrand(Id meetingId, Id brandId) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            if (meeting.Status__c != 'Draft' && meeting.Status__c != 'Rejected') {
                throw auraError('The brand can be changed while the meeting is a draft.');
            }
            meeting.Brand__c = brandId;
            update meeting;
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static void removeServiceItem(Id itemId) {
        try {
            Meeting_Service_Item__c item = [SELECT Id, Meeting__c FROM Meeting_Service_Item__c WHERE Id = :itemId LIMIT 1];
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(item.Meeting__c);
            requireOwner(meeting);
            requireDraft(meeting);
            delete item;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static void addAttendee(Id meetingId, String kind, Id recordId, String writeInName) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            if (!ATTENDEE_EDIT_STATUSES.contains(meeting.Status__c)) {
                throw auraError('Attendees can be changed while the meeting is a draft or approved.');
            }
            MeetingTypeService.requireKind(meeting, kind == 'hcp' || kind == 'employee' ? kind : 'guest');
            if (kind == 'hcp') {
                if (!MeetingHcpAttendeeService.isSelectableHcp(meeting, recordId)) {
                    throw auraError('Choose an HCP aligned to your territory.');
                }
                if (MeetingHcpAttendeeService.requiresHcpAttendees(meeting)) {
                    MeetingHcpAttendeeService.addHcpAttendee(meetingId, recordId);
                    return;
                }
                if ([SELECT COUNT() FROM Meeting_Member__c WHERE Meeting__c = :meetingId AND Customer__c = :recordId] > 0) {
                    throw auraError('This HCP is already on the meeting.');
                }
                insert new Meeting_Member__c(
                    Meeting__c = meetingId, RecordTypeId = memberRecordType('Attendee'),
                    Customer__c = recordId, Type__c = 'Participant', Status__c = 'Invited'
                );
            } else if (kind == 'employee') {
                if ([SELECT COUNT() FROM Meeting_Member__c WHERE Meeting__c = :meetingId AND Colleague__c = :recordId] > 0) {
                    throw auraError('This colleague is already on the meeting.');
                }
                insert new Meeting_Member__c(
                    Meeting__c = meetingId, RecordTypeId = memberRecordType('Colleague'),
                    Colleague__c = recordId, Type__c = 'Participant', Status__c = 'Invited'
                );
                MeetingApprovalChainService.shareWithUsers(meetingId, meeting.OwnerId, new Set<Id>{ recordId });
            } else {
                if (String.isBlank(writeInName)) {
                    throw auraError('Enter the guest name.');
                }
                insert new Meeting_Member__c(
                    Meeting__c = meetingId, RecordTypeId = memberRecordType('Write_In'),
                    Write_In_Name__c = writeInName.trim().left(255), Type__c = 'Participant', Status__c = 'Invited'
                );
            }
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static void removeAttendee(Id memberId) {
        try {
            Meeting_Member__c member = [SELECT Id, Meeting__c FROM Meeting_Member__c WHERE Id = :memberId LIMIT 1];
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(member.Meeting__c);
            requireOwner(meeting);
            if (!ATTENDEE_EDIT_STATUSES.contains(meeting.Status__c)) {
                throw auraError('Attendees can be changed while the meeting is a draft or approved.');
            }
            delete [SELECT Id FROM Meeting_Invitation__c WHERE Meeting_Member__c = :memberId];
            delete member;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static void setAttendance(Id memberId, String attendance) {
        try {
            Meeting_Member__c member = [SELECT Id, Meeting__c FROM Meeting_Member__c WHERE Id = :memberId LIMIT 1];
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(member.Meeting__c);
            requireOwner(meeting);
            if (!ATTENDANCE_STATUSES.contains(meeting.Status__c)) {
                throw auraError('Attendance can be taken once the meeting is approved.');
            }
            member.Attendance_Status__c = attendance;
            update member;
            if (attendance == 'Attended') {
                for (Meeting_Invitation__c invitation : [
                    SELECT Id, Meeting_Member__c, Status__c, Checked_In_At__c
                    FROM Meeting_Invitation__c
                    WHERE Meeting_Member__c = :memberId AND Status__c != 'Checked In'
                ]) {
                    MeetingInvitationService.checkIn(invitation);
                }
            }
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- lifecycle actions

    @AuraEnabled
    public static Workspace submitMeeting(Id meetingId) {
        try {
            MeetingApprovalChainService.submit(meetingId);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace approveMeeting(Id meetingId, String comments) {
        try {
            MeetingApprovalChainService.approve(meetingId, comments);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace rejectMeeting(Id meetingId, String reason) {
        try {
            MeetingApprovalChainService.reject(meetingId, reason);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace markExecuted(Id meetingId) {
        try {
            String attendance = MeetingTypeService.attendanceProblem(MeetingApprovalChainService.loadMeeting(meetingId));
            if (attendance != null) {
                throw auraError(attendance);
            }
            MeetingFinanceService.markExecuted(meetingId);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace submitDeposit(Id meetingId, Decimal amount, String fileName, String base64Data) {
        try {
            MeetingFinanceService.submitDeposit(meetingId, amount, fileName, base64Data);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace submitActualCost(Id meetingId, Decimal amount, String fileName, String base64Data) {
        try {
            MeetingFinanceService.submitActualCost(meetingId, amount, fileName, base64Data);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace uploadInvoice(Id meetingId, String fileName, String base64Data) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            MeetingFinanceService.saveInvoice(meetingId, fileName, base64Data);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace recordPayment(Id meetingId, Decimal amount, Date paidOn, String reference) {
        try {
            MeetingFinanceService.recordPayment(meetingId, amount, paidOn, reference);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace sendBackToBusiness(Id meetingId, String notes) {
        try {
            MeetingFinanceService.sendBack(meetingId, notes);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace closeMeeting(Id meetingId) {
        try {
            MeetingFinanceService.closeMeeting(meetingId);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace cancelMeeting(Id meetingId, String reason) {
        try {
            MeetingFinanceService.cancelMeeting(meetingId, reason);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- invitations

    @AuraEnabled
    public static Workspace inviteAttendees(Id meetingId) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            requireInvitable(meeting);
            Integer created = MeetingInvitationService.inviteMembers(meetingId);
            if (created == 0 && [SELECT COUNT() FROM Meeting_Invitation__c WHERE Meeting__c = :meetingId] == 0) {
                throw auraError('Add attendees first, then create their invitations.');
            }
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace addGuestInvitation(Id meetingId, String guestName, String phone, String email) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            requireOwner(meeting);
            requireInvitable(meeting);
            MeetingInvitationService.addGuest(meetingId, guestName, phone, email);
            return reload(meetingId);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static MeetingInvitationService.InvitationRow sendInvitationEmail(Id invitationId, String email) {
        try {
            Meeting_Invitation__c invitation = MeetingInvitationService.loadInvitation(invitationId);
            requireOwner(MeetingApprovalChainService.loadMeeting(invitation.Meeting__c));
            if (invitation.Active__c != true) {
                throw auraError('Turn the invitation on before sending it.');
            }
            return MeetingInvitationService.sendEmail(invitationId, email);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /** Door scanner: validates a guest's rotating QR and checks them in. */
    @AuraEnabled
    public static MeetingInvitationService.ScanResult scanAttendee(Id meetingId, String payload) {
        try {
            Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
            if (!canScan(meeting)) {
                throw auraError('You cannot check guests in for this meeting.');
            }
            return MeetingInvitationService.scan(meeting, payload, System.now().getTime());
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /** A door scan the field app saved offline; judged at the time the device scanned it. */
    public static MeetingInvitationService.ScanResult scanAttendeeAt(Id meetingId, String payload, Long scannedAtMillis) {
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
        if (!canScan(meeting)) {
            throw auraError('You cannot check guests in for this meeting.');
        }
        return MeetingInvitationService.scanAt(meeting, payload, scannedAtMillis, System.now().getTime());
    }

    public class ScanPack {
        @AuraEnabled public Id meetingId;
        @AuraEnabled public String status;
        @AuraEnabled public DateTime opens;
        @AuraEnabled public DateTime closes;
        @AuraEnabled public Long serverNow;
        @AuraEnabled public List<PackGuest> guests = new List<PackGuest>();
    }

    public class PackGuest {
        @AuraEnabled public Id invitationId;
        @AuraEnabled public String code;
        @AuraEnabled public String secret;
        @AuraEnabled public String guestName;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean active;
        @AuraEnabled public DateTime checkedInAt;
    }

    /**
     * Everything the field app needs to check guests in at a door with no signal, including each
     * invitation's QR signing key. Only staff who may scan get it, and only while check-in is open.
     */
    public static ScanPack getScanPack(Id meetingId) {
        Meeting__c meeting = MeetingApprovalChainService.loadMeeting(meetingId);
        if (!canScan(meeting)) {
            throw auraError('You cannot check guests in for this meeting.');
        }
        if (!MeetingInvitationService.isCheckInWindow(meeting, System.now())) {
            throw auraError('Door check-in is not open for this meeting.');
        }
        ScanPack pack = new ScanPack();
        pack.meetingId = meeting.Id;
        pack.status = meeting.Status__c;
        pack.opens = MeetingInvitationService.checkInOpens(meeting);
        pack.closes = (meeting.End_Date_Time__c == null ? meeting.Start_Date_Time__c : meeting.End_Date_Time__c).addHours(6);
        pack.serverNow = System.now().getTime();
        List<Meeting_Invitation__c> rows = [
            SELECT Id, Code__c, Qr_Secret__c, Guest_Name__c, Status__c, Active__c, Checked_In_At__c
            FROM Meeting_Invitation__c
            WHERE Meeting__c = :meeting.Id
            ORDER BY Guest_Name__c
            LIMIT 2000
        ];
        List<Meeting_Invitation__c> missingKeys = new List<Meeting_Invitation__c>();
        for (Meeting_Invitation__c row : rows) {
            if (String.isBlank(row.Qr_Secret__c)) {
                row.Qr_Secret__c = MeetingInvitationService.newSecret();
                missingKeys.add(new Meeting_Invitation__c(Id = row.Id, Qr_Secret__c = row.Qr_Secret__c));
            }
            PackGuest guest = new PackGuest();
            guest.invitationId = row.Id;
            guest.code = row.Code__c;
            guest.secret = row.Qr_Secret__c;
            guest.guestName = row.Guest_Name__c;
            guest.status = row.Status__c;
            guest.active = row.Active__c == true;
            guest.checkedInAt = row.Checked_In_At__c;
            pack.guests.add(guest);
        }
        if (!missingKeys.isEmpty()) {
            update missingKeys;
        }
        return pack;
    }

    /** Adds a walk-in guest once; a retried offline add with the same name and phone is not duplicated. */
    public static Workspace addGuestOnce(Id meetingId, String guestName, String phone, String email) {
        String name = String.isBlank(guestName) ? null : guestName.trim();
        String mobile = String.isBlank(phone) ? null : phone.trim();
        if (name != null && [
            SELECT COUNT() FROM Meeting_Invitation__c
            WHERE Meeting__c = :meetingId AND Guest_Name__c = :name AND Phone__c = :mobile
        ] > 0) {
            return reload(meetingId);
        }
        return addGuestInvitation(meetingId, guestName, phone, email);
    }

    @AuraEnabled
    public static MeetingInvitationService.InvitationRow markInvitationSent(Id invitationId, String phone) {
        try {
            Meeting_Invitation__c invitation = MeetingInvitationService.loadInvitation(invitationId);
            requireOwner(MeetingApprovalChainService.loadMeeting(invitation.Meeting__c));
            return MeetingInvitationService.markSent(invitationId, phone);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Workspace setInvitationActive(Id invitationId, Boolean active) {
        try {
            Meeting_Invitation__c invitation = MeetingInvitationService.loadInvitation(invitationId);
            requireOwner(MeetingApprovalChainService.loadMeeting(invitation.Meeting__c));
            MeetingInvitationService.setActive(invitationId, active);
            return reload(invitation.Meeting__c);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- workspace assembly

    private static Workspace reload(Id meetingId) {
        return buildWorkspace(MeetingApprovalChainService.loadMeeting(meetingId));
    }

    @TestVisible
    private static Workspace buildWorkspace(Meeting__c meeting) {
        Id me = UserInfo.getUserId();
        Boolean superUser = MeetingApprovalChainService.isSuperUser();
        Boolean accounting = MeetingFinanceService.isAccounting() || superUser;
        Boolean isOwner = meeting.OwnerId == me || superUser;
        Boolean lifecycle = MeetingApprovalChainService.isLifecycleMeeting(meeting);

        Workspace ws = new Workspace();
        ws.meeting = toCard(meeting);
        ws.objectives = meeting.Objectives__c;
        ws.agenda = meeting.Agenda__c;
        ws.brandId = meeting.Brand__c;
        ws.estimatedParticipants = meeting.Estimated_Participants__c;
        ws.accountingNotes = meeting.Accounting_Notes__c;
        ws.isOwner = meeting.OwnerId == me;
        ws.thresholdPct = MeetingFinanceService.reapprovalThresholdPct();
        ws.currencyCode = MeetingFinanceService.currencyCode();
        ws.currentRound = meeting.Approval_Round__c == null ? 0 : meeting.Approval_Round__c.intValue();
        MeetingTypeService.TypeConfig typeConfig = MeetingTypeService.forMeeting(meeting);
        ws.typeConfig = typeConfig;
        ws.requiresHcp = typeConfig.requireTargetHcps;
        if (meeting.Actual_Cost__c != null) {
            Decimal baseline = meeting.Approved_Planned_Cost__c != null ? meeting.Approved_Planned_Cost__c : meeting.Planned_Cost__c;
            ws.actualIncreasePct = MeetingFinanceService.increasePct(baseline, meeting.Actual_Cost__c).setScale(1);
        }

        ws.steps = new List<StepRow>();
        ws.earlierSteps = new List<StepRow>();
        for (Meeting_Approval_Step__c step : [
            SELECT Id, Step_Number__c, Round__c, Approver_Role__c, Approver__r.Name, Status__c, Decided_At__c, Comments__c
            FROM Meeting_Approval_Step__c
            WHERE Meeting__c = :meeting.Id
            ORDER BY Round__c DESC, Step_Number__c ASC
        ]) {
            StepRow row = new StepRow();
            row.id = step.Id;
            row.stepNumber = step.Step_Number__c == null ? 0 : step.Step_Number__c.intValue();
            row.round = step.Round__c == null ? 0 : step.Round__c.intValue();
            row.role = step.Approver_Role__c;
            row.approverName = step.Approver__r?.Name;
            row.status = step.Status__c;
            row.decidedAt = step.Decided_At__c;
            row.comments = step.Comments__c;
            if (row.round == ws.currentRound) {
                ws.steps.add(row);
            } else {
                ws.earlierSteps.add(row);
            }
        }
        if (ws.steps.isEmpty() && (meeting.Status__c == 'Draft' || meeting.Status__c == 'Rejected')) {
            ws.approvalPreview = true;
            try {
                Decimal planned = meeting.Planned_Cost__c == null ? 0 : meeting.Planned_Cost__c;
                List<Meeting_Approval_Step__c> plannedSteps = MeetingApprovalChainService.buildSteps(meeting, planned, 0);
                Set<Id> approverIds = new Set<Id>();
                for (Meeting_Approval_Step__c step : plannedSteps) {
                    if (step.Approver__c != null) {
                        approverIds.add(step.Approver__c);
                    }
                }
                Map<Id, User> approvers = approverIds.isEmpty()
                    ? new Map<Id, User>()
                    : new Map<Id, User>([SELECT Name FROM User WHERE Id IN :approverIds]);
                for (Meeting_Approval_Step__c step : plannedSteps) {
                    StepRow row = new StepRow();
                    row.stepNumber = step.Step_Number__c == null ? 0 : step.Step_Number__c.intValue();
                    row.round = 0;
                    row.role = step.Approver_Role__c;
                    row.approverName = approvers.get(step.Approver__c)?.Name;
                    row.status = step.Status__c == MeetingApprovalChainService.STEP_WAITING ? 'Planned' : step.Status__c;
                    row.comments = step.Comments__c;
                    ws.steps.add(row);
                }
            } catch (Exception previewError) {
                ws.approvalNote = previewError.getMessage();
            }
        }

        ws.members = new List<MemberRow>();
        for (Meeting_Member__c member : [
            SELECT Id, Customer__c, Customer__r.Name, Customer__r.Specialty_1__c, Colleague__c, Colleague__r.Name,
                Colleague__r.Title, Write_In_Name__c, Status__c, Attendance_Status__c, Type__c
            FROM Meeting_Member__c
            WHERE Meeting__c = :meeting.Id AND Type__c NOT IN ('Approver', 'Second Approver')
            ORDER BY CreatedDate ASC
            LIMIT 500
        ]) {
            MemberRow row = new MemberRow();
            row.id = member.Id;
            if (member.Customer__c != null) {
                row.kind = 'hcp';
                row.name = member.Customer__r?.Name;
                row.detail = member.Customer__r?.Specialty_1__c;
                row.recordId = member.Customer__c;
            } else if (member.Colleague__c != null) {
                row.kind = 'employee';
                row.name = member.Colleague__r?.Name;
                row.detail = member.Colleague__r?.Title;
                row.recordId = member.Colleague__c;
            } else {
                row.kind = 'guest';
                row.name = member.Write_In_Name__c;
            }
            row.status = member.Status__c;
            row.attendance = member.Attendance_Status__c;
            ws.members.add(row);
        }
        Integer attended = 0;
        ws.attendanceMarked = 0;
        for (MemberRow row : ws.members) {
            if (String.isNotBlank(row.attendance)) {
                ws.attendanceMarked++;
            }
            if (row.attendance == 'Attended') {
                attended++;
            }
        }
        ws.attendancePct = ws.members.isEmpty() ? null : (attended * 100.0 / ws.members.size()).setScale(0);

        ws.services = new List<ServiceRow>();
        for (Meeting_Service_Item__c item : [
            SELECT Id, Service__r.Name, Vendor__r.Name, Speaker__r.Name, Charged_To__r.Name,
                Description__c, Quantity__c, Unit_Cost__c, Planned_Amount__c
            FROM Meeting_Service_Item__c
            WHERE Meeting__c = :meeting.Id
            ORDER BY CreatedDate ASC
        ]) {
            ServiceRow row = new ServiceRow();
            row.id = item.Id;
            row.serviceName = item.Service__r?.Name;
            row.vendorName = item.Vendor__r?.Name;
            row.speakerName = item.Speaker__r?.Name;
            row.chargedToName = item.Charged_To__r?.Name;
            row.description = item.Description__c;
            row.quantity = item.Quantity__c;
            row.unitCost = item.Unit_Cost__c;
            row.amount = item.Planned_Amount__c;
            ws.services.add(row);
        }

        ws.payments = new List<PaymentRow>();
        for (Meeting_Payment__c payment : [
            SELECT Id, Name, Amount__c, Paid_On__c, Reference__c, Payment_For__c
            FROM Meeting_Payment__c
            WHERE Meeting__c = :meeting.Id
            ORDER BY Paid_On__c DESC, CreatedDate DESC
        ]) {
            PaymentRow row = new PaymentRow();
            row.id = payment.Id;
            row.name = payment.Name;
            row.amount = payment.Amount__c;
            row.paidOn = payment.Paid_On__c;
            row.reference = payment.Reference__c;
            row.paymentFor = payment.Payment_For__c;
            ws.payments.add(row);
        }

        ws.files = new List<FileRow>();
        for (ContentDocumentLink link : [
            SELECT ContentDocumentId, ContentDocument.Title, ContentDocument.FileExtension,
                ContentDocument.ContentSize, ContentDocument.LatestPublishedVersionId, ContentDocument.CreatedDate
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :meeting.Id
            ORDER BY ContentDocument.CreatedDate DESC
            LIMIT 50
        ]) {
            FileRow row = new FileRow();
            row.documentId = link.ContentDocumentId;
            row.versionId = link.ContentDocument.LatestPublishedVersionId;
            row.title = link.ContentDocument.Title;
            row.extension = link.ContentDocument.FileExtension;
            row.size = link.ContentDocument.ContentSize;
            row.createdDate = link.ContentDocument.CreatedDate;
            row.downloadUrl = '/sfc/servlet.shepherd/version/download/' + row.versionId;
            ws.files.add(row);
        }

        ws.history = new List<HistoryRow>();
        for (Meeting_History__c entry : [
            SELECT Id, From_Status__c, To_Status__c, Action_Key__c, Reason__c, Changed_By__r.Name, CreatedDate
            FROM Meeting_History__c
            WHERE Meeting__c = :meeting.Id
            ORDER BY CreatedDate DESC
            LIMIT 100
        ]) {
            HistoryRow row = new HistoryRow();
            row.id = entry.Id;
            row.fromStatus = entry.From_Status__c;
            row.toStatus = entry.To_Status__c;
            row.action = entry.Action_Key__c;
            row.reason = entry.Reason__c;
            row.changedBy = entry.Changed_By__r?.Name;
            row.changedAt = entry.CreatedDate;
            ws.history.add(row);
        }

        String base = MeetingInvitationService.siteBase();
        ws.siteReady = String.isNotBlank(base);
        ws.invitations = MeetingInvitationService.listForMeeting(meeting);

        Actions actions = new Actions();
        String status = meeting.Status__c;
        String payment = meeting.Payment_Status__c;
        Boolean executed = status == 'Concluded' || status == 'Incomplete';
        if (lifecycle || status == 'Draft') {
            actions.canEdit = isOwner && status == 'Draft';
            actions.canSubmit = isOwner && status == 'Draft' && lifecycle;
            actions.canApprove = MeetingApprovalChainService.canDecide(meeting, me);
            actions.canReject = actions.canApprove;
            actions.canManageAttendees = isOwner && ATTENDEE_EDIT_STATUSES.contains(status);
            actions.canMarkAttendance = isOwner && ATTENDANCE_STATUSES.contains(status);
            actions.canExecute = isOwner && status == 'Approved';
            actions.canDeposit = isOwner && typeConfig.allowDeposit && meeting.Approval_Status__c == MeetingApprovalChainService.APPROVAL_FULLY_APPROVED
                && meeting.Status__c == MeetingApprovalChainService.STATUS_APPROVED
                && meeting.Actual_Cost__c == null
                && (meeting.Deposit_Amount__c == null || payment == MeetingFinanceService.PAYMENT_RETURNED);
            actions.canActualCost = isOwner && executed
                && (meeting.Actual_Cost__c == null || payment == MeetingFinanceService.PAYMENT_RETURNED);
            actions.canPay = accounting && (payment == MeetingFinanceService.PAYMENT_IN_ACCOUNTING || payment == MeetingFinanceService.PAYMENT_PARTIAL);
            actions.canSendBack = actions.canPay;
            actions.canClose = isOwner && executed && payment == MeetingFinanceService.PAYMENT_PAID && meeting.Actual_Cost__c != null;
            actions.canCancel = isOwner && new Set<String>{ 'Draft', 'PendingApproval', 'Approved' }.contains(status)
                && (meeting.Paid_Amount__c == null || meeting.Paid_Amount__c == 0);
            actions.canInvite = isOwner && typeConfig.showInvitations && ATTENDEE_EDIT_STATUSES.contains(status) && ws.siteReady;
            actions.canScan = typeConfig.allowDoorScan && SCAN_STATUSES.contains(status) && !ws.invitations.isEmpty();
        }
        ws.actions = actions;

        if (actions.canSubmit) {
            ws.submitBlocker = submitBlocker(meeting, ws);
        }
        return ws;
    }

    private static String submitBlocker(Meeting__c meeting, Workspace ws) {
        if (String.isBlank(meeting.Activity_Type__c)) {
            return 'Choose the activity type.';
        }
        return MeetingTypeService.submitProblem(meeting);
    }

    // ---------------------------------------------------------------- mapping

    private static String cardSelect() {
        return 'SELECT Id, Name, OwnerId, Owner.Name, Status__c, Approval_Status__c, Payment_Status__c, ' +
            'Originating_Department__c, Activity_Type__c, Current_Approver__r.Name, Planned_Cost__c, ' +
            'Approved_Planned_Cost__c, Deposit_Amount__c, Actual_Cost__c, Paid_Amount__c, Remaining_Amount__c, ' +
            'Objectives__c, Venue__c, Brand__r.Name, Start_Date_Time__c, End_Date_Time__c, RecordType.Name, ' +
            '(SELECT Id FROM Meeting_Members__r WHERE Type__c NOT IN (\'Approver\', \'Second Approver\')), ' +
            '(SELECT Id FROM Service_Items__r) FROM Meeting__c';
    }

    @TestVisible
    private static MeetingCard toCard(Meeting__c meeting) {
        MeetingCard card = new MeetingCard();
        card.id = meeting.Id;
        card.name = meeting.Name;
        card.title = String.isNotBlank(meeting.Objectives__c) ? meeting.Objectives__c.left(200) : meeting.Name;
        card.status = meeting.Status__c;
        card.approvalStatus = meeting.Approval_Status__c;
        card.paymentStatus = meeting.Payment_Status__c;
        card.department = meeting.Originating_Department__c;
        card.activityType = meeting.Activity_Type__c;
        card.recordTypeLabel = meeting.RecordType?.Name;
        card.startDateTime = meeting.Start_Date_Time__c;
        card.endDateTime = meeting.End_Date_Time__c;
        card.venue = meeting.Venue__c;
        card.ownerId = meeting.OwnerId;
        card.ownerName = meeting.Owner?.Name;
        card.brandName = meeting.Brand__r?.Name;
        card.plannedCost = meeting.Planned_Cost__c;
        card.approvedPlannedCost = meeting.Approved_Planned_Cost__c;
        card.depositAmount = meeting.Deposit_Amount__c;
        card.actualCost = meeting.Actual_Cost__c;
        card.paidAmount = meeting.Paid_Amount__c;
        card.remainingAmount = meeting.Remaining_Amount__c;
        card.currentApproverName = meeting.Current_Approver__r?.Name;
        card.lifecycle = MeetingApprovalChainService.isLifecycleMeeting(meeting);
        card.stage = stageOf(meeting);
        try {
            card.attendeeCount = meeting.Meeting_Members__r.size();
            card.serviceCount = meeting.Service_Items__r.size();
        } catch (SObjectException e) {
            card.attendeeCount = null;
            card.serviceCount = null;
        }
        return card;
    }

    @TestVisible
    private static String stageOf(Meeting__c meeting) {
        String status = meeting.Status__c;
        if (status == 'Closed' || status == 'Cancelled') {
            return 'closed';
        }
        if (meeting.Approval_Status__c == MeetingApprovalChainService.APPROVAL_IN_APPROVAL
            || status == 'PendingApproval' || status == 'Pending GPM Approval' || status == 'Pending NLM Approval') {
            return 'waiting';
        }
        if (status == 'Draft' || status == 'Rejected') {
            return 'draft';
        }
        if (status == 'Approved') {
            return 'ready';
        }
        return 'cost';
    }

    private static List<Option> picklist(Schema.SObjectField field) {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static Boolean isHonorariumService(String serviceName) {
        String name = serviceName == null ? '' : serviceName.toLowerCase();
        return name.contains('honorarium') || name.contains('speaker fee');
    }

    private static PersonRow person(Id id, String name, String detail) {
        PersonRow row = new PersonRow();
        row.id = id;
        row.name = name;
        row.detail = detail;
        return row;
    }

    @TestVisible
    private static Id recordTypeFor(String activityType) {
        return recordTypeFor(activityType, null);
    }

    private static Id recordTypeFor(String activityType, String configured) {
        if (String.isBlank(activityType)) {
            return null;
        }
        String developerName = String.isNotBlank(configured) ? configured : RECORD_TYPE_BY_ACTIVITY.containsKey(activityType)
            ? RECORD_TYPE_BY_ACTIVITY.get(activityType)
            : DEFAULT_RECORD_TYPE;
        Schema.RecordTypeInfo info = Schema.SObjectType.Meeting__c.getRecordTypeInfosByDeveloperName().get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    private static Id memberRecordType(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Meeting_Member__c.getRecordTypeInfosByDeveloperName().get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }

    // ---------------------------------------------------------------- access

    @TestVisible
    private static Boolean canView(Meeting__c meeting) {
        Id me = UserInfo.getUserId();
        if (meeting.OwnerId == me || MeetingApprovalChainService.isSuperUser() || MeetingFinanceService.isAccounting()) {
            return true;
        }
        if ([SELECT COUNT() FROM Meeting_Approval_Step__c WHERE Meeting__c = :meeting.Id AND Approver__c = :me] > 0) {
            return true;
        }
        if ([SELECT COUNT() FROM Meeting_Member__c WHERE Meeting__c = :meeting.Id AND Colleague__c = :me] > 0) {
            return true;
        }
        List<User> owners = [SELECT ManagerId FROM User WHERE Id = :meeting.OwnerId LIMIT 1];
        if (!owners.isEmpty() && owners[0].ManagerId == me) {
            return true;
        }
        return MeetingApprovalAccess.managesUser(me, meeting.OwnerId);
    }

    private static Boolean canScan(Meeting__c meeting) {
        return SCAN_STATUSES.contains(meeting.Status__c) && MeetingTypeService.forMeeting(meeting).allowDoorScan && canView(meeting);
    }

    private static void requireView(Meeting__c meeting) {
        if (!canView(meeting)) {
            throw auraError('You do not have access to this meeting.');
        }
    }

    private static void requireOwner(Meeting__c meeting) {
        if (meeting.OwnerId != UserInfo.getUserId() && !MeetingApprovalChainService.isSuperUser()) {
            throw auraError('Only the meeting owner can change this meeting.');
        }
    }

    private static void requireDraft(Meeting__c meeting) {
        if (meeting.Status__c != 'Draft') {
            throw auraError('Services can be changed only while the meeting is a draft.');
        }
    }

    private static void requireInvitable(Meeting__c meeting) {
        if (!MeetingTypeService.forMeeting(meeting).showInvitations) {
            throw auraError(meeting.Activity_Type__c + ' meetings do not use invitations.');
        }
        if (!ATTENDEE_EDIT_STATUSES.contains(meeting.Status__c)) {
            throw auraError('Invitations can be sent while the meeting is a draft or approved.');
        }
    }

    public class MeetingException extends Exception {}

    /** AuraHandledException cannot be thrown under @RestResource (the field app), so REST gets a plain one. */
    private static Exception auraError(String message) {
        if (RestContext.request != null) {
            return new MeetingException(message);
        }
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    private static Exception fail(Exception e) {
        if (e instanceof AuraHandledException || e instanceof MeetingException) {
            return e;
        }
        String message = e.getMessage();
        if (e instanceof DmlException) {
            message = ((DmlException) e).getDmlMessage(0);
        }
        return auraError(message);
    }
}
