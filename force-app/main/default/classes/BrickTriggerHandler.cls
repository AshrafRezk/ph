/**
 * Keeps a brick's region box, centre and area in step with Boundary_GeoJSON__c, whether the region is
 * saved from the Bricks Manager, a data load or the API.
 */
public with sharing class BrickTriggerHandler {
    public static void deriveRegionFields(List<Brick__c> rows, Map<Id, Brick__c> oldMap) {
        for (Brick__c row : rows) {
            Brick__c old = oldMap == null ? null : oldMap.get(row.Id);
            Boolean changed = old == null
                ? String.isNotBlank(row.Boundary_GeoJSON__c)
                : row.Boundary_GeoJSON__c != old.Boundary_GeoJSON__c;
            if (!changed) {
                continue;
            }
            try {
                BrickGeometry.applyDerivedFields(row);
            } catch (BrickGeometry.GeometryException e) {
                row.Boundary_GeoJSON__c.addError(e.getMessage());
            }
        }
    }
}
