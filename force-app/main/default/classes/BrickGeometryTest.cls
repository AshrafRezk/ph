@IsTest
private class BrickGeometryTest {
    static String square(Decimal lat, Decimal lng, Decimal half) {
        return JSON.serialize(new Map<String, Object>{ 'type' => 'Polygon', 'coordinates' => new List<Object>{ ring(lat, lng, half) } });
    }

    static List<Object> ring(Decimal lat, Decimal lng, Decimal half) {
        return new List<Object>{
            new List<Object>{ lng - half, lat - half },
            new List<Object>{ lng + half, lat - half },
            new List<Object>{ lng + half, lat + half },
            new List<Object>{ lng - half, lat + half },
            new List<Object>{ lng - half, lat - half }
        };
    }

    static Boolean inside(BrickGeometry.Shape shape, Decimal lng, Decimal lat) {
        return BrickGeometry.contains(shape, lng.doubleValue(), lat.doubleValue());
    }

    static Double toEdge(BrickGeometry.Shape shape, Decimal lng, Decimal lat) {
        return BrickGeometry.distanceToEdgeMeters(shape, lng.doubleValue(), lat.doubleValue());
    }

    @IsTest
    static void squareContainsItsCentreButNotPointsOutside() {
        BrickGeometry.Shape shape = BrickGeometry.parse(square(30.1, 31.3, 0.01));
        System.assertEquals(true, inside(shape, 31.3, 30.1));
        System.assertEquals(true, inside(shape, 31.309, 30.091));
        System.assertEquals(false, inside(shape, 31.311, 30.1));
        System.assertEquals(false, inside(shape, 31.3, 30.2));
        System.assertEquals(4, shape.vertexCount, 'closing point is not stored twice');
    }

    @IsTest
    static void holesAreOutsideAndMultiPolygonsCountEveryPart() {
        String withHole = JSON.serialize(
            new Map<String, Object>{
                'type' => 'Polygon',
                'coordinates' => new List<Object>{ ring(30.1, 31.3, 0.01), ring(30.1, 31.3, 0.003) }
            }
        );
        BrickGeometry.Shape donut = BrickGeometry.parse(withHole);
        System.assertEquals(false, inside(donut, 31.3, 30.1), 'centre is in the hole');
        System.assertEquals(true, inside(donut, 31.306, 30.1));

        String twoParts = JSON.serialize(
            new Map<String, Object>{
                'type' => 'Feature',
                'geometry' => new Map<String, Object>{
                    'type' => 'MultiPolygon',
                    'coordinates' => new List<Object>{
                        new List<Object>{ ring(30.1, 31.3, 0.01) },
                        new List<Object>{ ring(30.5, 31.5, 0.01) }
                    }
                }
            }
        );
        BrickGeometry.Shape multi = BrickGeometry.parse(twoParts);
        System.assertEquals(true, inside(multi, 31.5, 30.5));
        System.assertEquals(true, inside(multi, 31.3, 30.1));
        System.assertEquals(false, inside(multi, 31.4, 30.3));
        System.assert(BrickGeometry.toGeoJson(multi).contains('"MultiPolygon"'));

        String collection = JSON.serialize(
            new Map<String, Object>{
                'type' => 'FeatureCollection',
                'features' => new List<Object>{
                    new Map<String, Object>{
                        'type' => 'Feature',
                        'geometry' => (Map<String, Object>) JSON.deserializeUntyped(square(30.1, 31.3, 0.01))
                    }
                }
            }
        );
        System.assertEquals(1, BrickGeometry.parse(collection).polygons.size());
    }

    @IsTest
    static void areaCentreAndEdgeDistanceAreInMetresAndKilometres() {
        BrickGeometry.Shape shape = BrickGeometry.parse(square(30.1, 31.3, 0.01));
        Double area = BrickGeometry.areaKm2(shape);
        System.assert(area > 4.0 && area < 4.5, 'about 1.93 km x 2.21 km, got ' + area);
        List<Double> c = BrickGeometry.center(shape);
        System.assert(Math.abs(c[0] - 31.3) < 0.000001 && Math.abs(c[1] - 30.1) < 0.000001, 'centre ' + c);
        Double fromCentre = toEdge(shape, 31.3, 30.1);
        System.assert(fromCentre > 950 && fromCentre < 1000, 'nearest edge is the east/west one, got ' + fromCentre);
        Double outside = toEdge(shape, 31.312, 30.1);
        System.assert(outside > 180 && outside < 200, '0.002 degrees east of the edge, got ' + outside);
    }

    @IsTest
    static void canonicalGeoJsonClosesRingsAndRounds() {
        String canonical = BrickGeometry.toGeoJson(BrickGeometry.parse(square(30.123456789, 31.3, 0.01)));
        Map<String, Object> geometry = (Map<String, Object>) JSON.deserializeUntyped(canonical);
        System.assertEquals('Polygon', geometry.get('type'));
        List<Object> outline = (List<Object>) ((List<Object>) geometry.get('coordinates'))[0];
        System.assertEquals(5, outline.size());
        System.assertEquals(String.valueOf(outline[0]), String.valueOf(outline[4]));
        System.assert(canonical.contains('30.113457'), canonical);
    }

    @IsTest
    static void invalidRegionsExplainWhatIsWrong() {
        Map<String, String> cases = new Map<String, String>{
            '' => 'empty',
            'not json' => 'not valid GeoJSON',
            '{"type":"LineString","coordinates":[[31,30],[31.1,30.1]]}' => 'Only Polygon and MultiPolygon',
            '{"type":"Polygon","coordinates":[[[31,30],[31.1,30.1],[31,30]]]}' => 'at least 3',
            '{"type":"Polygon","coordinates":[[[31.2,35],[31.3,35],[31.3,35.1],[31.2,35]]]}' => 'outside Egypt',
            '{"type":"Polygon","coordinates":[[[31,"x"],[31.1,30.1],[31.2,30.2]]]}' => 'not a number',
            '{"type":"Polygon","coordinates":[]}' => 'no outline'
        };
        for (String input : cases.keySet()) {
            try {
                BrickGeometry.parse(input);
                System.assert(false, 'expected an error for ' + input);
            } catch (BrickGeometry.GeometryException e) {
                System.assert(e.getMessage().contains(cases.get(input)), input + ' -> ' + e.getMessage());
            }
        }
    }

    @IsTest
    static void triggerKeepsRegionBoxCentreAndAreaInStep() {
        Brick__c brick = new Brick__c(
            Name = 'Geometry Trigger Brick',
            Brick_Level__c = '148',
            External_ID__c = 'GEOMETRY_TRIGGER_148',
            Boundary_GeoJSON__c = square(30.1, 31.3, 0.01)
        );
        insert brick;
        brick = [
            SELECT Min_Latitude__c, Max_Latitude__c, Min_Longitude__c, Max_Longitude__c, Center_Latitude__c,
                Center_Longitude__c, Boundary_Area_Km2__c, Boundary_Source__c, Boundary_Updated__c
            FROM Brick__c
            WHERE Id = :brick.Id
        ];
        System.assertEquals(30.09, brick.Min_Latitude__c.setScale(2));
        System.assertEquals(30.11, brick.Max_Latitude__c.setScale(2));
        System.assertEquals(31.29, brick.Min_Longitude__c.setScale(2));
        System.assertEquals(31.31, brick.Max_Longitude__c.setScale(2));
        System.assertEquals(30.1, brick.Center_Latitude__c.setScale(1));
        System.assert(brick.Boundary_Area_Km2__c > 4);
        System.assertEquals('Imported', brick.Boundary_Source__c, 'loaded outside the Bricks Manager');
        System.assertNotEquals(null, brick.Boundary_Updated__c);

        brick.Boundary_GeoJSON__c = null;
        update brick;
        brick = [SELECT Min_Latitude__c, Boundary_Area_Km2__c, Boundary_Source__c FROM Brick__c WHERE Id = :brick.Id];
        System.assertEquals(null, brick.Min_Latitude__c);
        System.assertEquals(null, brick.Boundary_Area_Km2__c);
        System.assertEquals(null, brick.Boundary_Source__c);

        brick.Boundary_GeoJSON__c = '{"type":"Point","coordinates":[31,30]}';
        Database.SaveResult result = Database.update(brick, false);
        System.assertEquals(false, result.isSuccess());
        System.assert(result.getErrors()[0].getMessage().contains('Only Polygon'));
    }
}
