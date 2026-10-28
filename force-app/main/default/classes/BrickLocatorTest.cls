@IsTest
private class BrickLocatorTest {
    static BrickLocator.Placement at(Decimal lat, Decimal lng, String precision) {
        return BrickLocator.placeOne(lat, lng, precision);
    }

    @IsTest
    static void smallestContainingRegionWinsAndTheParentIsThe148() {
        BrickMapTestData d = BrickMapTestData.create();
        BrickLocator.Placement centre = at(BrickMapTestData.LAT, BrickMapTestData.LNG, 'Street');
        System.assertEquals(d.inner702.Id, centre.brick702Id, 'inner region overlaps A and is smaller');
        System.assertEquals(d.north148.Id, centre.brick148Id);
        System.assertEquals(BrickLocator.IN_REGION, centre.status);

        BrickLocator.Placement inA = at(BrickMapTestData.LAT + 0.006, BrickMapTestData.LNG, null);
        System.assertEquals(d.a702.Id, inA.brick702Id);
    }

    @IsTest
    static void precisePointInASmallGapSnapsToTheNearestRegion() {
        BrickMapTestData d = BrickMapTestData.create();
        // A ends at 31.310, B starts at 31.3105; 31.3102 is ~19 m from A and ~29 m from B.
        BrickLocator.Placement gap = at(BrickMapTestData.LAT, 31.3102, 'Area');
        System.assertEquals(d.a702.Id, gap.brick702Id);
        System.assertEquals(BrickLocator.NEAREST_REGION, gap.status);
    }

    @IsTest
    static void pointOutside702RegionsStillGetsThe148Region() {
        BrickMapTestData d = BrickMapTestData.create();
        BrickLocator.Placement p = at(30.15, 31.35, 'Street');
        System.assertEquals(null, p.brick702Id);
        System.assertEquals(d.north148.Id, p.brick148Id);
        System.assertEquals(BrickLocator.IN_REGION, p.status);

        BrickLocator.Placement outside = at(29.5, 31.0, 'Street');
        System.assertEquals(null, outside.brick148Id);
        System.assertEquals(BrickLocator.OUTSIDE, outside.status);
    }

    @IsTest
    static void coarseLocationsAreOnlyPlacedWhenTheyCannotBeWrong() {
        BrickMapTestData.create();
        System.assertEquals(BrickLocator.APPROXIMATE, at(30.1, 31.3, 'Governorate').status);

        BrickLocator.Placement deep = at(30.15, 31.35, 'City');
        System.assertNotEquals(null, deep.brick148Id, 'about 5 km inside the 148 region');
        System.assertEquals(null, deep.brick702Id);

        BrickLocator.Placement centreOfSmallBricks = at(BrickMapTestData.LAT, BrickMapTestData.LNG, 'City');
        System.assertEquals(null, centreOfSmallBricks.brick702Id, 'a town centre is not inside one 702 for sure');
        System.assertNotEquals(null, centreOfSmallBricks.brick148Id);

        BrickLocator.Placement nearEdge = at(30.19, 31.39, 'City');
        System.assertEquals(BrickLocator.APPROXIMATE, nearEdge.status);

        System.assertEquals(BrickLocator.NO_LOCATION, BrickLocator.placeOne(null, 31.3, 'Street').status);
    }

    @IsTest
    static void inactiveBricksAreSkipped() {
        BrickMapTestData d = BrickMapTestData.create();
        d.a702.Is_Active__c = false;
        update d.a702;
        BrickLocator.Placement p = at(BrickMapTestData.LAT + 0.006, BrickMapTestData.LNG, 'Street');
        System.assertEquals(null, p.brick702Id);
        System.assertEquals(d.north148.Id, p.brick148Id);
    }

    @IsTest
    static void clientsArePlacedWhenTheirLocationIsSavedOrMoved() {
        BrickMapTestData d = BrickMapTestData.create();
        Distributor_Sellout_Alias__c c = BrickMapTestData.client('LOC1', 30.106, 31.3, 'Street');
        Distributor_Sellout_Alias__c noGeo = BrickMapTestData.client('LOC2', null, null, null);
        insert new List<Distributor_Sellout_Alias__c>{ c, noGeo };
        c = [SELECT Brick_702__c, Brick_148__c, Brick_Placement__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id];
        System.assertEquals(d.a702.Id, c.Brick_702__c);
        System.assertEquals(d.north148.Id, c.Brick_148__c);
        System.assertEquals(BrickLocator.IN_REGION, c.Brick_Placement__c);
        System.assertEquals(
            BrickLocator.NO_LOCATION,
            [SELECT Brick_Placement__c FROM Distributor_Sellout_Alias__c WHERE Id = :noGeo.Id].Brick_Placement__c
        );

        c.Latitude__c = 30.15;
        c.Longitude__c = 31.35;
        update c;
        c = [SELECT Brick_702__c, Brick_148__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id];
        System.assertEquals(null, c.Brick_702__c);
        System.assertEquals(d.north148.Id, c.Brick_148__c);

        c.Geocode_Precision__c = 'Governorate';
        update c;
        c = [SELECT Brick_148__c, Brick_Placement__c FROM Distributor_Sellout_Alias__c WHERE Id = :c.Id];
        System.assertEquals(null, c.Brick_148__c);
        System.assertEquals(BrickLocator.APPROXIMATE, c.Brick_Placement__c);
    }
}
