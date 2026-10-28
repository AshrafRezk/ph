/**
 * Geometry for brick regions stored on Brick__c.Boundary_GeoJSON__c as a GeoJSON Polygon or
 * MultiPolygon in [longitude, latitude] order.
 *
 * Distances and areas use a local flat-earth projection around the point or ring, which is accurate
 * to well under 1% at brick scale (a few hundred metres to ~200 km).
 */
public inherited sharing class BrickGeometry {
    public class GeometryException extends Exception {
    }

    public static final Integer MAX_VERTICES = 5000;

    private static final Double METERS_PER_DEG_LAT = 110574;
    private static final Double METERS_PER_DEG_LNG_AT_EQUATOR = 111320;
    private static final Double DEG_TO_RAD = Math.PI / 180;
    private static final Double ZERO = 0;
    private static final Double ONE = 1;
    private static final Double DEGENERATE_AREA = 0.00000000000001;

    // Egypt with a margin. Anything outside is almost always swapped [lat, lng] or a typo.
    private static final Double MIN_LAT = 20.0;
    private static final Double MAX_LAT = 33.0;
    private static final Double MIN_LNG = 24.0;
    private static final Double MAX_LNG = 38.0;

    /** One outline, stored open (the closing point is not repeated). */
    public class Ring {
        public List<Double> xs = new List<Double>();
        public List<Double> ys = new List<Double>();

        public Integer size() {
            return xs.size();
        }
    }

    /** Polygons of a region; each polygon is its outer ring followed by any holes. */
    public class Shape {
        public List<List<Ring>> polygons = new List<List<Ring>>();
        public Double minX;
        public Double minY;
        public Double maxX;
        public Double maxY;
        public Integer vertexCount = 0;

        public Boolean boxContains(Double x, Double y, Double padDeg) {
            return x >= minX - padDeg && x <= maxX + padDeg && y >= minY - padDeg && y <= maxY + padDeg;
        }
    }

    public static Shape parse(String geoJson) {
        if (String.isBlank(geoJson)) {
            throw new GeometryException('The region is empty.');
        }
        Object root;
        try {
            root = JSON.deserializeUntyped(geoJson);
        } catch (Exception e) {
            throw new GeometryException('The region is not valid GeoJSON.');
        }
        Shape shape = new Shape();
        addGeometry(shape, root);
        if (shape.polygons.isEmpty()) {
            throw new GeometryException('The region has no polygon.');
        }
        return shape;
    }

    public static Boolean contains(Shape shape, Double x, Double y) {
        if (shape == null || !shape.boxContains(x, y, ZERO)) {
            return false;
        }
        for (List<Ring> polygon : shape.polygons) {
            if (!inRing(polygon[0], x, y)) {
                continue;
            }
            Boolean inHole = false;
            for (Integer h = 1; h < polygon.size(); h++) {
                if (inRing(polygon[h], x, y)) {
                    inHole = true;
                    break;
                }
            }
            if (!inHole) {
                return true;
            }
        }
        return false;
    }

    /** Shortest distance in metres from the point to any edge of the region (inside or outside). */
    public static Double distanceToEdgeMeters(Shape shape, Double x, Double y) {
        Double kx = METERS_PER_DEG_LNG_AT_EQUATOR * Math.cos(y * DEG_TO_RAD);
        Double ky = METERS_PER_DEG_LAT;
        Double best;
        for (List<Ring> polygon : shape.polygons) {
            for (Ring ring : polygon) {
                Integer n = ring.size();
                for (Integer i = 0; i < n; i++) {
                    Integer k = i == n - 1 ? 0 : i + 1;
                    Double ax = (ring.xs[i] - x) * kx;
                    Double ay = (ring.ys[i] - y) * ky;
                    Double dx = (ring.xs[k] - x) * kx - ax;
                    Double dy = (ring.ys[k] - y) * ky - ay;
                    Double len2 = dx * dx + dy * dy;
                    Double t = len2 == 0 ? ZERO : -(ax * dx + ay * dy) / len2;
                    t = Math.max(ZERO, Math.min(ONE, t));
                    Double px = ax + t * dx;
                    Double py = ay + t * dy;
                    Double d = Math.sqrt(px * px + py * py);
                    if (best == null || d < best) {
                        best = d;
                    }
                }
            }
        }
        return best;
    }

    public static Double areaKm2(Shape shape) {
        Double total = 0;
        for (List<Ring> polygon : shape.polygons) {
            Double area = ringAreaKm2(polygon[0]);
            for (Integer h = 1; h < polygon.size(); h++) {
                area -= ringAreaKm2(polygon[h]);
            }
            total += Math.max(ZERO, area);
        }
        return total;
    }

    /** Area-weighted centre of the largest polygon's outline, as [longitude, latitude]. */
    public static List<Double> center(Shape shape) {
        Ring largest;
        Double largestArea = -1;
        for (List<Ring> polygon : shape.polygons) {
            Double area = ringAreaKm2(polygon[0]);
            if (area > largestArea) {
                largestArea = area;
                largest = polygon[0];
            }
        }
        Double ox = largest.xs[0];
        Double oy = largest.ys[0];
        Double twiceArea = 0;
        Double cx = 0;
        Double cy = 0;
        Integer n = largest.size();
        for (Integer i = 0; i < n; i++) {
            Integer k = i == n - 1 ? 0 : i + 1;
            Double x1 = largest.xs[i] - ox;
            Double y1 = largest.ys[i] - oy;
            Double x2 = largest.xs[k] - ox;
            Double y2 = largest.ys[k] - oy;
            Double cross = x1 * y2 - x2 * y1;
            twiceArea += cross;
            cx += (x1 + x2) * cross;
            cy += (y1 + y2) * cross;
        }
        if (Math.abs(twiceArea) < DEGENERATE_AREA) {
            return new List<Double>{ (shape.minX + shape.maxX) / 2, (shape.minY + shape.maxY) / 2 };
        }
        return new List<Double>{ ox + cx / (3 * twiceArea), oy + cy / (3 * twiceArea) };
    }

    /** Canonical GeoJSON: closed rings, 6 decimals (about 10 cm), Polygon for one part, MultiPolygon for more. */
    public static String toGeoJson(Shape shape) {
        List<Object> polygons = new List<Object>();
        for (List<Ring> polygon : shape.polygons) {
            List<Object> rings = new List<Object>();
            for (Ring ring : polygon) {
                List<Object> positions = new List<Object>();
                for (Integer i = 0; i < ring.size(); i++) {
                    positions.add(new List<Object>{ round6(ring.xs[i]), round6(ring.ys[i]) });
                }
                positions.add(new List<Object>{ round6(ring.xs[0]), round6(ring.ys[0]) });
                rings.add(positions);
            }
            polygons.add(rings);
        }
        Map<String, Object> geometry = new Map<String, Object>();
        if (polygons.size() == 1) {
            geometry.put('type', 'Polygon');
            geometry.put('coordinates', polygons[0]);
        } else {
            geometry.put('type', 'MultiPolygon');
            geometry.put('coordinates', polygons);
        }
        return JSON.serialize(geometry);
    }

    /** Fills the derived region fields on a brick from its Boundary_GeoJSON__c (or clears them). */
    public static void applyDerivedFields(Brick__c brick) {
        if (String.isBlank(brick.Boundary_GeoJSON__c)) {
            brick.Boundary_GeoJSON__c = null;
            brick.Center_Latitude__c = null;
            brick.Center_Longitude__c = null;
            brick.Min_Latitude__c = null;
            brick.Max_Latitude__c = null;
            brick.Min_Longitude__c = null;
            brick.Max_Longitude__c = null;
            brick.Boundary_Area_Km2__c = null;
            brick.Boundary_Source__c = null;
            brick.Boundary_Updated__c = System.now();
            return;
        }
        Shape shape = parse(brick.Boundary_GeoJSON__c);
        List<Double> c = center(shape);
        brick.Boundary_GeoJSON__c = toGeoJson(shape);
        brick.Center_Longitude__c = round7(c[0]);
        brick.Center_Latitude__c = round7(c[1]);
        brick.Min_Latitude__c = round7(shape.minY);
        brick.Max_Latitude__c = round7(shape.maxY);
        brick.Min_Longitude__c = round7(shape.minX);
        brick.Max_Longitude__c = round7(shape.maxX);
        brick.Boundary_Area_Km2__c = Decimal.valueOf(areaKm2(shape)).setScale(3);
        if (String.isBlank(brick.Boundary_Source__c)) {
            brick.Boundary_Source__c = 'Imported';
        }
        brick.Boundary_Updated__c = System.now();
    }

    private static void addGeometry(Shape shape, Object node) {
        if (!(node instanceof Map<String, Object>)) {
            throw new GeometryException('The region is not valid GeoJSON.');
        }
        Map<String, Object> m = (Map<String, Object>) node;
        String type = String.valueOf(m.get('type'));
        if (type == 'FeatureCollection') {
            for (Object feature : asList(m.get('features'))) {
                addGeometry(shape, feature);
            }
        } else if (type == 'Feature') {
            addGeometry(shape, m.get('geometry'));
        } else if (type == 'Polygon') {
            addPolygon(shape, asList(m.get('coordinates')));
        } else if (type == 'MultiPolygon') {
            for (Object polygon : asList(m.get('coordinates'))) {
                addPolygon(shape, asList(polygon));
            }
        } else {
            throw new GeometryException('Only Polygon and MultiPolygon regions are supported, not ' + type + '.');
        }
    }

    private static void addPolygon(Shape shape, List<Object> rings) {
        if (rings.isEmpty()) {
            throw new GeometryException('A region polygon has no outline.');
        }
        List<Ring> polygon = new List<Ring>();
        for (Object raw : rings) {
            Ring ring = toRing(asList(raw));
            shape.vertexCount += ring.size();
            if (shape.vertexCount > MAX_VERTICES) {
                throw new GeometryException('The region has more than ' + MAX_VERTICES + ' points. Simplify the outline.');
            }
            for (Integer i = 0; i < ring.size(); i++) {
                Double x = ring.xs[i];
                Double y = ring.ys[i];
                shape.minX = shape.minX == null ? x : Math.min(shape.minX, x);
                shape.maxX = shape.maxX == null ? x : Math.max(shape.maxX, x);
                shape.minY = shape.minY == null ? y : Math.min(shape.minY, y);
                shape.maxY = shape.maxY == null ? y : Math.max(shape.maxY, y);
            }
            polygon.add(ring);
        }
        shape.polygons.add(polygon);
    }

    private static Ring toRing(List<Object> positions) {
        Ring ring = new Ring();
        for (Object raw : positions) {
            List<Object> position = asList(raw);
            if (position.size() < 2) {
                throw new GeometryException('A region point is missing its longitude or latitude.');
            }
            Double x = toDouble(position[0]);
            Double y = toDouble(position[1]);
            if (x == null || y == null) {
                throw new GeometryException('A region point is not a number.');
            }
            if (y < MIN_LAT || y > MAX_LAT || x < MIN_LNG || x > MAX_LNG) {
                throw new GeometryException(
                    'Region point ' + y + ', ' + x + ' is outside Egypt. Coordinates must be [longitude, latitude].'
                );
            }
            Integer count = ring.size();
            if (count > 0 && ring.xs[count - 1] == x && ring.ys[count - 1] == y) {
                continue;
            }
            ring.xs.add(x);
            ring.ys.add(y);
        }
        Integer n = ring.size();
        if (n > 1 && ring.xs[0] == ring.xs[n - 1] && ring.ys[0] == ring.ys[n - 1]) {
            ring.xs.remove(n - 1);
            ring.ys.remove(n - 1);
        }
        if (ring.size() < 3) {
            throw new GeometryException('Each region outline needs at least 3 different points.');
        }
        return ring;
    }

    private static Boolean inRing(Ring ring, Double x, Double y) {
        Boolean inside = false;
        Integer n = ring.size();
        Integer j = n - 1;
        for (Integer i = 0; i < n; i++) {
            Double yi = ring.ys[i];
            Double yj = ring.ys[j];
            if ((yi > y) != (yj > y)) {
                Double xi = ring.xs[i];
                Double xj = ring.xs[j];
                if (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
                    inside = !inside;
                }
            }
            j = i;
        }
        return inside;
    }

    private static Double ringAreaKm2(Ring ring) {
        Double ox = ring.xs[0];
        Double oy = ring.ys[0];
        Double meanY = 0;
        for (Double y : ring.ys) {
            meanY += y;
        }
        meanY = meanY / ring.size();
        Double kx = METERS_PER_DEG_LNG_AT_EQUATOR * Math.cos(meanY * DEG_TO_RAD) / 1000;
        Double ky = METERS_PER_DEG_LAT / 1000;
        Double sum = 0;
        Integer n = ring.size();
        for (Integer i = 0; i < n; i++) {
            Integer k = i == n - 1 ? 0 : i + 1;
            sum += ((ring.xs[i] - ox) * kx) * ((ring.ys[k] - oy) * ky) - ((ring.xs[k] - ox) * kx) * ((ring.ys[i] - oy) * ky);
        }
        return Math.abs(sum) / 2;
    }

    private static List<Object> asList(Object o) {
        if (o instanceof List<Object>) {
            return (List<Object>) o;
        }
        throw new GeometryException('The region is not valid GeoJSON.');
    }

    private static Double toDouble(Object o) {
        if (o instanceof Decimal) {
            return ((Decimal) o).doubleValue();
        }
        if (o instanceof Double) {
            return (Double) o;
        }
        if (o instanceof Integer) {
            return Double.valueOf((Integer) o);
        }
        if (o instanceof Long) {
            return Double.valueOf((Long) o);
        }
        return null;
    }

    private static Decimal round6(Double v) {
        return Decimal.valueOf(v).setScale(6, RoundingMode.HALF_UP);
    }

    private static Decimal round7(Double v) {
        return Decimal.valueOf(v).setScale(7, RoundingMode.HALF_UP);
    }
}
