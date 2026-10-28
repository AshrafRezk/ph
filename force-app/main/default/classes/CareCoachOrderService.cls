/**
 * Orders board for Care Coach Co-pilot: orders with their line items, patient,
 * care coach and promise dates, plus the default line items for new orders.
 */
public with sharing class CareCoachOrderService {
    public static final List<String> STATUSES = new List<String>{ 'Requested', 'Approved', 'Dispatched', 'Delivered', 'Cancelled' };
    private static final Set<String> CLOSED = new Set<String>{ 'Delivered', 'Cancelled' };
    private static final Integer PER_STATUS_LIMIT = 60;

    public class ItemRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String lineNumber;
        @AuraEnabled public String name;
        @AuraEnabled public String itemType;
        @AuraEnabled public Integer quantity;
        @AuraEnabled public String unit;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public Decimal lineTotal;
    }

    public class OrderCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String orderNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String priority;
        @AuraEnabled public Date orderDate;
        @AuraEnabled public Date promisedDate;
        @AuraEnabled public Date deliveryDate;
        @AuraEnabled public String channel;
        @AuraEnabled public String pharmacy;
        @AuraEnabled public String deliveryAddress;
        @AuraEnabled public String trackingNumber;
        @AuraEnabled public String notes;
        @AuraEnabled public Id patientId;
        @AuraEnabled public String patientNumber;
        @AuraEnabled public String patientName;
        @AuraEnabled public String productName;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public Id coachId;
        @AuraEnabled public String coachName;
        @AuraEnabled public Integer lineCount = 0;
        @AuraEnabled public Integer totalUnits = 0;
        @AuraEnabled public Decimal orderTotal = 0;
        @AuraEnabled public Boolean overdue = false;
        @AuraEnabled public Integer daysToPromise;
        @AuraEnabled public List<ItemRow> items = new List<ItemRow>();
    }

    public class StatusTotal {
        @AuraEnabled public String status;
        @AuraEnabled public Integer count = 0;
        @AuraEnabled public Integer units = 0;
        @AuraEnabled public Decimal value = 0;
    }

    public class OrderBoard {
        @AuraEnabled public List<OrderCard> orders = new List<OrderCard>();
        @AuraEnabled public List<StatusTotal> totals = new List<StatusTotal>();
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Boolean masked;
        @AuraEnabled public Boolean canEdit;
        @AuraEnabled public Integer overdueCount = 0;
        @AuraEnabled public Integer dueThisWeek = 0;
    }

    /**
     * Orders placed in the last {days} days (all orders when days is blank), up to
     * PER_STATUS_LIMIT per status: open orders by promise date, closed ones newest first.
     */
    @AuraEnabled
    public static OrderBoard getOrders(String mode, String scope, Integer days) {
        Boolean masked = CareCoachAccess.isMasked(mode);
        Boolean mine = CareCoachAccess.resolveScope(scope) == CareCoachAccess.SCOPE_MINE;
        Date today = Date.today();
        Map<String, Object> binds = new Map<String, Object>{
            'me' => UserInfo.getUserId(),
            'today' => today,
            'weekEnd' => today.addDays(7),
            'closed' => CLOSED
        };
        List<String> filters = new List<String>();
        if (days != null && days > 0) {
            binds.put('since', today.addDays(-days));
            filters.add('Order_Date__c >= :since');
        }
        if (mine) {
            filters.add('Care_Coach__c = :me');
        }
        String baseWhere = filters.isEmpty() ? '' : String.join(filters, ' AND ');

        OrderBoard board = new OrderBoard();
        board.masked = masked;
        board.canEdit = !masked && CareCoachAccess.hasFullAccess();
        board.currencyCode = UserInfo.getDefaultCurrency();

        Map<String, StatusTotal> totals = new Map<String, StatusTotal>();
        for (String s : STATUSES) {
            StatusTotal t = new StatusTotal();
            t.status = s;
            totals.put(s, t);
            board.totals.add(t);
        }
        String aggWhere = baseWhere == '' ? '' : ' WHERE ' + baseWhere;
        for (AggregateResult ar : (List<AggregateResult>) Database.queryWithBinds(
            'SELECT Status__c s, COUNT(Id) c, SUM(Total_Units__c) u, SUM(Order_Total__c) v FROM Patient_Order__c' + aggWhere + ' GROUP BY Status__c',
            binds,
            AccessLevel.USER_MODE
        )) {
            StatusTotal t = totals.get((String) ar.get('s'));
            if (t == null) {
                continue;
            }
            t.count = (Integer) ar.get('c');
            t.units = ar.get('u') == null ? 0 : ((Decimal) ar.get('u')).intValue();
            t.value = ar.get('v') == null ? 0 : (Decimal) ar.get('v');
        }
        String openWhere = (baseWhere == '' ? '' : baseWhere + ' AND ') + 'Status__c NOT IN :closed';
        board.overdueCount = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Patient_Order__c WHERE ' + openWhere + ' AND Promised_Date__c < :today',
            binds,
            AccessLevel.USER_MODE
        );
        board.dueThisWeek = Database.countQueryWithBinds(
            'SELECT COUNT() FROM Patient_Order__c WHERE ' + openWhere + ' AND Promised_Date__c >= :today AND Promised_Date__c <= :weekEnd',
            binds,
            AccessLevel.USER_MODE
        );

        for (String s : STATUSES) {
            binds.put('status', s);
            String order = CLOSED.contains(s) ? 'Order_Date__c DESC, Name DESC' : 'Promised_Date__c ASC NULLS LAST, Name ASC';
            String q = selectClause(masked) + ' WHERE ' + (baseWhere == '' ? '' : baseWhere + ' AND ') + 'Status__c = :status ORDER BY ' + order + ' LIMIT ' + PER_STATUS_LIMIT;
            for (Patient_Order__c o : (List<Patient_Order__c>) Database.queryWithBinds(q, binds, AccessLevel.USER_MODE)) {
                board.orders.add(toCard(o, masked));
            }
        }
        return board;
    }

    @AuraEnabled
    public static OrderCard updateOrderStatus(Id orderId, String status, String trackingNumber) {
        CareCoachAccess.assertCanEdit();
        if (orderId == null || !STATUSES.contains(status)) {
            throw CareCoachAccess.fail('Choose a valid order status.');
        }
        Patient_Order__c o = new Patient_Order__c(Id = orderId, Status__c = status);
        if (String.isNotBlank(trackingNumber)) {
            o.Tracking_Number__c = trackingNumber.trim();
        }
        if (status == 'Delivered') {
            o.Delivery_Date__c = Date.today();
        } else if (status != 'Cancelled') {
            o.Delivery_Date__c = null;
        }
        update as user o;
        return getOrder(orderId, CareCoachAccess.MODE_PSP);
    }

    public static OrderCard getOrder(Id orderId, String mode) {
        Boolean masked = CareCoachAccess.isMasked(mode);
        List<Patient_Order__c> rows = (List<Patient_Order__c>) Database.queryWithBinds(
            selectClause(masked) + ' WHERE Id = :orderId',
            new Map<String, Object>{ 'orderId' => orderId },
            AccessLevel.USER_MODE
        );
        if (rows.isEmpty()) {
            throw CareCoachAccess.fail('Order not found.');
        }
        return toCard(rows[0], masked);
    }

    private static String selectClause(Boolean masked) {
        String fields =
            'Id, Name, Status__c, Priority__c, Order_Date__c, Promised_Date__c, Delivery_Date__c, Channel__c, Pharmacy__c, ' +
            'Tracking_Number__c, Notes__c, Quantity__c, Line_Count__c, Total_Units__c, Order_Total__c, ' +
            'Patient__c, Patient__r.Name, Patient__r.Initials__c, Product__r.Name, Product__r.Therapy_Area__c, ' +
            'Care_Coach__c, Care_Coach__r.Name';
        if (!masked) {
            fields += ', Patient__r.Full_Name__c, Delivery_Address__c';
        }
        return 'SELECT ' + fields +
            ', (SELECT Id, Name, Item_Name__c, Item_Type__c, Product__r.Name, Quantity__c, Unit__c, Unit_Price__c, Line_Total__c' +
            ' FROM Order_Items__r ORDER BY Sort_Order__c ASC NULLS LAST, Name ASC)' +
            ' FROM Patient_Order__c';
    }

    private static OrderCard toCard(Patient_Order__c o, Boolean masked) {
        OrderCard c = new OrderCard();
        c.id = o.Id;
        c.orderNumber = o.Name;
        c.status = o.Status__c;
        c.priority = String.isBlank(o.Priority__c) ? 'Standard' : o.Priority__c;
        c.orderDate = o.Order_Date__c;
        c.promisedDate = o.Promised_Date__c;
        c.deliveryDate = o.Delivery_Date__c;
        c.channel = o.Channel__c;
        c.pharmacy = o.Pharmacy__c;
        c.trackingNumber = o.Tracking_Number__c;
        c.patientId = o.Patient__c;
        c.patientNumber = o.Patient__r?.Name;
        c.productName = o.Product__r?.Name;
        c.therapyArea = o.Product__r?.Therapy_Area__c;
        c.coachId = o.Care_Coach__c;
        c.coachName = o.Care_Coach__r?.Name;
        String initials = o.Patient__r?.Initials__c;
        if (masked) {
            c.patientName = String.isBlank(initials) ? c.patientNumber : initials + ' · ' + c.patientNumber;
            c.notes = CareCoachAccess.redact(o.Notes__c);
        } else {
            String full = o.Patient__r?.Full_Name__c;
            c.patientName = String.isBlank(full) ? c.patientNumber : full;
            c.notes = o.Notes__c;
            c.deliveryAddress = o.Delivery_Address__c;
        }
        for (Patient_Order_Item__c i : o.Order_Items__r) {
            ItemRow r = new ItemRow();
            r.id = i.Id;
            r.lineNumber = i.Name;
            r.name = String.isBlank(i.Item_Name__c) ? i.Product__r?.Name : i.Item_Name__c;
            r.itemType = i.Item_Type__c;
            r.quantity = i.Quantity__c == null ? 0 : i.Quantity__c.intValue();
            r.unit = i.Unit__c;
            r.unitPrice = i.Unit_Price__c;
            r.lineTotal = i.Line_Total__c;
            c.items.add(r);
        }
        c.lineCount = o.Line_Count__c == null ? c.items.size() : o.Line_Count__c.intValue();
        c.totalUnits = o.Total_Units__c == null ? 0 : o.Total_Units__c.intValue();
        c.orderTotal = o.Order_Total__c == null ? 0 : o.Order_Total__c;
        if (c.items.isEmpty() && o.Quantity__c != null) {
            c.totalUnits = o.Quantity__c.intValue();
        }
        if (o.Promised_Date__c != null && !CLOSED.contains(o.Status__c)) {
            c.daysToPromise = Date.today().daysBetween(o.Promised_Date__c);
            c.overdue = c.daysToPromise < 0;
        }
        return c;
    }

    // ------------------------------------------------------------ defaults

    private class Supply {
        String name;
        String itemType;
        Integer quantity;
        String unit;
        Decimal price;
        Supply(String name, String itemType, Integer quantity, String unit, Decimal price) {
            this.name = name;
            this.itemType = itemType;
            this.quantity = quantity;
            this.unit = unit;
            this.price = price;
        }
    }

    private static final Map<String, String> MEDICINE_UNITS = new Map<String, String>{
        'PSP-REBIF' => 'cartridge pack',
        'PSP-SAIZEN' => 'cartridge',
        'PSP-MAVENCLAD' => 'tablet pack',
        'PSP-ERBITUX' => 'vial'
    };

    private static final Map<String, Decimal> MEDICINE_PRICES = new Map<String, Decimal>{
        'PSP-REBIF' => 1450,
        'PSP-SAIZEN' => 620,
        'PSP-MAVENCLAD' => 5200,
        'PSP-ERBITUX' => 780
    };

    private static List<Supply> suppliesFor(String code, String channel) {
        List<Supply> out = new List<Supply>();
        if (code == 'PSP-REBIF') {
            out.add(new Supply('RebiSmart autoinjector needles 29G', 'Consumables', 1, 'box', 18));
            out.add(new Supply('Alcohol swabs', 'Consumables', 2, 'pack', 3));
            out.add(new Supply('Sharps disposal container', 'Consumables', 1, 'unit', 6));
        } else if (code == 'PSP-SAIZEN') {
            out.add(new Supply('easypod needles 31G', 'Consumables', 1, 'box', 15));
            out.add(new Supply('Insulated cool bag', 'Cold Chain', 1, 'unit', 9));
            out.add(new Supply('Injection diary', 'Patient Material', 1, 'booklet', 0));
        } else if (code == 'PSP-MAVENCLAD') {
            out.add(new Supply('Treatment course diary', 'Patient Material', 1, 'booklet', 0));
        } else if (code == 'PSP-ERBITUX') {
            out.add(new Supply('IV infusion set with 0.2 µm filter', 'Device', 1, 'set', 25));
            out.add(new Supply('Premedication pack (antihistamine)', 'Medicine', 1, 'pack', 12));
            if (channel != 'Hospital') {
                out.add(new Supply('Validated cold-chain shipper', 'Cold Chain', 1, 'box', 40));
            }
        }
        return out;
    }

    public static Date promisedDate(Date orderDate, String channel) {
        if (orderDate == null) {
            return null;
        }
        Integer lead = channel == 'Hospital' ? 5 : channel == 'Pharmacy Pick-up' ? 2 : 3;
        return orderDate.addDays(lead);
    }

    /** Promise date and priority for orders that don't have them yet. */
    public static void applyDefaults(Patient_Order__c o) {
        if (o.Promised_Date__c == null) {
            o.Promised_Date__c = promisedDate(o.Order_Date__c, o.Channel__c);
        }
        if (String.isBlank(o.Priority__c)) {
            o.Priority__c = 'Standard';
        }
    }

    public static List<Patient_Order_Item__c> defaultItems(Patient_Order__c o, Product2 p) {
        String code = p?.ProductCode;
        List<Patient_Order_Item__c> items = new List<Patient_Order_Item__c>();
        String medicine = p == null ? 'PSP medicine' : (String.isBlank(p.Strength__c) ? p.Name : p.Name + ' ' + p.Strength__c);
        items.add(new Patient_Order_Item__c(
            Order__c = o.Id,
            Product__c = p?.Id,
            Item_Name__c = medicine.left(120),
            Item_Type__c = 'Medicine',
            Quantity__c = o.Quantity__c == null || o.Quantity__c < 1 ? 1 : o.Quantity__c,
            Unit__c = MEDICINE_UNITS.containsKey(code) ? MEDICINE_UNITS.get(code) : 'pack',
            Unit_Price__c = MEDICINE_PRICES.get(code),
            Sort_Order__c = 1
        ));
        Integer position = 2;
        for (Supply s : suppliesFor(code, o.Channel__c)) {
            items.add(new Patient_Order_Item__c(
                Order__c = o.Id,
                Item_Name__c = s.name,
                Item_Type__c = s.itemType,
                Quantity__c = s.quantity,
                Unit__c = s.unit,
                Unit_Price__c = s.price,
                Sort_Order__c = position++
            ));
        }
        return items;
    }

    /** Builds the default line items for saved orders (their Product__c drives the medicine line). */
    public static List<Patient_Order_Item__c> defaultItems(List<Patient_Order__c> orders) {
        Set<Id> productIds = new Set<Id>();
        for (Patient_Order__c o : orders) {
            if (o.Product__c != null) {
                productIds.add(o.Product__c);
            }
        }
        Map<Id, Product2> products = new Map<Id, Product2>(
            [SELECT Id, Name, ProductCode, Strength__c FROM Product2 WHERE Id IN :productIds]
        );
        List<Patient_Order_Item__c> items = new List<Patient_Order_Item__c>();
        for (Patient_Order__c o : orders) {
            items.addAll(defaultItems(o, products.get(o.Product__c)));
        }
        return items;
    }
}