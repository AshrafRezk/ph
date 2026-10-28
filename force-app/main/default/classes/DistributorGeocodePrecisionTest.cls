@IsTest
private class DistributorGeocodePrecisionTest {
    /** Nominatim that only knows the governorate, like most informal addresses. */
    private class GovernorateOnlyMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            String q = EncodingUtil.urlDecode(req.getEndpoint().substringBetween('q=', '&'), 'UTF-8');
            res.setBody(
                q == 'Cairo, Egypt'
                    ? '[{"lat":"30.0444","lon":"31.2357","display_name":"Cairo","addresstype":"city","boundingbox":["29.9","30.2","31.1","31.5"]}]'
                    : '[]'
            );
            return res;
        }
    }

    static Map<String, Object> parse(String body) {
        return (Map<String, Object>) JSON.deserializeUntyped(body);
    }

    @IsTest
    static void googleTypesAndViewportGiveThePrecision() {
        System.assertEquals(
            'Street',
            DistributorGeocodeService.googlePrecision(
                parse(
                    '{"types":["pharmacy","establishment"],"geometry":{"viewport":{"northeast":{"lat":30.0631,"lng":31.2202},"southwest":{"lat":30.0621,"lng":31.2192}}}}'
                )
            )
        );
        System.assertEquals(
            'Area',
            DistributorGeocodeService.googlePrecision(parse('{"types":["sublocality","political"]}'))
        );
        System.assertEquals(
            'City',
            DistributorGeocodeService.googlePrecision(
                parse(
                    '{"types":["route"],"geometry":{"viewport":{"northeast":{"lat":30.10,"lng":31.40},"southwest":{"lat":30.00,"lng":31.30}}}}'
                )
            ),
            'a long road is only as precise as its extent'
        );
        System.assertEquals(
            'Governorate',
            DistributorGeocodeService.googlePrecision(parse('{"types":["administrative_area_level_1","political"]}'))
        );
        System.assertEquals(null, DistributorGeocodeService.googlePrecision(parse('{"geometry":{}}')));
    }

    @IsTest
    static void nominatimAddressTypeAndBoxGiveThePrecision() {
        System.assertEquals(
            'Street',
            DistributorGeocodeService.nominatimPrecision(
                parse('{"addresstype":"amenity","type":"pharmacy","boundingbox":["30.0620","30.0630","31.2190","31.2200"]}')
            )
        );
        System.assertEquals(
            'Area',
            DistributorGeocodeService.nominatimPrecision(parse('{"addresstype":"suburb","type":"administrative"}'))
        );
        System.assertEquals(
            'Governorate',
            DistributorGeocodeService.nominatimPrecision(parse('{"type":"administrative","boundingbox":["29.5","31.0","30.5","32.0"]}'))
        );
    }

    @IsTest
    static void aGovernorateOnlyHitIsMarkedAsGovernorate() {
        Test.setMock(HttpCalloutMock.class, new GovernorateOnlyMock());
        Test.startTest();
        DistributorGeocodeService.GeoResult geo = DistributorGeocodeService.geocode(
            'Unknown Pharmacy',
            'Unknown Street',
            'Cairo'
        );
        Test.stopTest();
        System.assertEquals('Geocoded', geo.status);
        System.assertEquals('Governorate', geo.precision);
    }
}
