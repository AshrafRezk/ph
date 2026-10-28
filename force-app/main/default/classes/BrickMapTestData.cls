/**
 * Brick hierarchy with regions for tests, around (30.10, 31.30):
 *   area70 ── north148 (region ±0.10°) ── a702 (±0.01°), b702 (east of a702, ~50 m gap), inner702 (±0.003° inside a702), bare702 (no region)
 *          └─ south148 (no region)
 */
@IsTest
public class BrickMapTestData {
    public static final Decimal LAT = 30.10;
    public static final Decimal LNG = 31.30;

    public Brick__c area70;
    public Brick__c north148;
    public Brick__c south148;
    public Brick__c a702;
    public Brick__c b702;
    public Brick__c inner702;
    public Brick__c bare702;

    public static String square(Decimal lat, Decimal lng, Decimal half) {
        return JSON.serialize(
            new Map<String, Object>{
                'type' => 'Polygon',
                'coordinates' => new List<Object>{
                    new List<Object>{
                        new List<Object>{ lng - half, lat - half },
                        new List<Object>{ lng + half, lat - half },
                        new List<Object>{ lng + half, lat + half },
                        new List<Object>{ lng - half, lat + half },
                        new List<Object>{ lng - half, lat - half }
                    }
                }
            }
        );
    }

    public static BrickMapTestData create() {
        BrickMapTestData d = new BrickMapTestData();
        d.area70 = brick('Test Area', '70', null, null);
        insert d.area70;
        d.north148 = brick('BRICK1 TEST NORTH', '148', d.area70.Id, square(LAT, LNG, 0.10));
        d.south148 = brick('BRICK2 TEST SOUTH', '148', d.area70.Id, null);
        insert new List<Brick__c>{ d.north148, d.south148 };
        d.a702 = brick('Test A', '702', d.north148.Id, square(LAT, LNG, 0.01));
        d.b702 = brick('Test B', '702', d.north148.Id, square(LAT, LNG + 0.0205, 0.01));
        d.inner702 = brick('Test Inner', '702', d.north148.Id, square(LAT, LNG, 0.003));
        d.bare702 = brick('Test Bare', '702', d.north148.Id, null);
        insert new List<Brick__c>{ d.a702, d.b702, d.inner702, d.bare702 };
        return d;
    }

    public static Distributor_Sellout_Alias__c client(String code, Decimal lat, Decimal lng, String precision) {
        return new Distributor_Sellout_Alias__c(
            Distributor_Code__c = 'Egydrug',
            Distributor_Client_Code__c = code,
            Distributor_Client_Name__c = 'Client ' + code,
            Latitude__c = lat,
            Longitude__c = lng,
            Geocode_Precision__c = precision,
            Geocode_Status__c = lat == null ? 'Pending' : 'Geocoded',
            Status__c = 'Unmatched',
            Unique_Key__c = 'Egydrug|' + code
        );
    }

    private static Brick__c brick(String name, String level, Id parentId, String region) {
        return new Brick__c(
            Name = name,
            Brick_Code__c = name,
            Brick_Level__c = level,
            Parent_Brick__c = parentId,
            Is_Active__c = true,
            Account_Selectable__c = level != '70',
            Data_Source__c = 'IQVIA IMS',
            External_ID__c = 'TEST_' + level + '_' + name.toUpperCase().replaceAll('[^A-Z0-9]+', '_'),
            Boundary_GeoJSON__c = region,
            Boundary_Source__c = region == null ? null : 'Drawn'
        );
    }
}
