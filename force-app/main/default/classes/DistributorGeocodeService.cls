/**
 * Geocoding for distributor sellout aliases.
 * With a Google key: Geocoding API for the street address, then Places text search
 * when the address returns nothing but the pharmacy name and area are known.
 * Without a key: OpenStreetMap Nominatim.
 * Each hit carries a precision (Street, Area, City, Governorate) from the result type and extent, so a
 * town or governorate centre is not mistaken for the pharmacy's street location when placing it in a brick.
 */
public with sharing class DistributorGeocodeService {
    public class GeoResult {
        public Decimal latitude;
        public Decimal longitude;
        public String status;
        public String formattedAddress;
        public String provider;
        public String message;
        public String recommendation;
        public String precision;
    }

    private static final List<String> PRECISION_ORDER = new List<String>{ 'Street', 'Area', 'City', 'Governorate' };
    private static final Set<String> STREET_TYPES = new Set<String>{
        'street_address',
        'premise',
        'subpremise',
        'route',
        'intersection',
        'establishment',
        'point_of_interest',
        'pharmacy',
        'health',
        'store',
        'house',
        'building',
        'amenity',
        'shop',
        'healthcare',
        'road',
        'office'
    };
    private static final Set<String> AREA_TYPES = new Set<String>{
        'neighborhood',
        'neighbourhood',
        'sublocality',
        'sublocality_level_1',
        'sublocality_level_2',
        'sublocality_level_3',
        'sublocality_level_4',
        'sublocality_level_5',
        'colloquial_area',
        'postal_code',
        'suburb',
        'quarter',
        'village',
        'hamlet',
        'city_district',
        'district',
        'borough',
        'city_block',
        'residential'
    };
    private static final Set<String> CITY_TYPES = new Set<String>{
        'locality',
        'administrative_area_level_2',
        'administrative_area_level_3',
        'city',
        'town',
        'municipality',
        'county'
    };
    private static final Set<String> GOVERNORATE_TYPES = new Set<String>{
        'administrative_area_level_1',
        'country',
        'state',
        'region',
        'province'
    };

    public static GeoResult geocode(String name, String address, String governorate) {
        GeoResult result = new GeoResult();
        String cleanGov = cleanPlace(governorate);
        String cleanAddr = cleanPlace(address);
        String cleanName = cleanPlace(name);

        if (String.isBlank(cleanAddr) && String.isBlank(cleanGov) && String.isBlank(cleanName)) {
            result.status = 'Skipped';
            result.message = 'No pharmacy name, address, or governorate to geocode.';
            result.recommendation =
                'Add an address on this sellout alias, or link a pharmacy Account manually.';
            return result;
        }
        if (String.isBlank(cleanAddr) && String.isBlank(cleanGov)) {
            result.status = 'Skipped';
            result.message = 'Only a client name was available — street/area is required to geocode.';
            result.recommendation =
                'Add address or governorate on the alias, or link a pharmacy Account manually.';
            return result;
        }

        List<String> queryCandidates = buildQueryCandidates(cleanName, cleanAddr, cleanGov);
        String governorateOnly = String.isBlank(cleanGov) ? null : cleanGov + ', Egypt';
        String apiKey = resolveApiKey();
        Boolean usedGoogle = String.isNotBlank(apiKey);
        for (String query : queryCandidates) {
            GeoResult attempt = usedGoogle ? geocodeGoogle(query, apiKey) : geocodeNominatim(query);
            if (attempt != null && attempt.status == 'Geocoded') {
                if (query == governorateOnly) {
                    attempt.precision = 'Governorate';
                }
                return attempt;
            }
            if (attempt != null) {
                result = attempt;
            }
        }
        if (usedGoogle && String.isNotBlank(cleanName) && (result.status == null || result.status != 'Geocoded')) {
            GeoResult places = placesTextSearch(cleanName, cleanAddr, cleanGov, apiKey);
            if (places != null && places.status == 'Geocoded') {
                return places;
            }
            if (places != null) {
                result = places;
            }
        }
        if (result.status == null || result.status == 'Failed') {
            result.status = 'Failed';
            if (String.isBlank(result.message)) {
                result.message = usedGoogle
                    ? 'Google Geocoding and Google Places returned no usable coordinates (tried street, locality, governorate, and pharmacy name).'
                    : 'OpenStreetMap Nominatim returned no usable coordinates for this address (tried street, locality, and governorate).';
            }
            if (String.isBlank(result.recommendation)) {
                result.recommendation = defaultFailureRecommendation(usedGoogle);
            }
        }
        return result;
    }

    public static String defaultFailureRecommendation(Boolean usedGoogle) {
        if (usedGoogle != true) {
            return 'Add a Google Geocoding API key on the Import tab for better Egypt street matching, ' +
                'or search and link an existing pharmacy Account manually.';
        }
        return 'Improve the address (neighborhood / street), then re-run geocode from Batches, ' +
            'or search and link an existing pharmacy Account manually.';
    }

    public static String recommendationForStatus(String status, String storedMessage) {
        if (status == 'Geocoded') {
            return null;
        }
        if (status == 'Pending') {
            return 'Wait for the import batch to finish geocoding, or re-queue from Batches.';
        }
        if (status == 'Skipped') {
            return 'Add address/governorate on the alias, or link a pharmacy Account manually.';
        }
        if (status == 'Failed') {
            return defaultFailureRecommendation(hasGoogleApiKey());
        }
        return null;
    }

    private static List<String> buildQueryCandidates(String name, String address, String governorate) {
        List<String> queries = new List<String>();
        List<String> parts = new List<String>();
        if (String.isNotBlank(name)) {
            parts.add(name);
        }
        if (String.isNotBlank(address)) {
            parts.add(address);
        }
        if (String.isNotBlank(governorate)) {
            parts.add(governorate);
        }
        parts.add('Egypt');
        queries.add(String.join(parts, ', '));

        // Informal Egypt addresses often encode locality after '/' — try locality + governorate
        if (String.isNotBlank(address)) {
            List<String> localityBits = new List<String>();
            for (String chunk : address.split('[/|,|-]')) {
                String c = cleanPlace(chunk);
                if (String.isNotBlank(c) && c.length() >= 3) {
                    localityBits.add(c);
                }
            }
            if (!localityBits.isEmpty()) {
                String locality = localityBits[localityBits.size() - 1];
                List<String> locParts = new List<String>{ locality };
                if (String.isNotBlank(governorate)) {
                    locParts.add(governorate);
                }
                locParts.add('Egypt');
                String locQuery = String.join(locParts, ', ');
                if (!queries.contains(locQuery)) {
                    queries.add(locQuery);
                }
                String longest = locality;
                for (String c : localityBits) {
                    if (c.length() > longest.length()) {
                        longest = c;
                    }
                }
                if (longest != locality) {
                    List<String> longParts = new List<String>{ longest };
                    if (String.isNotBlank(governorate)) {
                        longParts.add(governorate);
                    }
                    longParts.add('Egypt');
                    String longQuery = String.join(longParts, ', ');
                    if (!queries.contains(longQuery)) {
                        queries.add(longQuery);
                    }
                }
            }
        }

        if (String.isNotBlank(governorate)) {
            String govOnly = governorate + ', Egypt';
            if (!queries.contains(govOnly)) {
                queries.add(govOnly);
            }
        }
        return queries;
    }

    private static GeoResult geocodeGoogle(String query, String apiKey) {
        GeoResult result = new GeoResult();
        result.provider = 'Google';
        String endpoint =
            'callout:Google_Geocoding/maps/api/geocode/json?address=' +
            EncodingUtil.urlEncode(query, 'UTF-8') +
            '&region=eg&language=ar&key=' +
            EncodingUtil.urlEncode(apiKey, 'UTF-8');

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(12000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            result.status = 'Failed';
            result.message = 'Google Geocoding HTTP ' + res.getStatusCode() + '.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String apiStatus = (String) body.get('status');
        if (apiStatus != 'OK') {
            result.status = 'Failed';
            result.message = 'Google Geocoding status: ' + apiStatus + '.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        List<Object> results = (List<Object>) body.get('results');
        if (results == null || results.isEmpty()) {
            result.status = 'Failed';
            result.message = 'Google Geocoding returned zero results.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        Map<String, Object> first = (Map<String, Object>) results[0];
        Map<String, Object> geometry = (Map<String, Object>) first.get('geometry');
        Map<String, Object> location = (Map<String, Object>) geometry.get('location');
        result.latitude = toDec(location.get('lat'));
        result.longitude = toDec(location.get('lng'));
        result.formattedAddress = (String) first.get('formatted_address');
        result.precision = googlePrecision(first);
        result.status = 'Geocoded';
        result.message = null;
        result.recommendation = null;
        return result;
    }

    private static GeoResult placesTextSearch(String name, String address, String governorate, String apiKey) {
        GeoResult result = new GeoResult();
        result.provider = 'Google Places';
        List<String> parts = new List<String>{ name };
        if (String.isNotBlank(address)) {
            parts.add(address);
        }
        if (String.isNotBlank(governorate)) {
            parts.add(governorate);
        }
        parts.add('Egypt');
        String query = String.join(parts, ', ');
        String endpoint =
            'callout:Google_Geocoding/maps/api/place/textsearch/json?query=' +
            EncodingUtil.urlEncode(query, 'UTF-8') +
            '&region=eg&language=ar&key=' +
            EncodingUtil.urlEncode(apiKey, 'UTF-8');
        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(12000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            result.status = 'Failed';
            result.message = 'Google Places HTTP ' + res.getStatusCode() + '.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        String apiStatus = (String) body.get('status');
        if (apiStatus != 'OK') {
            result.status = 'Failed';
            result.message = 'Google Places status: ' + apiStatus + '.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        List<Object> results = (List<Object>) body.get('results');
        if (results == null || results.isEmpty()) {
            result.status = 'Failed';
            result.message = 'Google Places returned zero results.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        Map<String, Object> first = (Map<String, Object>) results[0];
        Map<String, Object> geometry = (Map<String, Object>) first.get('geometry');
        Map<String, Object> location = geometry == null ? null : (Map<String, Object>) geometry.get('location');
        if (location == null) {
            result.status = 'Failed';
            result.message = 'Google Places result had no coordinates.';
            result.recommendation = defaultFailureRecommendation(true);
            return result;
        }
        result.latitude = toDec(location.get('lat'));
        result.longitude = toDec(location.get('lng'));
        result.formattedAddress = (String) first.get('formatted_address');
        result.precision = googlePrecision(first);
        if (result.precision == null) {
            result.precision = 'Street';
        }
        result.status = 'Geocoded';
        return result;
    }

    private static GeoResult geocodeNominatim(String query) {
        GeoResult result = new GeoResult();
        result.provider = 'Nominatim';
        String endpoint =
            'callout:OpenStreetMap_Nominatim/search?q=' +
            EncodingUtil.urlEncode(query, 'UTF-8') +
            '&format=json&limit=1&countrycodes=eg';

        HttpRequest req = new HttpRequest();
        req.setEndpoint(endpoint);
        req.setMethod('GET');
        req.setTimeout(12000);
        req.setHeader('User-Agent', 'ZetaPharma-DistributorsManagement/1.0');
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() == 429 || res.getStatusCode() == 502 || res.getStatusCode() == 503) {
            result.status = 'Failed';
            result.message = 'Nominatim temporarily unavailable (HTTP ' + res.getStatusCode() + ').';
            result.recommendation =
                'Re-queue the batch later, or add a Google Geocoding API key on the Import tab.';
            return result;
        }
        if (res.getStatusCode() != 200) {
            result.status = 'Failed';
            result.message = 'Nominatim HTTP ' + res.getStatusCode() + '.';
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        String bodyText = res.getBody();
        if (String.isBlank(bodyText) || !bodyText.trim().startsWith('[')) {
            result.status = 'Failed';
            result.message = 'Nominatim returned an unexpected response.';
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        Object parsed = JSON.deserializeUntyped(bodyText);
        if (!(parsed instanceof List<Object>) || ((List<Object>) parsed).isEmpty()) {
            result.status = 'Failed';
            result.message = 'Nominatim found no match for query: ' + query.left(180);
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        Map<String, Object> first = (Map<String, Object>) ((List<Object>) parsed)[0];
        result.latitude = toDec(first.get('lat'));
        result.longitude = toDec(first.get('lon'));
        result.formattedAddress = (String) first.get('display_name');
        if (result.latitude == null || result.longitude == null) {
            result.status = 'Failed';
            result.message = 'Nominatim result was missing coordinates.';
            result.recommendation = defaultFailureRecommendation(false);
            return result;
        }
        result.precision = nominatimPrecision(first);
        result.status = 'Geocoded';
        result.message = null;
        result.recommendation = null;
        return result;
    }

    public static Boolean hasGoogleApiKey() {
        return String.isNotBlank(resolveApiKey());
    }

    /** Coarser of the result-type precision and the viewport-size precision. */
    @TestVisible
    private static String googlePrecision(Map<String, Object> result) {
        Set<String> types = new Set<String>();
        if (result.get('types') instanceof List<Object>) {
            for (Object t : (List<Object>) result.get('types')) {
                types.add(String.valueOf(t));
            }
        }
        String byExtent;
        Map<String, Object> geometry = (Map<String, Object>) result.get('geometry');
        Object viewport = geometry == null ? null : geometry.get('viewport');
        if (viewport instanceof Map<String, Object>) {
            Object ne = ((Map<String, Object>) viewport).get('northeast');
            Object sw = ((Map<String, Object>) viewport).get('southwest');
            if (ne instanceof Map<String, Object> && sw instanceof Map<String, Object>) {
                Map<String, Object> neMap = (Map<String, Object>) ne;
                Map<String, Object> swMap = (Map<String, Object>) sw;
                byExtent = precisionForExtent(
                    toDec(swMap.get('lat')),
                    toDec(swMap.get('lng')),
                    toDec(neMap.get('lat')),
                    toDec(neMap.get('lng'))
                );
            }
        }
        return coarser(precisionForTypes(types), byExtent);
    }

    /** Coarser of the OSM address type and the bounding-box precision. */
    @TestVisible
    private static String nominatimPrecision(Map<String, Object> result) {
        Set<String> types = new Set<String>();
        for (String key : new List<String>{ 'addresstype', 'type' }) {
            if (result.get(key) != null) {
                types.add(String.valueOf(result.get(key)));
            }
        }
        String byExtent;
        if (result.get('boundingbox') instanceof List<Object>) {
            List<Object> box = (List<Object>) result.get('boundingbox');
            if (box.size() == 4) {
                byExtent = precisionForExtent(toDec(box[0]), toDec(box[2]), toDec(box[1]), toDec(box[3]));
            }
        }
        return coarser(precisionForTypes(types), byExtent);
    }

    private static String precisionForTypes(Set<String> types) {
        List<Set<String>> buckets = new List<Set<String>>{ STREET_TYPES, AREA_TYPES, CITY_TYPES, GOVERNORATE_TYPES };
        for (Integer i = 0; i < buckets.size(); i++) {
            for (String t : types) {
                if (buckets[i].contains(t)) {
                    return PRECISION_ORDER[i];
                }
            }
        }
        return null;
    }

    /** Street up to 1.5 km across, Area up to 6 km, City up to 40 km, otherwise Governorate. */
    private static String precisionForExtent(Decimal south, Decimal west, Decimal north, Decimal east) {
        if (south == null || west == null || north == null || east == null) {
            return null;
        }
        Double midLat = (south + north).doubleValue() / 2;
        Double dy = (north - south).doubleValue() * 110.574;
        Double dx = (east - west).doubleValue() * 111.320 * Math.cos(midLat * Math.PI / 180);
        Double km = Math.sqrt(dx * dx + dy * dy);
        if (km <= 1.5) {
            return 'Street';
        }
        if (km <= 6) {
            return 'Area';
        }
        if (km <= 40) {
            return 'City';
        }
        return 'Governorate';
    }

    private static String coarser(String a, String b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return PRECISION_ORDER.indexOf(a) >= PRECISION_ORDER.indexOf(b) ? a : b;
    }

    private static String resolveApiKey() {
        Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
        if (cfg != null && String.isNotBlank(cfg.Google_API_Key__c)) {
            return cfg.Google_API_Key__c;
        }
        return null;
    }

    private static String cleanPlace(String raw) {
        if (String.isBlank(raw)) {
            return null;
        }
        String s = raw.trim();
        if (s == '0' || s == '-' || s == 'null' || s == 'NULL' || s == 'N/A') {
            return null;
        }
        return s;
    }

    private static Decimal toDec(Object o) {
        if (o == null) {
            return null;
        }
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        try {
            return Decimal.valueOf(String.valueOf(o));
        } catch (Exception e) {
            return null;
        }
    }
}