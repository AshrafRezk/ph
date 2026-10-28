/**
 * Suggests a 702 / 148 brick region from OpenStreetMap using the IMS brick name,
 * the same way HAP scrapes OSM for a compound and then lets you edit the parcel.
 *
 * The live region is stored on Brick__c.Boundary_GeoJSON__c, not in leftover JSON files.
 * A bulk scrape (scripts/bricks/scrape_ims_regions.py) can fill every brick; this class
 * is the one-brick "Suggest from OSM" path so the user can still drag the outline.
 */
public inherited sharing class ImsBrickOutlineService {
    public class OutlineException extends Exception {
    }

    @TestVisible
    static String nominatimEndpoint = 'https://nominatim.openstreetmap.org/search';
    @TestVisible
    static String resourceName = 'imsBrickRegions';
    @TestVisible
    static Map<String, String> packOverride;

    private static final Double MIN_LAT = 20;
    private static final Double MAX_LAT = 33;
    private static final Double MIN_LNG = 24;
    private static final Double MAX_LNG = 38;
    private static final Double BOX_DEG = 0.011;

    public class Suggestion {
        @AuraEnabled public String geometry;
        @AuraEnabled public String query;
        @AuraEnabled public String displayName;
        @AuraEnabled public String source;
    }

    /** Best OSM outline for this brick's IMS name. Does not save — the map editor does. */
    public static Suggestion suggest(Id brickId) {
        if (brickId == null) {
            throw new OutlineException('Choose a brick first.');
        }
        List<Brick__c> found = [
            SELECT Id, Name, External_ID__c, Brick_Level__c
            FROM Brick__c
            WHERE Id = :brickId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (found.isEmpty()) {
            throw new OutlineException('Brick not found.');
        }
        Brick__c brick = found[0];
        Suggestion fromPack = fromResource(brick.External_ID__c);
        if (fromPack != null) {
            return fromPack;
        }
        if (brick.Brick_Level__c == '148') {
            throw new OutlineException('A 148 region is the outline of its 702 IMS bricks. Generate those first, then use Outline its 702 bricks.');
        }
        return fromNominatim(brick.Name);
    }

    /** Applies the scraped IMS pack to bricks that still have no region (or all, when overwrite). */
    public static Integer applyPack(Boolean overwrite) {
        Map<String, String> pack = loadPack();
        if (pack.isEmpty()) {
            throw new OutlineException('No scraped IMS outlines are loaded yet.');
        }
        List<Brick__c> bricks = [
            SELECT Id, External_ID__c, Brick_Level__c, Boundary_GeoJSON__c
            FROM Brick__c
            WHERE Brick_Level__c IN ('148', '702') AND External_ID__c IN :pack.keySet()
            WITH SYSTEM_MODE
        ];
        List<Brick__c> updates = new List<Brick__c>();
        for (Brick__c brick : bricks) {
            if (!overwrite && String.isNotBlank(brick.Boundary_GeoJSON__c)) {
                continue;
            }
            String geometry = pack.get(brick.External_ID__c);
            if (String.isBlank(geometry)) {
                continue;
            }
            BrickGeometry.parse(geometry);
            Brick__c row = new Brick__c(Id = brick.Id, Boundary_GeoJSON__c = geometry);
            row.Boundary_Source__c = brick.Brick_Level__c == '148' ? 'Child bricks' : 'Imported';
            updates.add(row);
        }
        if (updates.isEmpty()) {
            return 0;
        }
        Database.SaveResult[] results = Database.update(updates, false, AccessLevel.SYSTEM_MODE);
        Integer ok = 0;
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                ok++;
            }
        }
        return ok;
    }

    @TestVisible
    static Suggestion fromNominatim(String name) {
        String query = searchQuery(name);
        HttpRequest req = new HttpRequest();
        req.setEndpoint(nominatimEndpoint + '?q=' + EncodingUtil.urlEncode(query, 'UTF-8')
            + '&format=json&polygon_geojson=1&countrycodes=eg&limit=5&addressdetails=1');
        req.setMethod('GET');
        req.setHeader('User-Agent', 'ZetaPharma-BricksManager/1.0 (Cloudastick)');
        req.setHeader('Accept', 'application/json');
        req.setTimeout(20000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() >= 300) {
            throw new OutlineException('OpenStreetMap did not answer for "' + name + '".');
        }
        List<Object> hits = (List<Object>) JSON.deserializeUntyped(res.getBody());
        for (Object raw : hits) {
            Map<String, Object> hit = (Map<String, Object>) raw;
            String geometry = geometryOf(hit);
            if (geometry == null) {
                continue;
            }
            Suggestion suggestion = new Suggestion();
            suggestion.geometry = geometry;
            suggestion.query = query;
            suggestion.displayName = (String) hit.get('display_name');
            suggestion.source = 'Imported';
            return suggestion;
        }
        throw new OutlineException('OpenStreetMap has no region for "' + name + '". Draw it on the map.');
    }

    @TestVisible
    static String searchQuery(String name) {
        String cleaned = name == null ? '' : name.trim();
        if (cleaned.toLowerCase().startsWith('hay ') && cleaned.length() <= 7) {
            return cleaned + ', 6th of October, Egypt';
        }
        return cleaned + ', Egypt';
    }

    private static Suggestion fromResource(String externalId) {
        Map<String, String> pack = loadPack();
        if (!pack.containsKey(externalId)) {
            return null;
        }
        Suggestion suggestion = new Suggestion();
        suggestion.geometry = pack.get(externalId);
        suggestion.source = 'Imported';
        suggestion.query = 'IMS outline pack';
        return suggestion;
    }

    @TestVisible
    static Map<String, String> loadPack() {
        if (packOverride != null) {
            return packOverride;
        }
        Map<String, String> pack = new Map<String, String>();
        List<StaticResource> resources = [
            SELECT Body
            FROM StaticResource
            WHERE Name = :resourceName
            LIMIT 1
        ];
        if (resources.isEmpty()) {
            return pack;
        }
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(resources[0].Body.toString());
        Object bricks = root.get('bricks');
        if (!(bricks instanceof Map<String, Object>)) {
            return pack;
        }
        for (String key : ((Map<String, Object>) bricks).keySet()) {
            Object value = ((Map<String, Object>) bricks).get(key);
            if (value != null) {
                pack.put(key, JSON.serialize(value));
            }
        }
        return pack;
    }

    private static String geometryOf(Map<String, Object> hit) {
        Object raw = hit.get('geojson');
        if (!(raw instanceof Map<String, Object>)) {
            return null;
        }
        Map<String, Object> geo = (Map<String, Object>) raw;
        String kind = (String) geo.get('type');
        if (kind == 'Point') {
            List<Object> coords = (List<Object>) geo.get('coordinates');
            if (coords == null || coords.size() < 2) {
                return null;
            }
            Double lng = toDouble(coords[0]);
            Double lat = toDouble(coords[1]);
            if (lng == null || lat == null || !inEgypt(lng, lat)) {
                return null;
            }
            return JSON.serialize(pointBox(lng, lat));
        }
        if (kind != 'Polygon' && kind != 'MultiPolygon') {
            return null;
        }
        try {
            BrickGeometry.Shape parsed = BrickGeometry.parse(JSON.serialize(geo));
            if (parsed.vertexCount > BrickGeometry.MAX_VERTICES) {
                return null;
            }
            return BrickGeometry.toGeoJson(parsed);
        } catch (BrickGeometry.GeometryException e) {
            return null;
        }
    }

    private static Map<String, Object> pointBox(Double lng, Double lat) {
        Map<String, Object> polygon = new Map<String, Object>();
        polygon.put('type', 'Polygon');
        polygon.put(
            'coordinates',
            new List<Object>{
                new List<Object>{
                    new List<Object>{ lng - BOX_DEG, lat - BOX_DEG },
                    new List<Object>{ lng + BOX_DEG, lat - BOX_DEG },
                    new List<Object>{ lng + BOX_DEG, lat + BOX_DEG },
                    new List<Object>{ lng - BOX_DEG, lat + BOX_DEG },
                    new List<Object>{ lng - BOX_DEG, lat - BOX_DEG }
                }
            }
        );
        return polygon;
    }

    private static Boolean inEgypt(Double lng, Double lat) {
        return lng >= MIN_LNG && lng <= MAX_LNG && lat >= MIN_LAT && lat <= MAX_LAT;
    }

    private static Double toDouble(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).doubleValue();
        }
        try {
            return Double.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
}
