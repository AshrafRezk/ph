/**
 * Places locations in brick regions (Brick__c.Boundary_GeoJSON__c).
 *
 * - The 702 region that contains the point wins; where regions overlap, the smaller one wins.
 * - The 148 brick is the 702's parent, or the 148 region that contains the point when no 702 region does.
 * - A precise point in a small gap between regions snaps to the nearest region within NEAREST_METERS.
 * - City-level points (a town centre) count only when they sit at least CITY_INSET_METERS inside a region.
 *   Governorate-level points are never placed.
 */
public inherited sharing class BrickLocator {
    public static final Double NEAREST_METERS = 250;
    public static final Double CITY_INSET_METERS = 3000;

    public static final String IN_REGION = 'In region';
    public static final String NEAREST_REGION = 'Nearest region';
    public static final String APPROXIMATE = 'Approximate location';
    public static final String OUTSIDE = 'Outside regions';
    public static final String NO_LOCATION = 'No location';

    private static final Double CELL_DEG = 0.1;
    private static final Double PAD_DEG = 0.004;
    private static final Double NO_GAP = 0;

    public class Point {
        public String key;
        public Double latitude;
        public Double longitude;
        public String precision;

        public Point(String key, Decimal latitude, Decimal longitude, String precision) {
            this.key = key;
            this.latitude = latitude == null ? null : latitude.doubleValue();
            this.longitude = longitude == null ? null : longitude.doubleValue();
            this.precision = precision;
        }
    }

    public class Placement {
        public Id brick702Id;
        public Id brick148Id;
        public String status;

        public Placement(String status) {
            this.status = status;
        }
    }

    private class Region {
        Id id;
        String level;
        Id parentId;
        Double area;
        Double minX;
        Double minY;
        Double maxX;
        Double maxY;
        BrickGeometry.Shape shape;

        Boolean boxContains(Double x, Double y, Double pad) {
            return x >= minX - pad && x <= maxX + pad && y >= minY - pad && y <= maxY + pad;
        }
    }

    private class Match {
        Region region;
        Boolean inside;
        Double gapMeters;

        Match(Region region, Boolean inside, Double gapMeters) {
            this.region = region;
            this.inside = inside;
            this.gapMeters = gapMeters;
        }
    }

    public static Placement placeOne(Decimal latitude, Decimal longitude, String precision) {
        return place(new List<Point>{ new Point('point', latitude, longitude, precision) }).get('point');
    }

    /** Placement per Point.key. Uses two SOQL queries however many points are passed. */
    public static Map<String, Placement> place(List<Point> points) {
        Map<String, Placement> results = new Map<String, Placement>();
        List<Point> located = new List<Point>();
        Double minX;
        Double minY;
        Double maxX;
        Double maxY;
        for (Point p : points) {
            if (p == null || p.key == null) {
                continue;
            }
            if (p.latitude == null || p.longitude == null) {
                results.put(p.key, new Placement(NO_LOCATION));
                continue;
            }
            if (p.precision == 'Governorate') {
                results.put(p.key, new Placement(APPROXIMATE));
                continue;
            }
            located.add(p);
            minX = minX == null ? p.longitude : Math.min(minX, p.longitude);
            maxX = maxX == null ? p.longitude : Math.max(maxX, p.longitude);
            minY = minY == null ? p.latitude : Math.min(minY, p.latitude);
            maxY = maxY == null ? p.latitude : Math.max(maxY, p.latitude);
        }
        if (located.isEmpty()) {
            return results;
        }

        Map<String, List<Region>> grid = loadRegionGrid(minX, minY, maxX, maxY);
        Map<String, List<Region>> candidatesByKey = new Map<String, List<Region>>();
        Map<Id, Region> needShapes = new Map<Id, Region>();
        for (Point p : located) {
            List<Region> candidates = new List<Region>();
            List<Region> inCell = grid.get(cellKey(p.longitude, p.latitude));
            if (inCell != null) {
                for (Region r : inCell) {
                    if (r.boxContains(p.longitude, p.latitude, PAD_DEG)) {
                        candidates.add(r);
                        needShapes.put(r.id, r);
                    }
                }
            }
            candidatesByKey.put(p.key, candidates);
        }
        loadShapes(needShapes);

        for (Point p : located) {
            results.put(p.key, placeAmong(p, candidatesByKey.get(p.key)));
        }
        return results;
    }

    private static Placement placeAmong(Point p, List<Region> candidates) {
        Boolean cityLevel = p.precision == 'City';
        Placement result = new Placement(null);
        Match m702 = bestMatch(p, candidates, '702', cityLevel);
        if (m702 != null) {
            result.brick702Id = m702.region.id;
            result.status = m702.inside ? IN_REGION : NEAREST_REGION;
            if (m702.region.parentId != null) {
                result.brick148Id = m702.region.parentId;
                return result;
            }
        }
        Match m148 = bestMatch(p, candidates, '148', cityLevel);
        if (m148 != null) {
            result.brick148Id = m148.region.id;
            if (result.status == null) {
                result.status = m148.inside ? IN_REGION : NEAREST_REGION;
            }
        }
        if (result.status == null) {
            result.status = cityLevel ? APPROXIMATE : OUTSIDE;
        }
        return result;
    }

    private static Match bestMatch(Point p, List<Region> candidates, String level, Boolean cityLevel) {
        Double x = p.longitude;
        Double y = p.latitude;
        Match inside;
        for (Region r : candidates) {
            if (r.level != level || r.shape == null || !r.boxContains(x, y, NO_GAP)) {
                continue;
            }
            if (!BrickGeometry.contains(r.shape, x, y)) {
                continue;
            }
            if (cityLevel && BrickGeometry.distanceToEdgeMeters(r.shape, x, y) < CITY_INSET_METERS) {
                continue;
            }
            if (inside == null || r.area < inside.region.area) {
                inside = new Match(r, true, NO_GAP);
            }
        }
        if (inside != null || cityLevel) {
            return inside;
        }
        Match nearest;
        for (Region r : candidates) {
            if (r.level != level || r.shape == null) {
                continue;
            }
            Double gap = BrickGeometry.distanceToEdgeMeters(r.shape, x, y);
            if (gap <= NEAREST_METERS && (nearest == null || gap < nearest.gapMeters)) {
                nearest = new Match(r, false, gap);
            }
        }
        return nearest;
    }

    private static Map<String, List<Region>> loadRegionGrid(Double minX, Double minY, Double maxX, Double maxY) {
        Decimal qMinX = Decimal.valueOf(minX - PAD_DEG);
        Decimal qMaxX = Decimal.valueOf(maxX + PAD_DEG);
        Decimal qMinY = Decimal.valueOf(minY - PAD_DEG);
        Decimal qMaxY = Decimal.valueOf(maxY + PAD_DEG);
        Map<String, List<Region>> grid = new Map<String, List<Region>>();
        for (Brick__c b : [
            SELECT
                Id,
                Brick_Level__c,
                Parent_Brick__c,
                Boundary_Area_Km2__c,
                Min_Latitude__c,
                Max_Latitude__c,
                Min_Longitude__c,
                Max_Longitude__c
            FROM Brick__c
            WHERE
                Min_Latitude__c != NULL
                AND Is_Active__c = TRUE
                AND Brick_Level__c IN ('702', '148')
                AND Min_Latitude__c <= :qMaxY
                AND Max_Latitude__c >= :qMinY
                AND Min_Longitude__c <= :qMaxX
                AND Max_Longitude__c >= :qMinX
            WITH SYSTEM_MODE
            LIMIT 5000
        ]) {
            Region r = new Region();
            r.id = b.Id;
            r.level = b.Brick_Level__c;
            r.parentId = b.Parent_Brick__c;
            r.area = b.Boundary_Area_Km2__c == null ? 0 : b.Boundary_Area_Km2__c.doubleValue();
            r.minX = b.Min_Longitude__c.doubleValue();
            r.maxX = b.Max_Longitude__c.doubleValue();
            r.minY = b.Min_Latitude__c.doubleValue();
            r.maxY = b.Max_Latitude__c.doubleValue();
            Integer x0 = cell(r.minX - PAD_DEG);
            Integer x1 = cell(r.maxX + PAD_DEG);
            Integer y0 = cell(r.minY - PAD_DEG);
            Integer y1 = cell(r.maxY + PAD_DEG);
            for (Integer cx = x0; cx <= x1; cx++) {
                for (Integer cy = y0; cy <= y1; cy++) {
                    String key = cx + ':' + cy;
                    if (!grid.containsKey(key)) {
                        grid.put(key, new List<Region>());
                    }
                    grid.get(key).add(r);
                }
            }
        }
        return grid;
    }

    private static void loadShapes(Map<Id, Region> regions) {
        if (regions.isEmpty()) {
            return;
        }
        Set<Id> ids = regions.keySet();
        for (Brick__c b : [SELECT Id, Boundary_GeoJSON__c FROM Brick__c WHERE Id IN :ids WITH SYSTEM_MODE]) {
            try {
                regions.get(b.Id).shape = BrickGeometry.parse(b.Boundary_GeoJSON__c);
            } catch (BrickGeometry.GeometryException e) {
                // A region saved through the trigger is always valid; skip anything edited around it.
                continue;
            }
        }
    }

    private static String cellKey(Double x, Double y) {
        return cell(x) + ':' + cell(y);
    }

    private static Integer cell(Double v) {
        return Math.floor(v / CELL_DEG).intValue();
    }
}
