/**
 * Chooses the brick for distributor sales lines (Pharmacy_Sales_Withdrawal__c), in this order:
 *   1. the distributor client's location inside a brick region (Distributor_Sellout_Alias__c.Brick_702__c / Brick_148__c),
 *   2. the pharmacy account's own 702 / 148 bricks,
 *   3. an active Brick_Pharmacy__c membership.
 * Brick__c follows the Account convention: the 702 brick, else the 148 brick.
 */
public inherited sharing class SalesLineBrickResolver {
    public static final String FROM_LOCATION = 'Sales location';
    public static final String FROM_PHARMACY = 'Pharmacy brick';
    public static final String FROM_MEMBERSHIP = 'Brick membership';

    public class Bricks {
        public Id brick702;
        public Id brick148;
        public Id alignment;
        public String source;

        Bricks(Id brick702, Id brick148, Id alignment, String source) {
            this.brick702 = brick702;
            this.brick148 = brick148;
            this.alignment = alignment;
            this.source = source;
        }
    }

    private final Map<Id, Account> pharmacies = new Map<Id, Account>();
    private final Map<Id, Bricks> membershipBricks = new Map<Id, Bricks>();

    public SalesLineBrickResolver(Set<Id> pharmacyIds) {
        if (pharmacyIds == null || pharmacyIds.isEmpty()) {
            return;
        }
        for (Account a : [
            SELECT Id, Brick_702__c, Brick_148__c
            FROM Account
            WHERE Id IN :pharmacyIds
            WITH SYSTEM_MODE
        ]) {
            pharmacies.put(a.Id, a);
        }
        for (Brick_Pharmacy__c bp : [
            SELECT Pharmacy_Account__c, Brick__c, Brick__r.Brick_Level__c, Brick__r.Parent_Brick__c
            FROM Brick_Pharmacy__c
            WHERE Pharmacy_Account__c IN :pharmacyIds AND Is_Active__c = TRUE
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
        ]) {
            if (membershipBricks.containsKey(bp.Pharmacy_Account__c)) {
                continue;
            }
            String level = bp.Brick__r.Brick_Level__c;
            Id brick702 = level == '702' ? bp.Brick__c : null;
            Id brick148 = level == '702' ? bp.Brick__r.Parent_Brick__c : (level == '148' ? bp.Brick__c : null);
            membershipBricks.put(
                bp.Pharmacy_Account__c,
                new Bricks(brick702, brick148, bp.Brick__c, FROM_MEMBERSHIP)
            );
        }
    }

    /** `client` may be null; it needs Brick_702__c and Brick_148__c loaded. Returns null when nothing applies. */
    public Bricks resolve(Distributor_Sellout_Alias__c client, Id pharmacyId) {
        if (client != null && (client.Brick_702__c != null || client.Brick_148__c != null)) {
            return located(client.Brick_702__c, client.Brick_148__c, FROM_LOCATION);
        }
        Account pharmacy = pharmacyId == null ? null : pharmacies.get(pharmacyId);
        if (pharmacy != null && (pharmacy.Brick_702__c != null || pharmacy.Brick_148__c != null)) {
            return located(pharmacy.Brick_702__c, pharmacy.Brick_148__c, FROM_PHARMACY);
        }
        return pharmacyId == null ? null : membershipBricks.get(pharmacyId);
    }

    /** Writes the resolved bricks on a sales line, clearing them when `bricks` is null. True when anything changed. */
    public static Boolean applyTo(Pharmacy_Sales_Withdrawal__c line, Bricks bricks) {
        Id brick702 = bricks == null ? null : bricks.brick702;
        Id brick148 = bricks == null ? null : bricks.brick148;
        Id alignment = bricks == null ? null : bricks.alignment;
        String source = bricks == null ? null : bricks.source;
        Boolean changed =
            line.Brick_702__c != brick702 ||
            line.Brick_148__c != brick148 ||
            line.Brick__c != alignment ||
            line.Brick_Source__c != source;
        line.Brick_702__c = brick702;
        line.Brick_148__c = brick148;
        line.Brick__c = alignment;
        line.Brick_Source__c = source;
        return changed;
    }

    private static Bricks located(Id brick702, Id brick148, String source) {
        return new Bricks(brick702, brick148, brick702 != null ? brick702 : brick148, source);
    }
}
