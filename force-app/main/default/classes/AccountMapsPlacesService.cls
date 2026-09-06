/**
 * Official Google Places + OSM Overpass enrichment for account maps phone / photos.
 * Does not scrape Google Maps HTML.
 */
public with sharing class AccountMapsPlacesService {
  public class EnrichmentResult {
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public String placeId;
    @AuraEnabled
    public String status;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public String provider;
  }

  public class LocationMedia {
    @AuraEnabled
    public Id accountId;
    @AuraEnabled
    public String accountName;
    @AuraEnabled
    public String mapsPhone;
    @AuraEnabled
    public String placeId;
    @AuraEnabled
    public String enrichmentStatus;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String addressLine;
    @AuraEnabled
    public String streetViewUrl;
    @AuraEnabled
    public String staticMapUrl;
    @AuraEnabled
    public List<String> photoUrls;
    @AuraEnabled
    public String message;
    @AuraEnabled
    public Boolean hasGoogleKey;
  }

  public class PlaceCandidate {
    @AuraEnabled
    public String placeId;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String phone;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String provider;
    @AuraEnabled
    public String staticMapUrl;
    @AuraEnabled
    public String placeKind;
    @AuraEnabled
    public String placeKindLabel;
    @AuraEnabled
    public Decimal rating;
    @AuraEnabled
    public Integer ratingCount;
    @AuraEnabled
    public Boolean isKol;
    public String osmClass;
    public String osmType;
    public String osmAmenity;
    public String osmOffice;
    public List<String> googleTypes;
  }

  public class PlaceGeoBias {
    @AuraEnabled
    public String zoneName;
    @AuraEnabled
    public String brickName;
    @AuraEnabled
    public String areaName;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public Integer radiusMeters;
    @AuraEnabled
    public Decimal south;
    @AuraEnabled
    public Decimal west;
    @AuraEnabled
    public Decimal north;
    @AuraEnabled
    public Decimal east;
    @AuraEnabled
    public List<String> addressTokens;
    @AuraEnabled
    public Boolean bounded;
  }

  public static Id runPhoneEnrichmentBatch() {
    Integer scopeSize = DistributorGeocodeService.hasGoogleApiKey() ? 10 : 5;
    return Database.executeBatch(new AccountMapsPhoneBatch(), scopeSize);
  }

  @AuraEnabled(cacheable=true)
  public static LocationMedia getLocationMedia(Id accountId) {
    if (accountId == null) {
      throw new AuraHandledException('Account Id is required.');
    }
    Account acct = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        Maps_Phone_Number__c,
        Maps_Place_Id__c,
        Maps_Enrichment_Status__c
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    LocationMedia media = new LocationMedia();
    media.accountId = acct.Id;
    media.accountName = acct.Name;
    media.mapsPhone = acct.Maps_Phone_Number__c;
    media.placeId = acct.Maps_Place_Id__c;
    media.enrichmentStatus = acct.Maps_Enrichment_Status__c;
    media.latitude = acct.BillingLatitude;
    media.longitude = acct.BillingLongitude;
    media.addressLine = buildAddress(acct.BillingStreet, acct.BillingCity, acct.BillingCountry);
    media.photoUrls = new List<String>();
    media.hasGoogleKey = DistributorGeocodeService.hasGoogleApiKey();
    media.staticMapUrl = buildStaticMapUrl(acct.BillingLatitude, acct.BillingLongitude);

    String apiKey = resolveApiKey();
    if (acct.BillingLatitude != null && acct.BillingLongitude != null && String.isNotBlank(apiKey)) {
      media.streetViewUrl =
        'https://maps.googleapis.com/maps/api/streetview?size=640x360&location=' +
        String.valueOf(acct.BillingLatitude) +
        ',' +
        String.valueOf(acct.BillingLongitude) +
        '&fov=80&pitch=0&key=' +
        EncodingUtil.urlEncode(apiKey, 'UTF-8');
    }

    if (String.isNotBlank(acct.Maps_Place_Id__c) && String.isNotBlank(apiKey)) {
      media.photoUrls.addAll(loadPlacePhotoUrls(acct.Maps_Place_Id__c, apiKey, 4));
    }

    if (
      media.streetViewUrl == null &&
      media.staticMapUrl == null &&
      (media.photoUrls == null || media.photoUrls.isEmpty())
    ) {
      media.message = media.hasGoogleKey
        ? 'No map location yet. Geocode the billing address, then enrich maps phone.'
        : 'Add a Google Places/Geocoding API key on Distributor Geocode Config to load Street View and place photos. A static OpenStreetMap preview is used when coordinates exist.';
    }
    return media;
  }

  @AuraEnabled
  public static EnrichmentResult enrichAccount(Id accountId) {
    Account acct = [
      SELECT
        Id,
        Name,
        BillingStreet,
        BillingCity,
        BillingCountry,
        BillingLatitude,
        BillingLongitude,
        Maps_Phone_Number__c,
        Maps_Place_Id__c
      FROM Account
      WHERE Id = :accountId
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    EnrichmentResult result = enrichAccountRecord(acct);
    Account updateRow = new Account(
      Id = acct.Id,
      Maps_Enrichment_Status__c = result.status,
      Maps_Last_Enriched__c = System.now()
    );
    if (String.isNotBlank(result.phone)) {
      updateRow.Maps_Phone_Number__c = result.phone;
    }
    if (String.isNotBlank(result.placeId)) {
      updateRow.Maps_Place_Id__c = result.placeId;
    }
    Database.DmlOptions opts = new Database.DmlOptions();
    opts.duplicateRuleHeader.allowSave = true;
    opts.optAllOrNone = false;
    Database.update(new List<Account>{ updateRow }, opts);
    return result;
  }

  public static EnrichmentResult enrichAccountRecord(Account acct) {
    EnrichmentResult result = new EnrichmentResult();
    String apiKey = resolveApiKey();
    if (String.isNotBlank(apiKey)) {
      EnrichmentResult places = enrichFromGooglePlaces(acct, apiKey);
      if (places != null && String.isNotBlank(places.phone)) {
        return places;
      }
      if (places != null) {
        result = places;
      }
    } else {
      result.status = 'Needs API Key';
      result.message = 'Google Places API key is not configured on Distributor Geocode Config.';
    }

    EnrichmentResult osm = enrichFromOverpass(acct);
    if (osm != null && String.isNotBlank(osm.phone)) {
      return osm;
    }
    if (result.status == null || result.status == 'Needs API Key') {
      if (osm != null) {
        return osm;
      }
      if (String.isBlank(apiKey)) {
        result.status = 'Needs API Key';
        result.message = 'Configure Google Places API key (or wait for OSM phone tags near the location).';
        return result;
      }
    }
    if (String.isBlank(result.status)) {
      result.status = 'Not Found';
      result.message = 'No public phone found for this location.';
    }
    return result;
  }

  private static EnrichmentResult enrichFromGooglePlaces(Account acct, String apiKey) {
    EnrichmentResult result = new EnrichmentResult();
    result.provider = 'Google Places';
    String query = buildSearchQuery(acct);
    if (String.isBlank(query)) {
      result.status = 'Not Found';
      result.message = 'Account needs a name or address to search Places.';
      return result;
    }
    String findUrl =
      'callout:Google_Geocoding/maps/api/place/findplacefromtext/json?input=' +
      EncodingUtil.urlEncode(query, 'UTF-8') +
      '&inputtype=textquery&fields=place_id,name,formatted_phone_number,geometry&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    if (acct.BillingLatitude != null && acct.BillingLongitude != null) {
      findUrl +=
        '&locationbias=point:' +
        String.valueOf(acct.BillingLatitude) +
        ',' +
        String.valueOf(acct.BillingLongitude);
    }
    HttpResponse findResp = httpGet(findUrl);
    if (findResp == null || findResp.getStatusCode() >= 400) {
      result.status = 'Error';
      result.message = 'Google Places find request failed.';
      return result;
    }
    Map<String, Object> findBody = (Map<String, Object>) JSON.deserializeUntyped(findResp.getBody());
    String status = (String) findBody.get('status');
    if (status != 'OK' && status != 'ZERO_RESULTS') {
      result.status = 'Error';
      result.message = 'Google Places status: ' + status;
      return result;
    }
    List<Object> candidates = (List<Object>) findBody.get('candidates');
    if (candidates == null || candidates.isEmpty()) {
      result.status = 'Not Found';
      result.message = 'No Places match for this account.';
      return result;
    }
    Map<String, Object> first = (Map<String, Object>) candidates[0];
    String placeId = (String) first.get('place_id');
    String phone = (String) first.get('formatted_phone_number');
    result.placeId = placeId;
    if (String.isBlank(phone) && String.isNotBlank(placeId)) {
      phone = loadPlacePhone(placeId, apiKey);
    }
    result.phone = normalizePhone(phone);
    result.status = String.isNotBlank(result.phone) ? 'Found' : 'Not Found';
    result.message = result.status == 'Found' ? null : 'Place found but no phone number published.';
    return result;
  }

  private static String loadPlacePhone(String placeId, String apiKey) {
    String detailsUrl =
      'callout:Google_Geocoding/maps/api/place/details/json?place_id=' +
      EncodingUtil.urlEncode(placeId, 'UTF-8') +
      '&fields=formatted_phone_number,international_phone_number&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    HttpResponse resp = httpGet(detailsUrl);
    if (resp == null || resp.getStatusCode() >= 400) {
      return null;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    Map<String, Object> result = (Map<String, Object>) body.get('result');
    if (result == null) {
      return null;
    }
    String international = (String) result.get('international_phone_number');
    if (String.isNotBlank(international)) {
      return international;
    }
    return (String) result.get('formatted_phone_number');
  }

  private static List<String> loadPlacePhotoUrls(String placeId, String apiKey, Integer maxPhotos) {
    List<String> urls = new List<String>();
    String detailsUrl =
      'callout:Google_Geocoding/maps/api/place/details/json?place_id=' +
      EncodingUtil.urlEncode(placeId, 'UTF-8') +
      '&fields=photos&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    HttpResponse resp = httpGet(detailsUrl);
    if (resp == null || resp.getStatusCode() >= 400) {
      return urls;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    Map<String, Object> result = (Map<String, Object>) body.get('result');
    if (result == null || result.get('photos') == null) {
      return urls;
    }
    List<Object> photos = (List<Object>) result.get('photos');
    Integer limitSize = Math.min(maxPhotos, photos.size());
    for (Integer i = 0; i < limitSize; i++) {
      Map<String, Object> photo = (Map<String, Object>) photos[i];
      String photoRef = (String) photo.get('photo_reference');
      if (String.isBlank(photoRef)) {
        continue;
      }
      urls.add(
        'https://maps.googleapis.com/maps/api/place/photo?maxwidth=800&photo_reference=' +
          EncodingUtil.urlEncode(photoRef, 'UTF-8') +
          '&key=' +
          EncodingUtil.urlEncode(apiKey, 'UTF-8')
      );
    }
    return urls;
  }

  private static EnrichmentResult enrichFromOverpass(Account acct) {
    EnrichmentResult result = new EnrichmentResult();
    result.provider = 'OpenStreetMap';
    if (acct.BillingLatitude == null || acct.BillingLongitude == null) {
      result.status = 'Not Found';
      result.message = 'No coordinates for OSM phone lookup.';
      return result;
    }
    String lat = String.valueOf(acct.BillingLatitude);
    String lon = String.valueOf(acct.BillingLongitude);
    String query =
      '[out:json][timeout:25];(' +
      'node(around:80,' +
      lat +
      ',' +
      lon +
      ')[~"phone|contact:phone|contact:mobile"~"."];' +
      'way(around:80,' +
      lat +
      ',' +
      lon +
      ')[~"phone|contact:phone|contact:mobile"~"."];' +
      ');out tags center 8;';
    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://overpass-api.de/api/interpreter');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.setTimeout(20000);
    req.setBody('data=' + EncodingUtil.urlEncode(query, 'UTF-8'));
    HttpResponse resp;
    try {
      resp = new Http().send(req);
    } catch (Exception e) {
      result.status = 'Error';
      result.message = 'OSM Overpass call failed: ' + e.getMessage();
      return result;
    }
    if (resp.getStatusCode() >= 400) {
      result.status = 'Error';
      result.message = 'OSM Overpass HTTP ' + resp.getStatusCode();
      return result;
    }
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    List<Object> elements = (List<Object>) body.get('elements');
    if (elements == null || elements.isEmpty()) {
      result.status = 'Not Found';
      result.message = 'No OSM phone tags near this location.';
      return result;
    }
    for (Object elObj : elements) {
      Map<String, Object> el = (Map<String, Object>) elObj;
      Map<String, Object> tags = (Map<String, Object>) el.get('tags');
      if (tags == null) {
        continue;
      }
      for (String key : new List<String>{ 'phone', 'contact:phone', 'contact:mobile' }) {
        String phone = normalizePhone((String) tags.get(key));
        if (String.isNotBlank(phone)) {
          result.phone = phone;
          result.status = 'Found';
          return result;
        }
      }
    }
    result.status = 'Not Found';
    result.message = 'OSM features nearby had no usable phone.';
    return result;
  }

  private static String buildSearchQuery(Account acct) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(acct.Name)) {
      parts.add(acct.Name.trim());
    }
    if (String.isNotBlank(acct.BillingStreet)) {
      parts.add(acct.BillingStreet.trim());
    }
    if (String.isNotBlank(acct.BillingCity)) {
      parts.add(acct.BillingCity.trim());
    }
    if (String.isNotBlank(acct.BillingCountry)) {
      parts.add(acct.BillingCountry.trim());
    } else {
      parts.add('Egypt');
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static String buildAddress(String street, String city, String country) {
    List<String> parts = new List<String>();
    if (String.isNotBlank(street)) {
      parts.add(street);
    }
    if (String.isNotBlank(city)) {
      parts.add(city);
    }
    if (String.isNotBlank(country)) {
      parts.add(country);
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static String buildStaticMapUrl(Decimal lat, Decimal lon) {
    if (lat == null || lon == null) {
      return null;
    }
    return 'https://staticmap.openstreetmap.de/staticmap.php?center=' +
      String.valueOf(lat) +
      ',' +
      String.valueOf(lon) +
      '&zoom=17&size=640x360&markers=' +
      String.valueOf(lat) +
      ',' +
      String.valueOf(lon) +
      ',lightblue1';
  }

  private static HttpResponse httpGet(String endpoint) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('GET');
    req.setTimeout(20000);
    try {
      return new Http().send(req);
    } catch (Exception e) {
      return null;
    }
  }

  private static String resolveApiKey() {
    Distributor_Geocode_Config__c cfg = Distributor_Geocode_Config__c.getOrgDefaults();
    if (cfg != null && String.isNotBlank(cfg.Google_API_Key__c)) {
      return cfg.Google_API_Key__c;
    }
    return null;
  }

  private static String normalizePhone(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String egypt = AccountCreateQualityService.normalizeEgyptPhone(raw);
    return String.isBlank(egypt) ? raw.trim().left(40) : egypt;
  }

  public static List<PlaceCandidate> searchPlaces(String query, String recordTypeHint) {
    return searchPlaces(query, recordTypeHint, null);
  }

  public static List<PlaceCandidate> searchPlaces(
    String query,
    String recordTypeHint,
    PlaceGeoBias geoBias
  ) {
    List<PlaceCandidate> results = new List<PlaceCandidate>();
    if (String.isBlank(query)) {
      return results;
    }
    PlaceGeoBias bias = completeGeoBias(geoBias);
    String rawQuery = query.trim();
    String apiKey = resolveApiKey();
    List<String> phoneVariants = AccountCreateQualityService.egyptPhoneSearchQueries(rawQuery);
    if (!phoneVariants.isEmpty()) {
      results.addAll(searchPlacesByPhone(phoneVariants, apiKey, bias));
    } else {
      String typeHint = String.isBlank(recordTypeHint) ? '' : recordTypeHint.toLowerCase();
      String googleQuery = applyGeoQueryBias(rawQuery, bias);
      String nominatimQuery = applyGeoQueryBias(rawQuery, bias);
      if (String.isNotBlank(apiKey)) {
        results.addAll(safeSearchGoogle(googleQuery, apiKey, bias));
        String hinted = applyTypeHint(rawQuery, typeHint);
        if (hinted != rawQuery) {
          results.addAll(safeSearchGoogle(applyGeoQueryBias(hinted, bias), apiKey, bias));
        }
        hydrateGooglePlaceDetails(results, apiKey, 5);
      }
      results.addAll(safeSearchNominatim(nominatimQuery, bias));
      if (results.size() < 8) {
        results.addAll(safeSearchOverpass(rawQuery, typeHint, bias));
      }
    }
    results = preferPhoneMatches(results, phoneVariants);
    results = filterByGeoBias(results, bias);
    results = dedupePlaces(results);
    for (PlaceCandidate row : results) {
      applyPlaceKind(row);
    }
    Integer take = Math.min(25, results.size());
    List<PlaceCandidate> limited = new List<PlaceCandidate>();
    for (Integer i = 0; i < take; i++) {
      PlaceCandidate row = results[i];
      row.staticMapUrl = buildStaticMapUrl(row.latitude, row.longitude);
      limited.add(row);
    }
    return limited;
  }

  private static List<PlaceCandidate> searchPlacesByPhone(
    List<String> phoneVariants,
    String apiKey,
    PlaceGeoBias bias
  ) {
    List<PlaceCandidate> results = new List<PlaceCandidate>();
    if (phoneVariants == null || phoneVariants.isEmpty()) {
      return results;
    }
    if (String.isNotBlank(apiKey)) {
      results.addAll(safeSearchGoogleByPhone(phoneVariants, apiKey, bias));
    }
    results.addAll(safeSearchNominatimByPhone(phoneVariants, bias));
    if (results.size() < 8) {
      results.addAll(safeSearchOverpassByPhone(phoneVariants, bias));
    }
    return results;
  }

  private static List<PlaceCandidate> preferPhoneMatches(
    List<PlaceCandidate> rows,
    List<String> phoneVariants
  ) {
    if (rows == null || rows.isEmpty() || phoneVariants == null || phoneVariants.isEmpty()) {
      return rows == null ? new List<PlaceCandidate>() : rows;
    }
    String needle = phoneVariants[0];
    List<PlaceCandidate> matched = new List<PlaceCandidate>();
    List<PlaceCandidate> rest = new List<PlaceCandidate>();
    for (PlaceCandidate row : rows) {
      if (row != null && AccountCreateQualityService.phonesMatch(needle, row.phone)) {
        matched.add(row);
      } else {
        rest.add(row);
      }
    }
    matched.addAll(rest);
    return matched;
  }

  private static String applyTypeHint(String query, String typeHint) {
    String q = query;
    String lower = q.toLowerCase();
    if (typeHint.contains('pharmacy') && !lower.contains('pharmac')) {
      q += ' pharmacy';
    } else if (
      (typeHint.contains('person') || typeHint.contains('hcp') || typeHint.contains('medical')) &&
      !lower.contains('doctor')
    ) {
      q += ' doctor';
    } else if (typeHint.contains('institution') || typeHint.contains('hco')) {
      if (!lower.contains('hospital') && !lower.contains('clinic')) {
        q += ' hospital';
      }
    }
    return q;
  }

  private static String applyEgyptBias(String query) {
    String lower = query.toLowerCase();
    if (!lower.contains('egypt') && !query.contains('\u0645\u0635\u0631')) {
      return query + ' Egypt';
    }
    return query;
  }

  private static List<PlaceCandidate> safeSearchGoogle(String query, String apiKey, PlaceGeoBias bias) {
    try {
      return searchGoogleText(query, apiKey, bias);
    } catch (Exception e) {
      return new List<PlaceCandidate>();
    }
  }

  private static List<PlaceCandidate> safeSearchNominatim(String query, PlaceGeoBias bias) {
    try {
      return searchNominatim(query, bias);
    } catch (Exception e) {
      return new List<PlaceCandidate>();
    }
  }

  private static List<PlaceCandidate> safeSearchOverpass(String query, String typeHint, PlaceGeoBias bias) {
    try {
      return searchOverpassByName(query, typeHint, bias);
    } catch (Exception e) {
      return new List<PlaceCandidate>();
    }
  }

  private static List<PlaceCandidate> safeSearchGoogleByPhone(
    List<String> variants,
    String apiKey,
    PlaceGeoBias bias
  ) {
    try {
      return searchGoogleByPhone(variants, apiKey, bias);
    } catch (Exception e) {
      return new List<PlaceCandidate>();
    }
  }

  private static List<PlaceCandidate> safeSearchNominatimByPhone(List<String> variants, PlaceGeoBias bias) {
    List<PlaceCandidate> rows = new List<PlaceCandidate>();
    Integer tried = 0;
    for (String variant : variants) {
      if (String.isBlank(variant) || tried >= 3) {
        continue;
      }
      tried++;
      try {
        rows.addAll(searchNominatim(variant, bias));
      } catch (Exception e) {
        continue;
      }
    }
    return rows;
  }

  private static List<PlaceCandidate> safeSearchOverpassByPhone(List<String> variants, PlaceGeoBias bias) {
    try {
      return searchOverpassByPhone(variants, bias);
    } catch (Exception e) {
      return new List<PlaceCandidate>();
    }
  }

  private static List<PlaceCandidate> searchGoogleByPhone(
    List<String> variants,
    String apiKey,
    PlaceGeoBias bias
  ) {
    List<PlaceCandidate> rows = new List<PlaceCandidate>();
    Set<String> seenPlaceIds = new Set<String>();
    String e164;
    for (String variant : variants) {
      if (String.isNotBlank(variant) && variant.startsWith('+')) {
        e164 = variant;
        break;
      }
    }
    if (String.isBlank(e164) && !variants.isEmpty()) {
      e164 = AccountCreateQualityService.normalizeEgyptPhone(variants[0]);
    }
    if (String.isNotBlank(e164)) {
      String findUrl =
        'callout:Google_Geocoding/maps/api/place/findplacefromtext/json?input=' +
        EncodingUtil.urlEncode(e164, 'UTF-8') +
        '&inputtype=phonenumber&fields=place_id,name,formatted_address,geometry&key=' +
        EncodingUtil.urlEncode(apiKey, 'UTF-8') +
        googleLocationBiasParam(bias);
      HttpResponse findResp = httpGet(findUrl);
      if (findResp != null && findResp.getStatusCode() < 400 && String.isNotBlank(findResp.getBody())) {
        try {
          Map<String, Object> findBody = (Map<String, Object>) JSON.deserializeUntyped(findResp.getBody());
          List<Object> candidates = (List<Object>) findBody.get('candidates');
          if (candidates != null) {
            for (Object raw : candidates) {
              Map<String, Object> item = (Map<String, Object>) raw;
              String placeId = (String) item.get('place_id');
              PlaceCandidate row = placeFromGoogleItem(item, 'Google Places');
              if (String.isNotBlank(placeId)) {
                PlaceCandidate details = loadPlaceCandidateDetails(placeId, apiKey);
                if (details != null) {
                  if (String.isBlank(row.name)) {
                    row.name = details.name;
                  }
                  if (String.isBlank(row.address)) {
                    row.address = details.address;
                  }
                  row.phone = details.phone;
                  if (row.latitude == null) {
                    row.latitude = details.latitude;
                    row.longitude = details.longitude;
                  }
                }
                seenPlaceIds.add(placeId);
              }
              if (row.latitude != null && row.longitude != null && String.isNotBlank(row.name)) {
                rows.add(row);
              }
            }
          }
        } catch (Exception e) {
          // Fall through to text search.
        }
      }
    }
    Integer textTries = 0;
    for (String variant : variants) {
      if (String.isBlank(variant) || textTries >= 2) {
        continue;
      }
      textTries++;
      for (PlaceCandidate row : searchGoogleText(variant, apiKey, bias)) {
        if (String.isNotBlank(row.placeId) && seenPlaceIds.contains(row.placeId)) {
          continue;
        }
        if (String.isNotBlank(row.placeId)) {
          seenPlaceIds.add(row.placeId);
        }
        rows.add(row);
      }
    }
    hydrateGooglePlaceDetails(rows, apiKey, 5);
    return rows;
  }

  private static PlaceCandidate placeFromGoogleItem(Map<String, Object> item, String provider) {
    PlaceCandidate row = new PlaceCandidate();
    if (item == null) {
      return row;
    }
    row.placeId = (String) item.get('place_id');
    row.name = (String) item.get('name');
    row.address = (String) item.get('formatted_address');
    row.provider = provider;
    Map<String, Object> geometry = (Map<String, Object>) item.get('geometry');
    if (geometry != null && geometry.get('location') != null) {
      Map<String, Object> location = (Map<String, Object>) geometry.get('location');
      row.latitude = toDecimal(location.get('lat'));
      row.longitude = toDecimal(location.get('lng'));
    }
    copyGoogleClassification(row, item);
    return row;
  }

  private static PlaceCandidate loadPlaceCandidateDetails(String placeId, String apiKey) {
    if (String.isBlank(placeId) || String.isBlank(apiKey)) {
      return null;
    }
    String detailsUrl =
      'callout:Google_Geocoding/maps/api/place/details/json?place_id=' +
      EncodingUtil.urlEncode(placeId, 'UTF-8') +
      '&fields=name,formatted_address,formatted_phone_number,international_phone_number,geometry,types,rating,user_ratings_total&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8');
    HttpResponse resp = httpGet(detailsUrl);
    if (resp == null || resp.getStatusCode() >= 400 || String.isBlank(resp.getBody())) {
      return null;
    }
    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    } catch (Exception e) {
      return null;
    }
    Map<String, Object> result = body == null ? null : (Map<String, Object>) body.get('result');
    if (result == null) {
      return null;
    }
    PlaceCandidate row = placeFromGoogleItem(result, 'Google Places');
    row.placeId = placeId;
    String international = (String) result.get('international_phone_number');
    String formatted = (String) result.get('formatted_phone_number');
    row.phone = normalizePhone(String.isNotBlank(international) ? international : formatted);
    copyGoogleClassification(row, result);
    return row;
  }

  private static void hydrateGooglePlaceDetails(
    List<PlaceCandidate> rows,
    String apiKey,
    Integer maxDetails
  ) {
    if (rows == null || rows.isEmpty() || String.isBlank(apiKey) || maxDetails == null || maxDetails < 1) {
      return;
    }
    Integer loaded = 0;
    for (PlaceCandidate row : rows) {
      if (loaded >= maxDetails) {
        break;
      }
      if (row == null || String.isBlank(row.placeId) || row.placeId.startsWith('osm') || row.placeId.startsWith('overpass')) {
        continue;
      }
      if (String.isNotBlank(row.phone) && row.latitude != null) {
        continue;
      }
      PlaceCandidate details = loadPlaceCandidateDetails(row.placeId, apiKey);
      loaded++;
      if (details == null) {
        continue;
      }
      if (String.isBlank(row.phone)) {
        row.phone = details.phone;
      }
      if (String.isBlank(row.address)) {
        row.address = details.address;
      }
      if (String.isBlank(row.name)) {
        row.name = details.name;
      }
      if (row.latitude == null) {
        row.latitude = details.latitude;
        row.longitude = details.longitude;
      }
      if (row.googleTypes == null || row.googleTypes.isEmpty()) {
        row.googleTypes = details.googleTypes;
      }
      if (row.rating == null) {
        row.rating = details.rating;
        row.ratingCount = details.ratingCount;
      }
    }
  }

  private static List<PlaceCandidate> searchOverpassByPhone(List<String> variants, PlaceGeoBias bias) {
    List<PlaceCandidate> rows = new List<PlaceCandidate>();
    String digits = null;
    for (String variant : variants) {
      String candidate = AccountCreateQualityService.phoneDigits(variant);
      if (String.isNotBlank(candidate) && candidate.length() >= 8) {
        digits = candidate.right(Math.min(10, candidate.length()));
        break;
      }
    }
    if (String.isBlank(digits)) {
      return rows;
    }
    String safe = digits.replaceAll('[^0-9]', '');
    if (safe.length() < 8) {
      return rows;
    }
    String bbox = overpassBbox(bias);
    String overpassQuery =
      '[out:json][timeout:10];(' +
      'node[~"^(phone|contact:phone|contact:mobile)$"~"' +
      safe +
      '"]' +
      bbox +
      ';' +
      'way[~"^(phone|contact:phone|contact:mobile)$"~"' +
      safe +
      '"]' +
      bbox +
      ';' +
      ');out center 20;';
    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://overpass-api.de/api/interpreter');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.setTimeout(12000);
    req.setBody('data=' + EncodingUtil.urlEncode(overpassQuery, 'UTF-8'));
    HttpResponse resp;
    try {
      resp = new Http().send(req);
    } catch (Exception e) {
      return rows;
    }
    if (resp == null || resp.getStatusCode() >= 400 || String.isBlank(resp.getBody())) {
      return rows;
    }
    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    } catch (Exception e) {
      return rows;
    }
    if (body == null) {
      return rows;
    }
    List<Object> elements = (List<Object>) body.get('elements');
    if (elements == null) {
      return rows;
    }
    Integer take = Math.min(20, elements.size());
    for (Integer i = 0; i < take; i++) {
      Map<String, Object> el = (Map<String, Object>) elements[i];
      Map<String, Object> tags = (Map<String, Object>) el.get('tags');
      PlaceCandidate row = new PlaceCandidate();
      String elType = el.get('type') != null ? String.valueOf(el.get('type')) : 'node';
      String elId = el.get('id') != null ? String.valueOf(el.get('id')) : String.valueOf(i);
      row.placeId = 'overpass:' + elType + '/' + elId;
      row.provider = 'OpenStreetMap';
      if (tags != null) {
        row.name = (String) tags.get('name');
        row.phone = normalizePhone((String) tags.get('phone'));
        if (String.isBlank(row.phone)) {
          row.phone = normalizePhone((String) tags.get('contact:phone'));
        }
        if (String.isBlank(row.phone)) {
          row.phone = normalizePhone((String) tags.get('contact:mobile'));
        }
        row.address = overpassAddress(tags);
        row.osmAmenity = (String) tags.get('amenity');
        row.osmOffice = (String) tags.get('office');
      }
      row.latitude = toDecimal(el.get('lat'));
      row.longitude = toDecimal(el.get('lon'));
      if ((row.latitude == null || row.longitude == null) && el.get('center') != null) {
        Map<String, Object> center = (Map<String, Object>) el.get('center');
        row.latitude = toDecimal(center.get('lat'));
        row.longitude = toDecimal(center.get('lon'));
      }
      if (row.latitude != null && row.longitude != null && String.isNotBlank(row.name)) {
        rows.add(row);
      }
    }
    return rows;
  }

  private static List<PlaceCandidate> searchGoogleText(String query, String apiKey, PlaceGeoBias bias) {
    List<PlaceCandidate> rows = new List<PlaceCandidate>();
    String endpoint =
      'callout:Google_Geocoding/maps/api/place/textsearch/json?query=' +
      EncodingUtil.urlEncode(query, 'UTF-8') +
      '&region=eg&key=' +
      EncodingUtil.urlEncode(apiKey, 'UTF-8') +
      googleLocationParam(bias);
    HttpResponse resp = httpGet(endpoint);
    if (resp == null || resp.getStatusCode() >= 400 || String.isBlank(resp.getBody())) {
      return rows;
    }
    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    } catch (Exception e) {
      return rows;
    }
    if (body == null || (String) body.get('status') != 'OK') {
      return rows;
    }
    List<Object> results = (List<Object>) body.get('results');
    if (results == null) {
      return rows;
    }
    Integer take = Math.min(15, results.size());
    for (Integer i = 0; i < take; i++) {
      Map<String, Object> item = (Map<String, Object>) results[i];
      PlaceCandidate row = new PlaceCandidate();
      row.placeId = (String) item.get('place_id');
      row.name = (String) item.get('name');
      row.address = (String) item.get('formatted_address');
      row.provider = 'Google Places';
      Map<String, Object> geometry = (Map<String, Object>) item.get('geometry');
      if (geometry != null && geometry.get('location') != null) {
        Map<String, Object> location = (Map<String, Object>) geometry.get('location');
        row.latitude = toDecimal(location.get('lat'));
        row.longitude = toDecimal(location.get('lng'));
      }
      copyGoogleClassification(row, item);
      if (row.latitude != null && row.longitude != null && String.isNotBlank(row.name)) {
        rows.add(row);
      }
    }
    return rows;
  }

  private static List<PlaceCandidate> searchNominatim(String query, PlaceGeoBias bias) {
    List<PlaceCandidate> rows = new List<PlaceCandidate>();
    String endpoint =
      'callout:OpenStreetMap_Nominatim/search?q=' +
      EncodingUtil.urlEncode(query, 'UTF-8') +
      '&format=json&limit=20&countrycodes=eg&addressdetails=1&extratags=1&dedupe=0' +
      nominatimViewboxParam(bias);
    HttpRequest req = new HttpRequest();
    req.setEndpoint(endpoint);
    req.setMethod('GET');
    req.setTimeout(20000);
    req.setHeader('User-Agent', 'ZetaPharma-AccountsTab/1.0');
    req.setHeader('Accept-Language', 'en');
    HttpResponse resp;
    try {
      resp = new Http().send(req);
    } catch (Exception e) {
      return rows;
    }
    if (resp == null || resp.getStatusCode() >= 400 || String.isBlank(resp.getBody())) {
      return rows;
    }
    String bodyText = resp.getBody().trim();
    if (!bodyText.startsWith('[')) {
      return rows;
    }
    List<Object> parsed = (List<Object>) JSON.deserializeUntyped(bodyText);
    for (Object raw : parsed) {
      Map<String, Object> item = (Map<String, Object>) raw;
      PlaceCandidate row = new PlaceCandidate();
      String osmType = item.get('osm_type') != null ? String.valueOf(item.get('osm_type')) : 'n';
      String osmId = item.get('osm_id') != null ? String.valueOf(item.get('osm_id')) : String.valueOf(item.get('place_id'));
      row.placeId = 'osm:' + osmType + '/' + osmId;
      row.name = (String) item.get('name');
      if (String.isBlank(row.name)) {
        row.name = (String) item.get('display_name');
      }
      row.address = (String) item.get('display_name');
      row.latitude = toDecimal(item.get('lat'));
      row.longitude = toDecimal(item.get('lon'));
      row.provider = 'OpenStreetMap';
      row.osmClass = (String) item.get('class');
      row.osmType = (String) item.get('type');
      Map<String, Object> extra = (Map<String, Object>) item.get('extratags');
      if (extra != null) {
        row.phone = normalizePhone((String) extra.get('phone'));
        row.osmAmenity = (String) extra.get('amenity');
        row.osmOffice = (String) extra.get('office');
      }
      if (row.latitude != null && row.longitude != null && String.isNotBlank(row.name)) {
        rows.add(row);
      }
    }
    return rows;
  }

  private static List<PlaceCandidate> searchOverpassByName(String query, String typeHint, PlaceGeoBias bias) {
    List<PlaceCandidate> rows = new List<PlaceCandidate>();
    String token = extractOverpassName(query);
    if (String.isBlank(token)) {
      return rows;
    }
    String amenities = overpassAmenities(typeHint);
    String bbox = overpassBbox(bias);
    String overpassQuery =
      '[out:json][timeout:10];(' +
      'node["name"~"' +
      token +
      '",i]["amenity"~"' +
      amenities +
      '"]' +
      bbox +
      ';' +
      'way["name"~"' +
      token +
      '",i]["amenity"~"' +
      amenities +
      '"]' +
      bbox +
      ';' +
      'node["name"~"' +
      token +
      '",i]["office"]' +
      bbox +
      ';' +
      'way["name"~"' +
      token +
      '",i]["office"]' +
      bbox +
      ';' +
      'node["name"~"' +
      token +
      '",i]["shop"]' +
      bbox +
      ';' +
      'way["name"~"' +
      token +
      '",i]["shop"]' +
      bbox +
      ';' +
      ');out center 20;';
    HttpRequest req = new HttpRequest();
    req.setEndpoint('https://overpass-api.de/api/interpreter');
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
    req.setTimeout(12000);
    req.setBody('data=' + EncodingUtil.urlEncode(overpassQuery, 'UTF-8'));
    HttpResponse resp;
    try {
      resp = new Http().send(req);
    } catch (Exception e) {
      return rows;
    }
    if (resp == null || resp.getStatusCode() >= 400 || String.isBlank(resp.getBody())) {
      return rows;
    }
    Map<String, Object> body;
    try {
      body = (Map<String, Object>) JSON.deserializeUntyped(resp.getBody());
    } catch (Exception e) {
      return rows;
    }
    if (body == null) {
      return rows;
    }
    List<Object> elements = (List<Object>) body.get('elements');
    if (elements == null) {
      return rows;
    }
    Integer take = Math.min(20, elements.size());
    for (Integer i = 0; i < take; i++) {
      Map<String, Object> el = (Map<String, Object>) elements[i];
      Map<String, Object> tags = (Map<String, Object>) el.get('tags');
      PlaceCandidate row = new PlaceCandidate();
      String elType = el.get('type') != null ? String.valueOf(el.get('type')) : 'node';
      String elId = el.get('id') != null ? String.valueOf(el.get('id')) : String.valueOf(i);
      row.placeId = 'overpass:' + elType + '/' + elId;
      row.provider = 'OpenStreetMap';
      if (tags != null) {
        row.name = (String) tags.get('name');
        row.phone = normalizePhone((String) tags.get('phone'));
        if (String.isBlank(row.phone)) {
          row.phone = normalizePhone((String) tags.get('contact:phone'));
        }
        row.address = overpassAddress(tags);
        row.osmAmenity = (String) tags.get('amenity');
        row.osmOffice = (String) tags.get('office');
      }
      row.latitude = toDecimal(el.get('lat'));
      row.longitude = toDecimal(el.get('lon'));
      if ((row.latitude == null || row.longitude == null) && el.get('center') != null) {
        Map<String, Object> center = (Map<String, Object>) el.get('center');
        row.latitude = toDecimal(center.get('lat'));
        row.longitude = toDecimal(center.get('lon'));
      }
      if (row.latitude != null && row.longitude != null && String.isNotBlank(row.name)) {
        rows.add(row);
      }
    }
    return rows;
  }

  private static String extractOverpassName(String query) {
    if (String.isBlank(query)) {
      return null;
    }
    String q = query.toLowerCase();
    for (String skip : new List<String>{
      'egypt',
      'doctor',
      'doctors',
      'pharmacy',
      'hospital',
      'clinic',
      'hcp',
      'hco'
    }) {
      q = q.replaceAll('\\b' + skip + '\\.?\\b', ' ');
    }
    q = q.replaceAll('^dr\\.?\\s+', ' ');
    q = q.replaceAll('[^a-z0-9\\u0600-\\u06FF\\s]', ' ').trim();
    String best = '';
    for (String part : q.split('\\s+')) {
      if (part.length() > best.length()) {
        best = part;
      }
    }
    return best.length() >= 3 ? best : null;
  }

  private static String overpassAmenities(String typeHint) {
    if (typeHint != null && typeHint.contains('pharmacy')) {
      return 'pharmacy';
    }
    if (
      typeHint != null &&
      (typeHint.contains('person') || typeHint.contains('hcp') || typeHint.contains('medical'))
    ) {
      return 'doctors|clinic|hospital';
    }
    if (typeHint != null && (typeHint.contains('institution') || typeHint.contains('hco'))) {
      return 'hospital|clinic|doctors';
    }
    return 'pharmacy|doctors|clinic|hospital';
  }

  private static String overpassAddress(Map<String, Object> tags) {
    if (tags == null) {
      return null;
    }
    if (String.isNotBlank((String) tags.get('addr:full'))) {
      return (String) tags.get('addr:full');
    }
    List<String> parts = new List<String>();
    for (String key : new List<String>{ 'addr:street', 'addr:city', 'addr:state' }) {
      String value = (String) tags.get(key);
      if (String.isNotBlank(value)) {
        parts.add(value);
      }
    }
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static List<PlaceCandidate> dedupePlaces(List<PlaceCandidate> input) {
    List<PlaceCandidate> output = new List<PlaceCandidate>();
    Set<String> seenIds = new Set<String>();
    Set<String> seenKeys = new Set<String>();
    for (PlaceCandidate row : input) {
      if (row == null || String.isBlank(row.name) || row.latitude == null || row.longitude == null) {
        continue;
      }
      if (String.isNotBlank(row.placeId) && seenIds.contains(row.placeId)) {
        continue;
      }
      String key =
        row.name.trim().toLowerCase() +
        '|' +
        String.valueOf(row.latitude.setScale(3)) +
        '|' +
        String.valueOf(row.longitude.setScale(3));
      if (seenKeys.contains(key)) {
        continue;
      }
      if (String.isNotBlank(row.placeId)) {
        seenIds.add(row.placeId);
      }
      seenKeys.add(key);
      output.add(row);
    }
    return output;
  }

  private static void copyGoogleClassification(PlaceCandidate row, Map<String, Object> item) {
    if (row == null || item == null) {
      return;
    }
    row.rating = toDecimal(item.get('rating'));
    Object ratingTotal = item.get('user_ratings_total');
    if (ratingTotal instanceof Integer) {
      row.ratingCount = (Integer) ratingTotal;
    } else if (ratingTotal instanceof Decimal) {
      row.ratingCount = ((Decimal) ratingTotal).intValue();
    } else if (ratingTotal != null) {
      try {
        row.ratingCount = Integer.valueOf(String.valueOf(ratingTotal));
      } catch (Exception e) {
        row.ratingCount = null;
      }
    }
    List<Object> rawTypes = (List<Object>) item.get('types');
    if (rawTypes == null || rawTypes.isEmpty()) {
      return;
    }
    row.googleTypes = new List<String>();
    for (Object rawType : rawTypes) {
      if (rawType != null) {
        row.googleTypes.add(String.valueOf(rawType));
      }
    }
  }

  @TestVisible
  static void applyPlaceKind(PlaceCandidate row) {
    if (row == null) {
      return;
    }
    String kind = classifyPlaceKind(row);
    row.placeKind = kind;
    row.placeKindLabel = placeKindLabel(kind);
  }

  @TestVisible
  static String classifyPlaceKind(PlaceCandidate row) {
    Set<String> types = new Set<String>();
    if (row.googleTypes != null) {
      for (String googleType : row.googleTypes) {
        if (String.isNotBlank(googleType)) {
          types.add(googleType.toLowerCase());
        }
      }
    }
    String amenity = blankToEmpty(row.osmAmenity).toLowerCase();
    String office = blankToEmpty(row.osmOffice).toLowerCase();
    String osmClass = blankToEmpty(row.osmClass).toLowerCase();
    String osmType = blankToEmpty(row.osmType).toLowerCase();
    String name = blankToEmpty(row.name).toLowerCase();

    if (
      types.contains('pharmacy') ||
      types.contains('drugstore') ||
      amenity == 'pharmacy' ||
      osmType == 'pharmacy' ||
      name.contains('pharmacy') ||
      name.contains('\u0635\u064a\u062f\u0644')
    ) {
      return 'pharmacy';
    }
    if (
      types.contains('doctor') ||
      types.contains('dentist') ||
      types.contains('physiotherapist') ||
      amenity == 'doctors' ||
      amenity == 'dentist' ||
      osmType == 'doctors' ||
      name.startsWith('dr ') ||
      name.startsWith('dr.') ||
      name.contains(' doctor') ||
      name.contains('\u062f\u0643\u062a\u0648\u0631')
    ) {
      return 'doctor';
    }
    if (
      types.contains('hospital') ||
      types.contains('clinic') ||
      amenity == 'hospital' ||
      amenity == 'clinic' ||
      osmType == 'hospital' ||
      osmType == 'clinic' ||
      name.contains('hospital') ||
      name.contains('clinic') ||
      name.contains('\u0645\u0633\u062a\u0634\u0641') ||
      name.contains('\u0639\u064a\u0627\u062f')
    ) {
      return 'hco';
    }
    if (
      String.isNotBlank(office) ||
      osmClass == 'office' ||
      osmClass == 'shop' ||
      osmClass == 'craft' ||
      osmClass == 'industrial' ||
      types.contains('finance') ||
      types.contains('insurance_agency') ||
      types.contains('real_estate_agency') ||
      types.contains('electronics_store') ||
      types.contains('store') ||
      types.contains('general_contractor') ||
      types.contains('bank') ||
      types.contains('accounting') ||
      name.contains('systems') ||
      name.contains('company') ||
      name.contains('consult') ||
      name.contains('technologies') ||
      name.contains('software') ||
      name.contains('ltd') ||
      name.contains('corp')
    ) {
      return 'company';
    }
    if (types.contains('establishment') || types.contains('point_of_interest')) {
      return 'company';
    }
    return 'unknown';
  }

  private static String placeKindLabel(String kind) {
    if (kind == 'doctor') {
      return 'Doctor';
    }
    if (kind == 'pharmacy') {
      return 'Pharmacy';
    }
    if (kind == 'hco') {
      return 'HCO';
    }
    if (kind == 'company') {
      return 'Company';
    }
    return 'Unknown';
  }

  private static String blankToEmpty(String value) {
    return value == null ? '' : value;
  }

  private static Decimal toDecimal(Object raw) {
    if (raw == null) {
      return null;
    }
    if (raw instanceof Decimal) {
      return (Decimal) raw;
    }
    try {
      return Decimal.valueOf(String.valueOf(raw));
    } catch (Exception e) {
      return null;
    }
  }

  public static PlaceGeoBias completeGeoBias(PlaceGeoBias input) {
    if (input == null) {
      return null;
    }
    Boolean hasNames =
      String.isNotBlank(input.zoneName) ||
      String.isNotBlank(input.brickName) ||
      String.isNotBlank(input.areaName);
    Boolean hasPoint = input.latitude != null && input.longitude != null;
    if (!hasNames && !hasPoint) {
      return null;
    }
    PlaceGeoBias bias = new PlaceGeoBias();
    bias.zoneName = input.zoneName;
    bias.brickName = input.brickName;
    bias.areaName = input.areaName;
    bias.latitude = input.latitude;
    bias.longitude = input.longitude;
    bias.radiusMeters = input.radiusMeters;
    bias.addressTokens = new List<String>();
    addBiasTokens(bias.addressTokens, input.areaName);
    addBiasTokens(bias.addressTokens, input.brickName);
    addBiasTokens(bias.addressTokens, input.zoneName);

    if (!hasPoint) {
      GeoCentroid centroid = inferCentroid(input.areaName, input.brickName, input.zoneName);
      if (centroid != null) {
        bias.latitude = centroid.latitude;
        bias.longitude = centroid.longitude;
        if (bias.radiusMeters == null) {
          bias.radiusMeters = centroid.radiusMeters;
        }
      }
    }
    if (bias.radiusMeters == null) {
      if (String.isNotBlank(input.brickName) && input.brickName.toLowerCase().contains('brick') == false) {
        bias.radiusMeters = 8000;
      } else if (String.isNotBlank(input.brickName)) {
        bias.radiusMeters = 18000;
      } else if (String.isNotBlank(input.zoneName)) {
        bias.radiusMeters = 40000;
      } else {
        bias.radiusMeters = 55000;
      }
    }
    if (bias.radiusMeters > 50000) {
      bias.radiusMeters = 50000;
    }
    fillBiasBounds(bias);
    bias.bounded = bias.radiusMeters != null && bias.radiusMeters <= 20000;
    return bias.latitude == null && bias.addressTokens.isEmpty() ? null : bias;
  }

  private static void addBiasTokens(List<String> tokens, String raw) {
    if (String.isBlank(raw) || tokens == null) {
      return;
    }
    String cleaned = cleanBrickLabel(raw);
    if (String.isBlank(cleaned)) {
      return;
    }
    Set<String> seen = new Set<String>();
    for (String existing : tokens) {
      seen.add(existing.toLowerCase());
    }
    String lower = cleaned.toLowerCase();
    if (!seen.contains(lower) && cleaned.length() >= 3) {
      tokens.add(cleaned);
      seen.add(lower);
    }
    for (String part : cleaned.split('[\\s,/\\-]+')) {
      String token = part.trim();
      if (token.length() < 4) {
        continue;
      }
      String key = token.toLowerCase();
      if (seen.contains(key)) {
        continue;
      }
      seen.add(key);
      tokens.add(token);
    }
    GeoCentroid inferred = lookupCentroid(cleaned);
    if (inferred != null && String.isNotBlank(inferred.label) && !seen.contains(inferred.label.toLowerCase())) {
      tokens.add(inferred.label);
      if (inferred.aliases != null) {
        for (String alias : inferred.aliases) {
          if (String.isNotBlank(alias) && !seen.contains(alias.toLowerCase())) {
            tokens.add(alias);
            seen.add(alias.toLowerCase());
          }
        }
      }
    }
  }

  private static String cleanBrickLabel(String name) {
    if (String.isBlank(name)) {
      return null;
    }
    String n = name.replaceAll('(?i)\\bBRICK\\s*\\d+\\b', ' ');
    n = n.replaceAll('\\b(I|II|III|IV|V)\\b', ' ');
    n = n.replaceAll('\\s+', ' ').trim();
    return String.isBlank(n) ? name.trim() : n;
  }

  private static String applyGeoQueryBias(String query, PlaceGeoBias bias) {
    String q = applyEgyptBias(query);
    if (bias == null) {
      return q;
    }
    String lower = q.toLowerCase();
    List<String> extras = new List<String>();
    for (String candidate : new List<String>{
      bias.areaName,
      cleanBrickLabel(bias.brickName),
      cleanBrickLabel(bias.zoneName)
    }) {
      if (String.isBlank(candidate)) {
        continue;
      }
      if (!lower.contains(candidate.toLowerCase())) {
        extras.add(candidate);
        lower += ' ' + candidate.toLowerCase();
      }
    }
    return extras.isEmpty() ? q : q + ' ' + String.join(extras, ' ');
  }

  private static List<PlaceCandidate> filterByGeoBias(List<PlaceCandidate> rows, PlaceGeoBias bias) {
    if (rows == null || rows.isEmpty() || bias == null) {
      return rows == null ? new List<PlaceCandidate>() : rows;
    }
    List<PlaceCandidate> kept = new List<PlaceCandidate>();
    Integer radius = bias.radiusMeters == null ? 55000 : bias.radiusMeters;
    Decimal maxMeters = Decimal.valueOf(radius) * 1.45;
    for (PlaceCandidate row : rows) {
      if (placeMatchesBias(row, bias, maxMeters)) {
        kept.add(row);
      }
    }
    return kept;
  }

  private static Boolean placeMatchesBias(PlaceCandidate row, PlaceGeoBias bias, Decimal maxMeters) {
    if (row == null) {
      return false;
    }
    String haystack = ((row.address == null ? '' : row.address) + ' ' + (row.name == null ? '' : row.name))
      .toLowerCase();
    if (bias.addressTokens != null) {
      for (String token : bias.addressTokens) {
        if (String.isNotBlank(token) && token.length() >= 3 && haystack.contains(token.toLowerCase())) {
          return true;
        }
      }
    }
    if (row.latitude != null && row.longitude != null && bias.latitude != null && bias.longitude != null) {
      return distanceMeters(bias.latitude, bias.longitude, row.latitude, row.longitude) <= maxMeters;
    }
    return false;
  }

  private static String googleLocationParam(PlaceGeoBias bias) {
    if (bias == null || bias.latitude == null || bias.longitude == null) {
      return '';
    }
    Integer radius = bias.radiusMeters == null ? 40000 : bias.radiusMeters;
    return '&location=' +
      String.valueOf(bias.latitude) +
      ',' +
      String.valueOf(bias.longitude) +
      '&radius=' +
      String.valueOf(radius);
  }

  private static String googleLocationBiasParam(PlaceGeoBias bias) {
    if (bias == null || bias.latitude == null || bias.longitude == null) {
      return '';
    }
    Integer radius = bias.radiusMeters == null ? 40000 : bias.radiusMeters;
    return '&locationbias=circle:' +
      String.valueOf(radius) +
      '@' +
      String.valueOf(bias.latitude) +
      ',' +
      String.valueOf(bias.longitude);
  }

  private static String nominatimViewboxParam(PlaceGeoBias bias) {
    if (bias == null || bias.west == null || bias.north == null || bias.east == null || bias.south == null) {
      return '';
    }
    String viewbox =
      '&viewbox=' +
      String.valueOf(bias.west) +
      ',' +
      String.valueOf(bias.north) +
      ',' +
      String.valueOf(bias.east) +
      ',' +
      String.valueOf(bias.south);
    if (bias.bounded == true) {
      viewbox += '&bounded=1';
    }
    return viewbox;
  }

  private static String overpassBbox(PlaceGeoBias bias) {
    if (bias != null && bias.south != null && bias.west != null && bias.north != null && bias.east != null) {
      return '(' +
        String.valueOf(bias.south) +
        ',' +
        String.valueOf(bias.west) +
        ',' +
        String.valueOf(bias.north) +
        ',' +
        String.valueOf(bias.east) +
        ')';
    }
    return '(22.0,24.7,31.7,36.9)';
  }

  private static void fillBiasBounds(PlaceGeoBias bias) {
    if (bias == null || bias.latitude == null || bias.longitude == null) {
      return;
    }
    Integer radius = bias.radiusMeters == null ? 40000 : bias.radiusMeters;
    Double lat = bias.latitude.doubleValue();
    Double lon = bias.longitude.doubleValue();
    Double dLat = radius / 111320.0;
    Double cosLat = Math.cos(lat * Math.PI / 180);
    Double dLon = cosLat == 0 ? dLat : radius / (111320.0 * Math.abs(cosLat));
    bias.south = Decimal.valueOf(lat - dLat).setScale(5);
    bias.north = Decimal.valueOf(lat + dLat).setScale(5);
    bias.west = Decimal.valueOf(lon - dLon).setScale(5);
    bias.east = Decimal.valueOf(lon + dLon).setScale(5);
  }

  private static Decimal distanceMeters(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
    Double r = 6371000;
    Double p1 = lat1.doubleValue() * Math.PI / 180;
    Double p2 = lat2.doubleValue() * Math.PI / 180;
    Double dLat = (lat2.doubleValue() - lat1.doubleValue()) * Math.PI / 180;
    Double dLon = (lon2.doubleValue() - lon1.doubleValue()) * Math.PI / 180;
    Double a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(p1) * Math.cos(p2) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Decimal.valueOf(r * c);
  }

  private class GeoCentroid {
    public String label;
    public Decimal latitude;
    public Decimal longitude;
    public Integer radiusMeters;
    public List<String> aliases;
  }

  private static GeoCentroid inferCentroid(String areaName, String brickName, String zoneName) {
    GeoCentroid fromArea = lookupCentroid(areaName);
    if (fromArea != null) {
      return fromArea;
    }
    GeoCentroid fromBrick = lookupCentroid(brickName);
    if (fromBrick != null) {
      return fromBrick;
    }
    return lookupCentroid(zoneName);
  }

  private static GeoCentroid lookupCentroid(String raw) {
    if (String.isBlank(raw)) {
      return null;
    }
    String haystack = cleanBrickLabel(raw).toLowerCase();
    for (GeoCentroid row : egyptCentroids()) {
      if (haystack.contains(row.label.toLowerCase())) {
        return row;
      }
      if (row.aliases == null) {
        continue;
      }
      for (String alias : row.aliases) {
        if (String.isNotBlank(alias) && haystack.contains(alias.toLowerCase())) {
          return row;
        }
      }
    }
    return null;
  }

  private static List<GeoCentroid> egyptCentroids() {
    return new List<GeoCentroid>{
      centroid('Cairo', 30.0444, 31.2357, 28000, new List<String>{
        'al qahira', 'helwan', 'maadi', 'heliopolis', 'nasr', 'abbase', 'abbaseya', 'abbasiya', 'shubra'
      }),
      centroid('Giza', 30.0131, 31.2089, 28000, new List<String>{
        'guiza', 'faisal', 'imbaba', 'october', '6th of october', 'dokki', 'mohandessin'
      }),
      centroid('Alexandria', 31.2001, 29.9187, 30000, new List<String>{
        'alex', 'smouha', 'montaza', 'agami'
      }),
      centroid('Qalyubia', 30.4660, 31.1850, 35000, new List<String>{
        'qalyub', 'kalubia', 'banha', 'shubra el kheima', 'obour'
      }),
      centroid('Sharqia', 30.5877, 31.5020, 50000, new List<String>{
        'sharkia', 'sharkeia', 'sharq', 'zagazig', '10th of ramadan', 'eastern'
      }),
      centroid('Dakahlia', 31.0364, 31.3807, 45000, new List<String>{
        'dakhleiah', 'dakahl', 'mansoura', 'mansura', 'mit ghamr'
      }),
      centroid('Beheira', 31.0341, 30.4681, 50000, new List<String>{
        'behair', 'damanhur', 'kafr el dawar'
      }),
      centroid('Monufia', 30.5972, 30.9876, 40000, new List<String>{
        'menofeya', 'menof', 'shibin', 'shebin'
      }),
      centroid('Gharbia', 30.7865, 31.0004, 40000, new List<String>{
        'gharb', 'gharbiyya', 'tanta', 'mahalla', 'el mahalla'
      }),
      centroid('Kafr El Sheikh', 31.1107, 30.9388, 45000, new List<String>{
        'kafr el-sheikh', 'kafrelsheikh'
      }),
      centroid('Damietta', 31.4165, 31.8133, 30000, new List<String>{ 'domiat', 'dumyat' }),
      centroid('Port Said', 31.2653, 32.3019, 20000, new List<String>{ 'portsaid' }),
      centroid('Ismailia', 30.5965, 32.2715, 35000, new List<String>{ 'ismail' }),
      centroid('Suez', 29.9668, 32.5498, 25000, null),
      centroid('North Sinai', 31.1120, 33.8010, 50000, new List<String>{ 'arish' }),
      centroid('South Sinai', 28.1090, 33.9750, 50000, new List<String>{ 'sharm' }),
      centroid('Fayoum', 29.3084, 30.8428, 35000, new List<String>{ 'fayum' }),
      centroid('Beni Suef', 29.0744, 31.0978, 35000, new List<String>{ 'bani suef' }),
      centroid('Minya', 28.1099, 30.7503, 45000, new List<String>{ 'menya', 'el menya' }),
      centroid('Assiut', 27.1801, 31.1837, 45000, new List<String>{ 'asyut', 'assuit' }),
      centroid('Sohag', 26.5590, 31.6956, 45000, null),
      centroid('Qena', 26.1551, 32.7160, 45000, new List<String>{ 'quena' }),
      centroid('Luxor', 25.6872, 32.6396, 30000, null),
      centroid('Aswan', 24.0889, 32.8998, 40000, null),
      centroid('Red Sea', 27.2579, 33.8116, 50000, new List<String>{ 'hurghada' }),
      centroid('New Valley', 25.4510, 30.5460, 50000, new List<String>{ 'n valley', 'kharga' }),
      centroid('Matrouh', 31.3543, 27.2373, 50000, new List<String>{ 'marsa matruh' })
    };
  }

  private static GeoCentroid centroid(
    String label,
    Decimal lat,
    Decimal lon,
    Integer radiusMeters,
    List<String> aliases
  ) {
    GeoCentroid row = new GeoCentroid();
    row.label = label;
    row.latitude = lat;
    row.longitude = lon;
    row.radiusMeters = radiusMeters;
    row.aliases = aliases;
    return row;
  }
}
