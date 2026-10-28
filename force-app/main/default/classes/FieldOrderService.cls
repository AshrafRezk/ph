/**
 * Field sales orders (Direct or Distributor) from Home, Account, or Visit.
 * BRD: DM → NAM → BU → Yasser → Finance. Qty ≤10 skips full cycle; qty >200 forces Distributor.
 */
public with sharing class FieldOrderService {
    private static final Integer QTY_SKIP_FULL = 10;
    private static final Integer QTY_FORCE_DISTRIBUTOR = 200;

    private static final String STATUS_DRAFT = 'Draft';
    private static final String STATUS_DM = 'Pending DM';
    private static final String STATUS_NAM = 'Pending NAM';
    private static final String STATUS_BU = 'Pending BU';
    private static final String STATUS_YASSER = 'Pending Yasser';
    private static final String STATUS_FINANCE = 'Pending Finance';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';
    private static final String STATUS_GOODS = 'Goods Issued';
    private static final String STATUS_COLLECTED = 'Collected';
    private static final String STATUS_SETTLED = 'Settled';

    public class LineInput {
        @AuraEnabled public Id productId;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Boolean foc;
        @AuraEnabled public String notes;
    }

    public class OrderInput {
        @AuraEnabled public Id accountId;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String orderType;
        @AuraEnabled public String distributorName;
        @AuraEnabled public String branchName;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Boolean foc;
        @AuraEnabled public String notes;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean submitNow;
        @AuraEnabled public List<LineInput> lines;
    }

    public class OptionRow {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String iconName;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public String subtitle;
    }

    public class LineView {
        @AuraEnabled public Id id;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal quantity;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Boolean foc;
        @AuraEnabled public String notes;
    }

    public class OrderView {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String orderType;
        @AuraEnabled public String distributorName;
        @AuraEnabled public String branchName;
        @AuraEnabled public String status;
        @AuraEnabled public String statusLabel;
        @AuraEnabled public Decimal totalQuantity;
        @AuraEnabled public Decimal discountPercent;
        @AuraEnabled public Boolean foc;
        @AuraEnabled public String notes;
        @AuraEnabled public String source;
        @AuraEnabled public Boolean skipFullApproval;
        @AuraEnabled public String requestedByName;
        @AuraEnabled public String currentApproverName;
        @AuraEnabled public Boolean canApprove;
        @AuraEnabled public Boolean canReject;
        @AuraEnabled public Boolean canAdvanceFulfillment;
        @AuraEnabled public List<LineView> lines;
        @AuraEnabled public String routingHint;
    }

    public class CreateContext {
        @AuraEnabled public Boolean ordersEnabled;
        @AuraEnabled public Id defaultAccountId;
        @AuraEnabled public String defaultAccountName;
        @AuraEnabled public String defaultRecordTypeLabel;
        @AuraEnabled public String defaultIconName;
        @AuraEnabled public Id defaultVisitId;
        @AuraEnabled public List<OptionRow> productOptions;
        @AuraEnabled public List<OptionRow> distributorOptions;
        @AuraEnabled public List<FieldAccountSearch.Hit> accountHints;
    }

    @AuraEnabled(cacheable=true)
    public static CreateContext getCreateContext(Id accountId, Id visitId) {
        Map<String, Boolean> features = FieldAppFeatureController.getEnabledFeatureMap();
        CreateContext ctx = new CreateContext();
        ctx.ordersEnabled = features.get('orders') != false;
        ctx.defaultAccountId = accountId;
        ctx.defaultVisitId = visitId;
        ctx.productOptions = new List<OptionRow>();
        ctx.accountHints = new List<FieldAccountSearch.Hit>();
        ctx.distributorOptions = new List<OptionRow>{
            option('Ibn Sina', 'Ibn Sina'),
            option('Sofico', 'Sofico'),
            option('EPDA', 'EPDA'),
            option('Egydrug', 'Egydrug'),
            option('Elezaby', 'Elezaby'),
            option('Pharmaoverseas', 'Pharmaoverseas'),
            option('Other', 'Other')
        };

        if (visitId != null) {
            List<Visit__c> visits = [
                SELECT Id, Account__c, Account__r.Name, Account__r.RecordType.Name,
                       Account__r.RecordType.DeveloperName
                FROM Visit__c
                WHERE Id = :visitId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!visits.isEmpty()) {
                ctx.defaultVisitId = visits[0].Id;
                if (ctx.defaultAccountId == null) {
                    ctx.defaultAccountId = visits[0].Account__c;
                }
                applyDefaultAccount(ctx, visits[0].Account__r);
            }
        }
        if (ctx.defaultAccountId != null && String.isBlank(ctx.defaultAccountName)) {
            List<Account> accounts = [
                SELECT Id, Name, RecordType.Name, RecordType.DeveloperName
                FROM Account
                WHERE Id = :ctx.defaultAccountId
                WITH USER_MODE
                LIMIT 1
            ];
            if (!accounts.isEmpty()) {
                applyDefaultAccount(ctx, accounts[0]);
            }
        }

        ctx.productOptions = loadProducts(ctx.defaultVisitId);
        if (ctx.defaultAccountId == null) {
            ctx.accountHints = loadPharmacyHints();
        }
        return ctx;
    }

    @AuraEnabled
    public static OrderView saveAndSubmit(OrderInput input) {
        if (input == null || input.accountId == null) {
            throw badRequest('Choose a pharmacy (or hospital/chain) for this order.');
        }
        Map<String, Boolean> features = FieldAppFeatureController.getEnabledFeatureMap();
        if (features.get('orders') == false) {
            throw badRequest('Orders are turned off for the field app.');
        }

        Decimal totalQty = 0;
        List<LineInput> validLines = new List<LineInput>();
        Set<Id> seen = new Set<Id>();
        if (input.lines != null) {
            for (LineInput line : input.lines) {
                if (line == null || line.productId == null) {
                    continue;
                }
                if (line.quantity == null || line.quantity < 1) {
                    throw badRequest('Each line needs a quantity of at least 1.');
                }
                if (line.discountPercent != null && (line.discountPercent < 0 || line.discountPercent > 100)) {
                    throw badRequest('Discount on a line has to be between 0 and 100.');
                }
                if (seen.contains(line.productId)) {
                    continue;
                }
                seen.add(line.productId);
                validLines.add(line);
                totalQty += line.quantity;
            }
        }
        if (validLines.isEmpty()) {
            throw badRequest('Add at least one product with a quantity.');
        }

        String orderType = String.isBlank(input.orderType) ? 'Direct' : input.orderType.trim();
        if (totalQty > QTY_FORCE_DISTRIBUTOR && orderType != 'Distributor') {
            orderType = 'Distributor';
        }
        if (orderType == 'Distributor' && String.isBlank(input.distributorName)) {
            throw badRequest('Pick a distributor for distributor orders.');
        }

        Boolean submitNow = input.submitNow == true;
        Boolean skipFull = totalQty <= QTY_SKIP_FULL;
        Id managerId = currentUserManagerId();

        Field_Order__c order = new Field_Order__c(
            Account__c = input.accountId,
            Visit__c = input.visitId,
            Order_Type__c = orderType,
            Distributor_Name__c = input.distributorName,
            Branch_Name__c = input.branchName,
            Notes__c = input.notes,
            Source__c = String.isBlank(input.source) ? 'Home' : input.source,
            Requested_By__c = UserInfo.getUserId(),
            Total_Quantity__c = totalQty,
            Skip_Full_Approval__c = skipFull,
            Status__c = STATUS_DRAFT
        );

        if (submitNow) {
            order.Submitted_Date__c = Datetime.now();
            if (skipFull) {
                order.Status__c = STATUS_FINANCE;
                order.Current_Approver__c = configuredApprover(STEP_FINANCE);
                order.Decision_Notes__c =
                    'Quantity ≤ ' +
                    QTY_SKIP_FULL +
                    ': full approval cycle skipped; stakeholders notified.';
            } else {
                order.Status__c = STATUS_DM;
                order.Current_Approver__c = managerId;
                if (managerId == null) {
                    throw badRequest('Your manager is not set. Ask SFE to assign a District Manager before submitting.');
                }
            }
        }

        insert as user order;

        List<Field_Order_Line__c> lines = new List<Field_Order_Line__c>();
        Integer display = 1;
        for (LineInput line : validLines) {
            lines.add(
                new Field_Order_Line__c(
                    Field_Order__c = order.Id,
                    Product2__c = line.productId,
                    Quantity__c = line.quantity,
                    Discount_Percent__c = line.discountPercent,
                    FOC__c = line.foc == true,
                    Notes__c = line.notes,
                    Display_Order__c = display
                )
            );
            display++;
        }
        insert as user lines;
        if (submitNow) {
            sendFocSampleRequests(order, validLines);
        }
        return toView(requery(order.Id));
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getMyOpenOrders() {
        return getMyOrders(40);
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getMyOrders(Integer limitSize) {
        Integer lim = normalizeLimit(limitSize, 40);
        Id userId = UserInfo.getUserId();
        List<Field_Order__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Distributor_Name__c,
                   Branch_Name__c, Status__c, Total_Quantity__c, Discount_Percent__c, FOC__c, Notes__c,
                   Source__c, Skip_Full_Approval__c, Requested_By__r.Name, Current_Approver__c,
                   Current_Approver__r.Name, Decision_Notes__c, Submitted_Date__c
            FROM Field_Order__c
            WHERE Requested_By__c = :userId
              AND Status__c NOT IN :new Set<String>{ STATUS_SETTLED, STATUS_REJECTED }
            WITH USER_MODE
            ORDER BY Submitted_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :lim
        ];
        return toViews(rows);
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getApproverQueue() {
        return getApprovalQueue(100);
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getApprovalQueue(Integer limitSize) {
        Integer lim = normalizeLimit(limitSize, 100);
        Id userId = UserInfo.getUserId();
        Set<String> unassignedSteps = configuredStepsFor(userId);
        List<Field_Order__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Distributor_Name__c,
                   Branch_Name__c, Status__c, Total_Quantity__c, Discount_Percent__c, FOC__c, Notes__c,
                   Source__c, Skip_Full_Approval__c, Requested_By__r.Name, Current_Approver__c,
                   Current_Approver__r.Name, Decision_Notes__c, Submitted_Date__c
            FROM Field_Order__c
            WHERE (
                    Current_Approver__c = :userId
                    OR (Current_Approver__c = NULL AND Status__c IN :unassignedSteps)
                )
              AND Status__c IN :new Set<String>{
                  STATUS_DM, STATUS_NAM, STATUS_BU, STATUS_YASSER, STATUS_FINANCE
              }
            WITH USER_MODE
            ORDER BY Submitted_Date__c ASC NULLS LAST
            LIMIT :lim
        ];
        return toViews(rows);
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getFinanceQueue(Integer limitSize) {
        Integer lim = normalizeLimit(limitSize, 40);
        List<Field_Order__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Distributor_Name__c,
                   Branch_Name__c, Status__c, Total_Quantity__c, Discount_Percent__c, FOC__c, Notes__c,
                   Source__c, Skip_Full_Approval__c, Requested_By__r.Name, Current_Approver__c,
                   Current_Approver__r.Name, Decision_Notes__c, Submitted_Date__c
            FROM Field_Order__c
            WHERE Status__c IN :new Set<String>{
                STATUS_FINANCE, STATUS_APPROVED, STATUS_GOODS, STATUS_COLLECTED
            }
            WITH USER_MODE
            ORDER BY Submitted_Date__c ASC NULLS LAST, CreatedDate DESC
            LIMIT :lim
        ];
        return toViews(rows);
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getOrdersForVisit(Id visitId) {
        if (visitId == null) {
            return new List<OrderView>();
        }
        List<Field_Order__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Distributor_Name__c,
                   Branch_Name__c, Status__c, Total_Quantity__c, Discount_Percent__c, FOC__c, Notes__c,
                   Source__c, Skip_Full_Approval__c, Requested_By__r.Name, Current_Approver__c,
                   Current_Approver__r.Name, Decision_Notes__c, Submitted_Date__c
            FROM Field_Order__c
            WHERE Visit__c = :visitId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 40
        ];
        return toViews(rows);
    }

    @AuraEnabled
    public static OrderView decideApproval(Id orderId, Boolean approve, String notes) {
        if (approve == true) {
            return approve(orderId, notes);
        }
        return reject(orderId, String.isBlank(notes) ? 'Rejected' : notes);
    }

    @AuraEnabled
    public static OrderView markPaid(Id orderId) {
        Field_Order__c order = requery(orderId);
        if (order == null) {
            throw badRequest('Order not found.');
        }
        if (order.Status__c == STATUS_FINANCE) {
            // Finance must approve before payment can be recorded (E5-01).
            forApprover(orderId);
            order.Status__c = STATUS_APPROVED;
            order.Current_Approver__c = null;
            update as user order;
            order = requery(order.Id);
        }
        if (order.Status__c == STATUS_APPROVED) {
            return markCollected(markGoodsIssued(order.Id).id);
        }
        if (order.Status__c == STATUS_GOODS) {
            return markCollected(order.Id);
        }
        if (order.Status__c == STATUS_COLLECTED) {
            return toView(order);
        }
        throw badRequest('Finance approval / goods issue must complete before collection.');
    }

    @AuraEnabled(cacheable=false)
    public static List<OrderView> getOrdersForAccount(Id accountId) {
        if (accountId == null) {
            return new List<OrderView>();
        }
        List<Field_Order__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Distributor_Name__c,
                   Branch_Name__c, Status__c, Total_Quantity__c, Discount_Percent__c, FOC__c, Notes__c,
                   Source__c, Skip_Full_Approval__c, Requested_By__r.Name, Current_Approver__c,
                   Current_Approver__r.Name, Decision_Notes__c, Submitted_Date__c
            FROM Field_Order__c
            WHERE Account__c = :accountId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 40
        ];
        return toViews(rows);
    }

    @AuraEnabled
    public static OrderView approve(Id orderId, String notes) {
        Field_Order__c order = forApprover(orderId);
        advanceApproval(order, notes);
        update as user order;
        return toView(requery(order.Id));
    }

    @AuraEnabled
    public static OrderView reject(Id orderId, String reason) {
        if (String.isBlank(reason)) {
            throw badRequest('Add a short reason for the rejection.');
        }
        Field_Order__c order = forApprover(orderId);
        order.Status__c = STATUS_REJECTED;
        order.Decision_Notes__c = reason.trim();
        order.Current_Approver__c = null;
        update as user order;
        return toView(requery(order.Id));
    }

    @AuraEnabled
    public static OrderView markGoodsIssued(Id orderId) {
        Field_Order__c order = requery(orderId);
        if (order.Status__c != STATUS_APPROVED) {
            throw badRequest('Goods can only be issued after the order is approved.');
        }
        order.Status__c = STATUS_GOODS;
        update as user order;
        return toView(requery(order.Id));
    }

    @AuraEnabled
    public static OrderView markCollected(Id orderId) {
        Field_Order__c order = requery(orderId);
        if (order.Status__c != STATUS_GOODS) {
            throw badRequest('Mark goods issued before collection.');
        }
        order.Status__c = STATUS_COLLECTED;
        update as user order;
        return toView(requery(order.Id));
    }

    @AuraEnabled
    public static OrderView markSettled(Id orderId) {
        Field_Order__c order = requery(orderId);
        if (order.Status__c != STATUS_COLLECTED) {
            throw badRequest('Settle only after collection.');
        }
        order.Status__c = STATUS_SETTLED;
        order.Current_Approver__c = null;
        update as user order;
        return toView(requery(order.Id));
    }

    /**
     * E5-01: every step has a named approver. DM and NAM come from the manager chain. BU is
     * the NAM's manager, or the configured BU approver when the chain stops. Yasser and
     * Finance always come from Field_Order_Approver__mdt. A step with no named approver
     * waits (Current_Approver__c blank) until SFE names one; no other manager can approve it.
     */
    private static void advanceApproval(Field_Order__c order, String notes) {
        if (String.isNotBlank(notes)) {
            order.Decision_Notes__c = notes;
        }
        String status = order.Status__c;
        if (status == STATUS_DM) {
            Id nam = managerOf(order.Current_Approver__c);
            if (nam != null) {
                order.Status__c = STATUS_NAM;
                order.Current_Approver__c = nam;
            } else {
                order.Status__c = STATUS_BU;
                order.Current_Approver__c = configuredApprover(STEP_BU);
            }
        } else if (status == STATUS_NAM) {
            Id bu = managerOf(order.Current_Approver__c);
            order.Status__c = STATUS_BU;
            order.Current_Approver__c = bu != null ? bu : configuredApprover(STEP_BU);
        } else if (status == STATUS_BU) {
            order.Status__c = STATUS_YASSER;
            order.Current_Approver__c = configuredApprover(STEP_YASSER);
        } else if (status == STATUS_YASSER) {
            order.Status__c = STATUS_FINANCE;
            order.Current_Approver__c = configuredApprover(STEP_FINANCE);
        } else if (status == STATUS_FINANCE) {
            order.Status__c = STATUS_APPROVED;
            order.Current_Approver__c = null;
        } else {
            throw badRequest('This order is not waiting on an approval step.');
        }
    }

    /** Only the named approver of the current step (or a System Administrator) may decide. */
    private static Field_Order__c forApprover(Id orderId) {
        Field_Order__c order = requery(orderId);
        if (order == null) {
            throw badRequest('Order not found.');
        }
        if (!APPROVAL_STEPS.contains(order.Status__c)) {
            throw badRequest('This order is not waiting on an approval step.');
        }
        Id me = UserInfo.getUserId();
        if (order.Current_Approver__c == me || isSystemAdmin()) {
            return order;
        }
        if (order.Current_Approver__c == null) {
            Id named = configuredApprover(stepForStatus(order.Status__c));
            if (named == me) {
                order.Current_Approver__c = me;
                return order;
            }
            throw badRequest(
                'No approver is named for the ' + order.Status__c.removeStart('Pending ') +
                ' step yet. Ask SFE to set one in Field Order Approvers.'
            );
        }
        throw badRequest('Only the current approver can decide on this order.');
    }

    private static final String STEP_BU = 'BU';
    private static final String STEP_YASSER = 'Yasser';
    private static final String STEP_FINANCE = 'Finance';
    private static final Set<String> APPROVAL_STEPS = new Set<String>{
        STATUS_DM, STATUS_NAM, STATUS_BU, STATUS_YASSER, STATUS_FINANCE
    };

    /** Test hook: step → approver user id, used instead of the custom metadata records. */
    @TestVisible
    private static Map<String, Id> approverOverrideByStep;
    private static Map<String, Id> approverByStepCache;

    private static String stepForStatus(String status) {
        if (status == STATUS_BU) {
            return STEP_BU;
        }
        if (status == STATUS_YASSER) {
            return STEP_YASSER;
        }
        if (status == STATUS_FINANCE) {
            return STEP_FINANCE;
        }
        return null;
    }

    private static Map<String, Id> approverByStep() {
        if (approverOverrideByStep != null) {
            return approverOverrideByStep;
        }
        if (approverByStepCache == null) {
            approverByStepCache = new Map<String, Id>();
            Map<String, String> usernameByStep = new Map<String, String>();
            for (Field_Order_Approver__mdt row : Field_Order_Approver__mdt.getAll().values()) {
                if (String.isNotBlank(row.Step__c) && String.isNotBlank(row.Approver_Username__c)) {
                    usernameByStep.put(row.Step__c, row.Approver_Username__c.trim());
                }
            }
            if (!usernameByStep.isEmpty()) {
                Map<String, Id> idByUsername = new Map<String, Id>();
                for (User u : [
                    SELECT Id, Username
                    FROM User
                    WHERE Username IN :usernameByStep.values() AND IsActive = TRUE
                    WITH SYSTEM_MODE
                ]) {
                    idByUsername.put(u.Username.toLowerCase(), u.Id);
                }
                for (String step : usernameByStep.keySet()) {
                    Id userId = idByUsername.get(usernameByStep.get(step).toLowerCase());
                    if (userId != null) {
                        approverByStepCache.put(step, userId);
                    }
                }
            }
        }
        return approverByStepCache;
    }

    private static Id configuredApprover(String step) {
        return step == null ? null : approverByStep().get(step);
    }

    /** Unassigned step statuses the user is the configured approver for (approval queue). */
    private static Set<String> configuredStepsFor(Id userId) {
        Set<String> statuses = new Set<String>();
        Map<String, Id> byStep = approverByStep();
        if (byStep.get(STEP_BU) == userId) {
            statuses.add(STATUS_BU);
        }
        if (byStep.get(STEP_YASSER) == userId) {
            statuses.add(STATUS_YASSER);
        }
        if (byStep.get(STEP_FINANCE) == userId) {
            statuses.add(STATUS_FINANCE);
        }
        return statuses;
    }

    private static Id managerOf(Id userId) {
        if (userId == null) {
            return null;
        }
        List<User> users = [SELECT ManagerId FROM User WHERE Id = :userId LIMIT 1];
        return users.isEmpty() ? null : users[0].ManagerId;
    }

    private static Id currentUserManagerId() {
        return managerOf(UserInfo.getUserId());
    }

    private static Boolean isSystemAdmin() {
        List<Profile> profiles = [
            SELECT Id FROM Profile WHERE Id = :UserInfo.getProfileId() AND Name = 'System Administrator' LIMIT 1
        ];
        return !profiles.isEmpty();
    }

    private static List<OptionRow> loadProducts(Id visitId) {
        List<OptionRow> options = new List<OptionRow>();
        if (visitId != null) {
            try {
                for (VisitCallReportService.TerritoryProductOption product :
                     VisitCallReportService.getTerritoryProducts(visitId)) {
                    if (product.productId == null) {
                        continue;
                    }
                    options.add(productOption(product.productName, String.valueOf(product.productId), null, null));
                }
            } catch (Exception ignore) {
                // fall through
            }
        }
        if (options.isEmpty()) {
            for (Product2 product : [
                SELECT Id, Name, Product_Type__c, Product_Image_URL__c
                FROM Product2
                WHERE IsActive = true
                WITH USER_MODE
                ORDER BY Name
                LIMIT 50
            ]) {
                options.add(
                    productOption(
                        product.Name,
                        String.valueOf(product.Id),
                        product.Product_Type__c,
                        product.Product_Image_URL__c
                    )
                );
            }
        }
        return options;
    }

    private static void applyDefaultAccount(CreateContext ctx, Account account) {
        if (ctx == null || account == null) {
            return;
        }
        FieldAccountSearch.Hit hit = FieldAccountSearch.fromAccount(account, null, null, null);
        ctx.defaultAccountName = hit.accountName;
        ctx.defaultRecordTypeLabel = hit.recordTypeLabel;
        ctx.defaultIconName = hit.iconName;
    }

    private static List<FieldAccountSearch.Hit> loadPharmacyHints() {
        List<FieldAccountSearch.Hit> hints = new List<FieldAccountSearch.Hit>();
        Set<Id> seen = new Set<Id>();
        for (Visit__c visit : [
            SELECT Id, Name, Account__c, Account__r.Name, Account__r.RecordType.Name,
                   Account__r.RecordType.DeveloperName
            FROM Visit__c
            WHERE Assigned_To__c = :UserInfo.getUserId()
              AND Account__c != null
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 20
        ]) {
            if (visit.Account__r == null || seen.contains(visit.Account__c)) {
                continue;
            }
            seen.add(visit.Account__c);
            hints.add(FieldAccountSearch.fromAccount(visit.Account__r, visit.Id, visit.Name, 'Recent'));
            if (hints.size() >= 8) {
                break;
            }
        }
        return hints;
    }

    private static Field_Order__c requery(Id orderId) {
        List<Field_Order__c> rows = [
            SELECT Id, Name, Account__c, Account__r.Name, Visit__c, Order_Type__c, Distributor_Name__c,
                   Branch_Name__c, Status__c, Total_Quantity__c, Discount_Percent__c, FOC__c, Notes__c,
                   Source__c, Skip_Full_Approval__c, Requested_By__c, Requested_By__r.Name,
                   Current_Approver__c, Current_Approver__r.Name, Decision_Notes__c, Submitted_Date__c
            FROM Field_Order__c
            WHERE Id = :orderId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static List<OrderView> toViews(List<Field_Order__c> rows) {
        List<OrderView> views = new List<OrderView>();
        for (Field_Order__c row : rows) {
            views.add(toView(row));
        }
        return views;
    }

    private static OrderView toView(Field_Order__c row) {
        OrderView view = new OrderView();
        view.id = row.Id;
        view.name = row.Name;
        view.accountId = row.Account__c;
        view.accountName = row.Account__r != null ? row.Account__r.Name : null;
        view.visitId = row.Visit__c;
        view.orderType = row.Order_Type__c;
        view.distributorName = row.Distributor_Name__c;
        view.branchName = row.Branch_Name__c;
        view.status = row.Status__c;
        view.statusLabel = row.Status__c;
        view.totalQuantity = row.Total_Quantity__c;
        view.discountPercent = row.Discount_Percent__c;
        view.foc = row.FOC__c == true;
        view.notes = row.Notes__c;
        view.source = row.Source__c;
        view.skipFullApproval = row.Skip_Full_Approval__c == true;
        view.requestedByName = row.Requested_By__r != null ? row.Requested_By__r.Name : null;
        view.currentApproverName = row.Current_Approver__r != null ? row.Current_Approver__r.Name : null;
        Boolean isOpenStep = APPROVAL_STEPS.contains(row.Status__c);
        Boolean isApprover =
            isOpenStep &&
            (row.Current_Approver__c == UserInfo.getUserId() ||
            isSystemAdmin() ||
            (row.Current_Approver__c == null &&
            configuredApprover(stepForStatus(row.Status__c)) == UserInfo.getUserId()));
        view.canApprove = isApprover;
        view.canReject = isApprover;
        view.canAdvanceFulfillment =
            isSystemAdmin() ||
            row.Requested_By__c == UserInfo.getUserId() ||
            isApprover;
        view.routingHint = routingHint(row);
        view.lines = loadLines(row.Id);
        return view;
    }

    private static String routingHint(Field_Order__c row) {
        if (APPROVAL_STEPS.contains(row.Status__c) && row.Current_Approver__c == null) {
            return 'Waiting for SFE to name the ' + row.Status__c.removeStart('Pending ') + ' approver.';
        }
        if (row.Skip_Full_Approval__c == true) {
            return '10 units or fewer. Finance reviews this next.';
        }
        if (row.Total_Quantity__c != null && row.Total_Quantity__c > QTY_FORCE_DISTRIBUTOR) {
            return 'Qty > 200: Distributor order required.';
        }
        return 'Waiting on the next approver.';
    }

    private static List<LineView> loadLines(Id orderId) {
        List<LineView> lines = new List<LineView>();
        for (Field_Order_Line__c line : [
            SELECT Id, Product2__c, Product2__r.Name, Quantity__c, Discount_Percent__c, FOC__c, Notes__c
            FROM Field_Order_Line__c
            WHERE Field_Order__c = :orderId
            WITH USER_MODE
            ORDER BY Display_Order__c ASC NULLS LAST
        ]) {
            LineView row = new LineView();
            row.id = line.Id;
            row.productId = line.Product2__c;
            row.productName = line.Product2__r != null ? line.Product2__r.Name : null;
            row.quantity = line.Quantity__c;
            row.discountPercent = line.Discount_Percent__c;
            row.foc = line.FOC__c == true;
            row.notes = line.Notes__c;
            lines.add(row);
        }
        return lines;
    }

    private static OptionRow option(String label, String value) {
        OptionRow row = new OptionRow();
        row.label = label;
        row.value = value;
        return row;
    }

    private static OptionRow productOption(String label, String value, String productType, String imageUrl) {
        OptionRow row = new OptionRow();
        row.label = label;
        row.value = value;
        row.iconName = productIcon(productType);
        row.imageUrl = imageUrl;
        row.subtitle = productType;
        return row;
    }

    private static String productIcon(String productType) {
        if (productType == 'Sample') {
            return 'standard:medication';
        }
        if (productType == 'Detail') {
            return 'standard:article';
        }
        if (productType == 'Brand Reminder') {
            return 'standard:reward';
        }
        return 'standard:product';
    }

    private static void sendFocSampleRequests(Field_Order__c order, List<LineInput> lines) {
        Map<String, Boolean> features = FieldAppFeatureController.getEnabledFeatureMap();
        if (features.get('requests.enabled') == false || features.get('requests.type.sample') == false) {
            return;
        }
        List<LineInput> focLines = new List<LineInput>();
        Set<Id> productIds = new Set<Id>();
        for (LineInput line : lines) {
            if (line != null && line.foc == true && line.productId != null) {
                focLines.add(line);
                productIds.add(line.productId);
            }
        }
        if (focLines.isEmpty()) {
            return;
        }
        Map<Id, Product2> products = new Map<Id, Product2>([
            SELECT Id, Name FROM Product2 WHERE Id IN :productIds WITH USER_MODE
        ]);
        Id managerId = currentUserManagerId();
        List<Field_Request__c> requests = new List<Field_Request__c>();
        for (LineInput line : focLines) {
            String productName = products.containsKey(line.productId) ? products.get(line.productId).Name : 'this product';
            Field_Request__c request = new Field_Request__c(
                Account__c = order.Account__c,
                Visit__c = order.Visit__c,
                Product__c = line.productId,
                Kind__c = 'Field',
                Request_Type__c = 'Sample',
                Urgency__c = 'Normal',
                Quantity__c = line.quantity,
                Summary__c = 'FOC sample: ' + productName + ' × ' + String.valueOf(line.quantity) + '.',
                Source__c = order.Source__c,
                Requested_By__c = UserInfo.getUserId(),
                Manager__c = managerId,
                Submitted_Date__c = Datetime.now(),
                Status__c = 'With Manager'
            );
            if (managerId != null) {
                request.OwnerId = managerId;
            }
            requests.add(request);
        }
        insert as user requests;
    }

    private static Integer normalizeLimit(Integer limitSize, Integer fallback) {
        if (limitSize == null || limitSize < 1) {
            return fallback;
        }
        return Math.min(limitSize, 200);
    }

    private static AuraHandledException badRequest(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}
