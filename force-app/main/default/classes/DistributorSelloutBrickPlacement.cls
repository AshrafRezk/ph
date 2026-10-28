/**
 * Puts each distributor client (Distributor_Sellout_Alias__c) in the 702 and 148 brick whose region
 * contains its geocoded location. Runs whenever the location or its precision changes.
 */
public with sharing class DistributorSelloutBrickPlacement {
    public static void apply(List<Distributor_Sellout_Alias__c> rows, Map<Id, Distributor_Sellout_Alias__c> oldMap) {
        List<Distributor_Sellout_Alias__c> moved = new List<Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c row : rows) {
            Distributor_Sellout_Alias__c old = oldMap == null ? null : oldMap.get(row.Id);
            if (
                old == null ||
                row.Latitude__c != old.Latitude__c ||
                row.Longitude__c != old.Longitude__c ||
                row.Geocode_Precision__c != old.Geocode_Precision__c
            ) {
                moved.add(row);
            }
        }
        if (!moved.isEmpty()) {
            stamp(moved);
        }
    }

    /**
     * Sets Brick_702__c, Brick_148__c and Brick_Placement__c in memory and returns the rows that changed.
     * Rows need Latitude__c, Longitude__c, Geocode_Precision__c and the three brick fields loaded.
     */
    public static final String ADDRESS_MATCH = 'Address match';

    public static List<Distributor_Sellout_Alias__c> stamp(List<Distributor_Sellout_Alias__c> rows) {
        List<BrickLocator.Point> points = new List<BrickLocator.Point>();
        for (Integer i = 0; i < rows.size(); i++) {
            Distributor_Sellout_Alias__c row = rows[i];
            points.add(
                new BrickLocator.Point(String.valueOf(i), row.Latitude__c, row.Longitude__c, row.Geocode_Precision__c)
            );
        }
        Map<String, BrickLocator.Placement> placed = BrickLocator.place(points);
        List<Distributor_Sellout_Alias__c> changed = new List<Distributor_Sellout_Alias__c>();
        for (Integer i = 0; i < rows.size(); i++) {
            Distributor_Sellout_Alias__c row = rows[i];
            BrickLocator.Placement p = placed.get(String.valueOf(i));
            // A client placed from its address keeps that brick until it gets a map location.
            if (p.status == BrickLocator.NO_LOCATION && row.Brick_Placement__c == ADDRESS_MATCH) {
                continue;
            }
            if (
                row.Brick_702__c != p.brick702Id ||
                row.Brick_148__c != p.brick148Id ||
                row.Brick_Placement__c != p.status
            ) {
                row.Brick_702__c = p.brick702Id;
                row.Brick_148__c = p.brick148Id;
                row.Brick_Placement__c = p.status;
                changed.add(row);
            }
        }
        return changed;
    }
}
