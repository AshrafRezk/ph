/**
 * Egypt doctor lookup against Vezeeta's public search and profile APIs.
 * Used by the New Account wizard when the record type is a doctor.
 * Suggest decides whether the term is a specialty list or a doctor name.
 * The profile call fills specialty, clinic, address, and map pin.
 */
public with sharing class VezeetaDoctorService {
  @TestVisible
  private static final String SUGGEST_ENDPOINT =
    'https://vezeeta-web-gateway.vezeetaservices.com/search-api/api/search/suggest';
  @TestVisible
  private static final String SEARCH_ENDPOINT = 'https://vezeeta-web-gateway.vezeetaservices.com/api/Search';
  @TestVisible
  private static final String PROFILE_ENDPOINT =
    'https://vezeeta-web-gateway.vezeetaservices.com/api/v2/doctorprofile';
  private static final Integer RESULT_LIMIT = 10;
  private static final String PROFILE_SITE = 'https://www.vezeeta.com/en/dr/';

  public class DoctorHit {
    @AuraEnabled
    public String urlName;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String specialty;
    @AuraEnabled
    public String address;
    @AuraEnabled
    public String area;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String fees;
    @AuraEnabled
    public Decimal rating;
    @AuraEnabled
    public String clinicName;
    @AuraEnabled
    public String profileUrl;
  }

  public class DoctorProfile {
    @AuraEnabled
    public String urlName;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String specialty1;
    @AuraEnabled
    public String specialty2;
    @AuraEnabled
    public String specialty3;
    @AuraEnabled
    public String specialtyLabel;
    @AuraEnabled
    public String street;
    @AuraEnabled
    public String city;
    @AuraEnabled
    public String area;
    @AuraEnabled
    public String governorate;
    @AuraEnabled
    public String landmark;
    @AuraEnabled
    public String clinicName;
    @AuraEnabled
    public Decimal latitude;
    @AuraEnabled
    public Decimal longitude;
    @AuraEnabled
    public String fees;
    @AuraEnabled
    public String shortDescription;
    @AuraEnabled
    public String profileUrl;
    @AuraEnabled
    public Id brickId;
    @AuraEnabled
    public Id brick148Id;
    @AuraEnabled
    public Id brick702Id;
    @AuraEnabled
    public String brickName;
  }

  private class Suggestion {
    public Integer typeCode;
    public String name;
    public String url;
  }

  @AuraEnabled
  public static List<DoctorHit> searchVezeetaDoctors(String searchTerm) {
    String term = searchTerm == null ? '' : searchTerm.trim();
    if (term.length() < 2) {
      return new List<DoctorHit>();
    }
    if (term.length() > 120) {
      term = term.left(120);
    }

    String profileSlug = slugFromProfileUrl(term);
    if (String.isNotBlank(profileSlug)) {
      DoctorHit pasted = new DoctorHit();
      pasted.urlName = profileSlug;
      pasted.name = humanizeSlug(profileSlug);
      pasted.profileUrl = profileUrlFor(profileSlug);
      return new List<DoctorHit>{ pasted };
    }

    String listingSpecialty = specialtySlugFromListingUrl(term);
    String language = languageFor(term);
    String specialtySlug = listingSpecialty;
    if (String.isBlank(specialtySlug)) {
      List<Suggestion> suggestions = suggest(term, language);
      if (!suggestions.isEmpty() && suggestions[0].typeCode == 0 && String.isNotBlank(suggestions[0].url)) {
        specialtySlug = suggestions[0].url;
      }
    }

    String searchJson = String.isNotBlank(specialtySlug)
      ? getJson(searchUrl(specialtySlug, null), language)
      : getJson(searchUrl(null, term), language);
    return parseSearchHits(searchJson);
  }

  @AuraEnabled
  public static void saveVezeetaProfileUrl(Id accountId, String profileUrl) {
    if (accountId == null || String.isBlank(profileUrl)) {
      return;
    }
    Account row = new Account(Id = accountId);
    row.Website = profileUrl.trim().left(255);
    Database.update(row, AccessLevel.SYSTEM_MODE);
  }

  @AuraEnabled
  public static DoctorProfile getVezeetaDoctor(String profileUrl) {
    String slug = slugFromProfileUrl(profileUrl);
    if (String.isBlank(slug)) {
      slug = profileUrl == null ? null : profileUrl.trim();
    }
    if (String.isBlank(slug)) {
      throw new AuraHandledException('Choose a doctor from Google Search first.');
    }
    String body = getJson(PROFILE_ENDPOINT + '?url=' + encodeQuery(slug), 'en-EG');
    DoctorProfile profile = parseProfile(body);
    if (profile == null || String.isBlank(profile.name)) {
      throw new AuraHandledException('Google Search did not return that doctor.');
    }
    attachBrick(profile);
    return profile;
  }

  @TestVisible
  private static String slugFromProfileUrl(String value) {
    if (String.isBlank(value) || !value.toLowerCase().contains('/dr/')) {
      return null;
    }
    String decoded = safeDecode(value.trim());
    Integer marker = decoded.toLowerCase().indexOf('/dr/');
    if (marker < 0) {
      return null;
    }
    String slug = decoded.substring(marker + 4);
    if (slug.contains('?')) {
      slug = slug.substringBefore('?');
    }
    if (slug.contains('#')) {
      slug = slug.substringBefore('#');
    }
    while (slug.endsWith('/')) {
      slug = slug.removeEnd('/');
    }
    return String.isBlank(slug) ? null : slug;
  }

  @TestVisible
  private static String specialtySlugFromListingUrl(String value) {
    if (String.isBlank(value) || !value.toLowerCase().contains('vezeeta.com')) {
      return null;
    }
    if (value.toLowerCase().contains('/dr/')) {
      return null;
    }
    String decoded = safeDecode(value.trim());
    String marker = null;
    if (decoded.contains('/doctor/')) {
      marker = '/doctor/';
    } else if (decoded.contains('/دكتور/')) {
      marker = '/دكتور/';
    }
    if (marker == null) {
      return null;
    }
    String rest = decoded.substring(decoded.indexOf(marker) + marker.length());
    if (rest.contains('?')) {
      rest = rest.substringBefore('?');
    }
    String specialty = rest.contains('/') ? rest.substringBefore('/') : rest;
    return String.isBlank(specialty) ? null : specialty;
  }

  private static List<Suggestion> suggest(String term, String language) {
    String endpoint =
      SUGGEST_ENDPOINT +
      '?query=' +
      encodeQuery(term) +
      '&categoryCount=4&area=&bookingType=physical&types=0,1,2,3,4';
    try {
      return parseSuggestions(getJson(endpoint, language));
    } catch (Exception ex) {
      return new List<Suggestion>();
    }
  }

  private static String searchUrl(String specialtySlug, String doctorName) {
    String query = 'viewModel.BookingTypes=physical&viewModel.page=1';
    if (String.isNotBlank(specialtySlug)) {
      query += '&viewModel.speciality=' + encodeQuery(specialtySlug);
    }
    if (String.isNotBlank(doctorName)) {
      query += '&viewModel.doctorName=' + encodeQuery(doctorName);
    }
    return SEARCH_ENDPOINT + '?' + query;
  }

  private static List<Suggestion> parseSuggestions(String body) {
    List<Suggestion> suggestions = new List<Suggestion>();
    Map<String, Object> root = asMap(parseJson(body));
    if (root == null) {
      return suggestions;
    }
    for (Object rowValue : asList(root.get('Result'))) {
      Map<String, Object> row = asMap(rowValue);
      if (row == null) {
        continue;
      }
      Suggestion suggestion = new Suggestion();
      suggestion.typeCode = toInteger(row.get('Type'));
      suggestion.name = asString(row.get('Name'));
      suggestion.url = asString(row.get('Url'));
      suggestions.add(suggestion);
    }
    return suggestions;
  }

  @TestVisible
  private static List<DoctorHit> parseSearchHits(String body) {
    List<DoctorHit> hits = new List<DoctorHit>();
    Map<String, Object> root = asMap(parseJson(body));
    if (root == null) {
      return hits;
    }
    Set<String> seen = new Set<String>();
    for (Object rowValue : asList(root.get('Result'))) {
      if (hits.size() >= RESULT_LIMIT) {
        break;
      }
      Map<String, Object> row = asMap(rowValue);
      if (row == null) {
        continue;
      }
      String urlName = asString(row.get('UrlName'));
      String name = stripTitle(asString(row.get('DoctorName')));
      if (String.isBlank(urlName) || String.isBlank(name) || seen.contains(urlName)) {
        continue;
      }
      seen.add(urlName);
      Map<String, Object> area = asMap(row.get('BasicContactArea'));
      Map<String, Object> city = asMap(row.get('BasicContactCity'));
      DoctorHit hit = new DoctorHit();
      hit.urlName = urlName;
      hit.name = name;
      hit.specialty = asString(row.get('MainSpecialtyName'));
      hit.address = asString(row.get('BasicContactAddress'));
      hit.area = firstText(area, new List<String>{ 'textEnglish', 'text' });
      hit.city = firstText(city, new List<String>{ 'textEnglish', 'text' });
      hit.fees = feeText(row.get('Fees'));
      hit.rating = toDecimal(row.get('OverallPercentage'));
      hit.clinicName = asString(row.get('TopLevelEntityName'));
      hit.profileUrl = profileUrlFor(urlName);
      hits.add(hit);
    }
    return hits;
  }

  @TestVisible
  private static DoctorProfile parseProfile(String body) {
    Map<String, Object> root = asMap(parseJson(body));
    Map<String, Object> profileNode = root == null ? null : asMap(root.get('Profile'));
    if (profileNode == null) {
      return null;
    }
    DoctorProfile profile = new DoctorProfile();
    profile.urlName = asString(profileNode.get('UrlName'));
    profile.name = stripTitle(
      firstNonBlank(asString(profileNode.get('DoctorNameEnglish')), asString(profileNode.get('DoctorName')))
    );
    profile.shortDescription = asString(profileNode.get('ShortDescription'));
    profile.profileUrl = profileUrlFor(profile.urlName);

    List<String> specialties = new List<String>();
    addSpecialty(specialties, specialtyName(asMap(profileNode.get('MainSpeciality'))));
    for (Object secondaryValue : asList(profileNode.get('SecondarySpecialties'))) {
      addSpecialty(specialties, specialtyName(asMap(secondaryValue)));
    }
    if (!specialties.isEmpty()) {
      profile.specialty1 = specialties[0];
    }
    if (specialties.size() > 1) {
      profile.specialty2 = specialties[1];
    }
    if (specialties.size() > 2) {
      profile.specialty3 = specialties[2];
    }
    profile.specialtyLabel = MedicalSpecialtyPicklist.getLabel(profile.specialty1);

    Map<String, Object> contact = basicContact(asList(profileNode.get('Contacts')));
    if (contact != null) {
      Map<String, Object> area = asMap(contact.get('Area'));
      Map<String, Object> city = asMap(contact.get('City'));
      Map<String, Object> entity = asMap(contact.get('Entity'));
      profile.street = asString(contact.get('Address'));
      profile.area = firstText(area, new List<String>{ 'NameEnglish', 'Name' });
      String cityName = firstText(city, new List<String>{ 'NameEnglish', 'Name' });
      profile.governorate = resolveGovernorate(cityName);
      profile.city = String.isNotBlank(profile.area) ? profile.area : cityName;
      profile.latitude = toDecimal(contact.get('Latitude'));
      profile.longitude = toDecimal(contact.get('Longitude'));
      profile.fees = feeText(contact.get('Fees'));
      profile.clinicName = firstText(entity, new List<String>{ 'NameEnglish', 'Name' });
      profile.landmark = profile.clinicName;
    }
    return profile;
  }

  private static void attachBrick(DoctorProfile profile) {
    if (profile == null) {
      return;
    }
    try {
      List<Brick__c> bricks = new List<Brick__c>();
      if (String.isNotBlank(profile.governorate)) {
        String governorate = profile.governorate;
        bricks = [
          SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, City__c, Governorate__c
          FROM Brick__c
          WHERE Is_Active__c = TRUE AND Governorate__c = :governorate
          WITH SYSTEM_MODE
          ORDER BY Brick_Level__c DESC
          LIMIT 40
        ];
      }
      Brick__c match = pickBrick(bricks, profile.area, profile.city);
      if (match == null && String.isNotBlank(profile.area)) {
        String likeArea = '%' + profile.area.left(40).replace('%', '').replace('_', '') + '%';
        bricks = [
          SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, City__c, Governorate__c
          FROM Brick__c
          WHERE Is_Active__c = TRUE AND (Name LIKE :likeArea OR City__c LIKE :likeArea)
          WITH SYSTEM_MODE
          LIMIT 20
        ];
        match = pickBrick(bricks, profile.area, profile.city);
      }
      if (match == null) {
        return;
      }
      profile.brickName = String.isNotBlank(match.Brick_Code__c)
        ? match.Brick_Code__c + ' — ' + match.Name
        : match.Name;
      if (match.Brick_Level__c == '702') {
        profile.brickId = match.Id;
        profile.brick702Id = match.Id;
        profile.brick148Id = match.Parent_Brick__c;
      } else if (match.Brick_Level__c == '148') {
        profile.brick148Id = match.Id;
      } else {
        profile.brickId = match.Id;
      }
    } catch (Exception ex) {
      // Brick alignment is optional. The rep can still pick 148/702 on the form.
    }
  }

  private static Brick__c pickBrick(List<Brick__c> bricks, String area, String city) {
    if (bricks == null || bricks.isEmpty()) {
      return null;
    }
    Brick__c fallback = null;
    for (Brick__c brick : bricks) {
      if (fallback == null && brick.Brick_Level__c == '702') {
        fallback = brick;
      }
      String haystack = ((brick.Name == null ? '' : brick.Name) + ' ' + (brick.City__c == null ? '' : brick.City__c))
        .toLowerCase();
      if (containsEither(haystack, area) || containsEither(haystack, city)) {
        return brick;
      }
    }
    return fallback == null ? bricks[0] : fallback;
  }

  private static Boolean containsEither(String haystack, String needle) {
    if (String.isBlank(haystack) || String.isBlank(needle)) {
      return false;
    }
    String normalizedNeedle = needle.toLowerCase();
    if (haystack.contains(normalizedNeedle) || normalizedNeedle.contains(haystack)) {
      return true;
    }
    String firstWord = normalizedNeedle.substringBefore(' ');
    return firstWord.length() >= 4 && haystack.contains(firstWord);
  }

  private static void addSpecialty(List<String> specialties, String vezeetaName) {
    String apiValue = resolveSpecialty(vezeetaName);
    if (String.isBlank(apiValue) || specialties.contains(apiValue)) {
      return;
    }
    specialties.add(apiValue);
  }

  @TestVisible
  private static String resolveSpecialty(String vezeetaName) {
    if (String.isBlank(vezeetaName)) {
      return null;
    }
    Map<String, String> apiByLabel = specialtyApiByNormalizedLabel();
    String normalized = normalizeToken(vezeetaName);
    if (apiByLabel.containsKey(normalized)) {
      return apiByLabel.get(normalized);
    }
    String alias = SPECIALTY_ALIASES.get(normalized);
    if (String.isNotBlank(alias)) {
      String aliasKey = normalizeToken(alias.replace('_', ' '));
      if (apiByLabel.containsKey(aliasKey)) {
        return apiByLabel.get(aliasKey);
      }
    }
    String bestLabel = null;
    String bestApi = null;
    for (String label : apiByLabel.keySet()) {
      if (label.length() < 6) {
        continue;
      }
      if (normalized.contains(label) && (bestLabel == null || label.length() > bestLabel.length())) {
        bestLabel = label;
        bestApi = apiByLabel.get(label);
      }
    }
    return bestApi;
  }

  private static Map<String, String> specialtyApiByLabelCache;

  private static Map<String, String> specialtyApiByNormalizedLabel() {
    if (specialtyApiByLabelCache != null) {
      return specialtyApiByLabelCache;
    }
    specialtyApiByLabelCache = new Map<String, String>();
    Map<String, Schema.SObjectField> fields = Account.SObjectType.getDescribe().fields.getMap();
    Schema.SObjectField specialtyField = fields.containsKey('Specialty_1__c')
      ? fields.get('Specialty_1__c')
      : fields.get('specialty_1__c');
    if (specialtyField == null) {
      return specialtyApiByLabelCache;
    }
    for (Schema.PicklistEntry entry : specialtyField.getDescribe().getPicklistValues()) {
      if (!entry.isActive()) {
        continue;
      }
      specialtyApiByLabelCache.put(normalizeToken(entry.getLabel()), entry.getValue());
      specialtyApiByLabelCache.put(normalizeToken(entry.getValue().replace('_', ' ')), entry.getValue());
    }
    return specialtyApiByLabelCache;
  }

  private static final Map<String, String> SPECIALTY_ALIASES = new Map<String, String>{
    'skin' => 'Dermatology',
    'venereology' => 'Dermatology',
    'dermatology and venereology' => 'Dermatology',
    'cosmetic surgery' => 'Plastic_Surgery',
    'dietitian and nutrition' => 'Nutrition_Medicine',
    'nutrition' => 'Nutrition_Medicine',
    'psychiatry' => 'Psychiatry',
    'ear nose and throat' => 'Otorhinolaryngology',
    'ent' => 'Otorhinolaryngology'
  };

  @TestVisible
  private static String resolveGovernorate(String cityName) {
    if (String.isBlank(cityName)) {
      return null;
    }
    String key = cityName.trim().toLowerCase();
    if (GOVERNORATE_ALIASES.containsKey(key)) {
      return GOVERNORATE_ALIASES.get(key);
    }
    for (String governorate : AccountCreateQualityService.EGYPT_GOVERNORATES) {
      if (governorate.toLowerCase() == key) {
        return governorate;
      }
    }
    return null;
  }

  private static final Map<String, String> GOVERNORATE_ALIASES = new Map<String, String>{
    'cairo' => 'Cairo',
    'القاهرة' => 'Cairo',
    'giza' => 'Giza',
    'الجيزة' => 'Giza',
    'الجيزه' => 'Giza',
    'alexandria' => 'Alexandria',
    'الاسكندرية' => 'Alexandria',
    'الإسكندرية' => 'Alexandria',
    'qalyubia' => 'Qalyubia',
    'qalyubiya' => 'Qalyubia',
    'القليوبية' => 'Qalyubia',
    'sharqia' => 'Sharqia',
    'الشرقية' => 'Sharqia',
    'dakahlia' => 'Dakahlia',
    'الدقهلية' => 'Dakahlia',
    'beheira' => 'Beheira',
    'البحيرة' => 'Beheira',
    'monufia' => 'Monufia',
    'المنوفية' => 'Monufia',
    'gharbia' => 'Gharbia',
    'الغربية' => 'Gharbia',
    'kafr el sheikh' => 'Kafr El Sheikh',
    'كفر الشيخ' => 'Kafr El Sheikh',
    'damietta' => 'Damietta',
    'دمياط' => 'Damietta',
    'port said' => 'Port Said',
    'بورسعيد' => 'Port Said',
    'ismailia' => 'Ismailia',
    'الإسماعيلية' => 'Ismailia',
    'suez' => 'Suez',
    'السويس' => 'Suez',
    'fayoum' => 'Fayoum',
    'faiyum' => 'Fayoum',
    'الفيوم' => 'Fayoum',
    'beni suef' => 'Beni Suef',
    'بني سويف' => 'Beni Suef',
    'minya' => 'Minya',
    'المنيا' => 'Minya',
    'assiut' => 'Assiut',
    'asyut' => 'Assiut',
    'أسيوط' => 'Assiut',
    'sohag' => 'Sohag',
    'سوهاج' => 'Sohag',
    'qena' => 'Qena',
    'قنا' => 'Qena',
    'luxor' => 'Luxor',
    'الأقصر' => 'Luxor',
    'aswan' => 'Aswan',
    'أسوان' => 'Aswan',
    'red sea' => 'Red Sea',
    'البحر الأحمر' => 'Red Sea',
    'new valley' => 'New Valley',
    'الوادي الجديد' => 'New Valley',
    'matrouh' => 'Matrouh',
    'مطروح' => 'Matrouh',
    'north sinai' => 'North Sinai',
    'شمال سيناء' => 'North Sinai',
    'south sinai' => 'South Sinai',
    'جنوب سيناء' => 'South Sinai'
  };

  private static Map<String, Object> basicContact(List<Object> contacts) {
    Map<String, Object> first = null;
    for (Object contactValue : contacts) {
      Map<String, Object> contact = asMap(contactValue);
      if (contact == null) {
        continue;
      }
      if (first == null) {
        first = contact;
      }
      if (contact.get('IsBasic') == true) {
        return contact;
      }
    }
    return first;
  }

  private static String specialtyName(Map<String, Object> specialty) {
    if (specialty == null) {
      return null;
    }
    return firstNonBlank(asString(specialty.get('NameEnglish')), asString(specialty.get('Name')));
  }

  private static String profileUrlFor(String slug) {
    if (String.isBlank(slug)) {
      return null;
    }
    String url = PROFILE_SITE + encodeQuery(slug);
    return url.length() <= 255 ? url : null;
  }

  private static String humanizeSlug(String slug) {
    String text = slug.replace('-', ' ').replace('_', ' ');
    return stripTitle(text);
  }

  @TestVisible
  private static String stripTitle(String name) {
    if (String.isBlank(name)) {
      return name;
    }
    String cleaned = name.trim();
    List<String> titles = new List<String>{
      'أستاذ دكتور',
      'استاذ دكتور',
      'دكتورة',
      'دكتور',
      'أستاذ',
      'استاذ',
      'بروفيسور',
      'doctor',
      'dr.',
      'dr',
      'prof.',
      'prof'
    };
    Boolean stripped = true;
    while (stripped && String.isNotBlank(cleaned)) {
      stripped = false;
      String lower = cleaned.toLowerCase();
      for (String title : titles) {
        if (lower.startsWith(title + ' ')) {
          cleaned = cleaned.substring(title.length()).trim();
          stripped = true;
          break;
        }
      }
    }
    return cleaned;
  }

  private static String languageFor(String term) {
    return term != null && Pattern.compile('[\\u0600-\\u06FF]').matcher(term).find() ? 'ar-EG' : 'en-EG';
  }

  private static String getJson(String endpoint, String language) {
    HttpRequest req = new HttpRequest();
    req.setMethod('GET');
    req.setEndpoint(endpoint);
    req.setTimeout(20000);
    req.setHeader('Accept', 'application/json');
    req.setHeader('Accept-Language', String.isBlank(language) ? 'en-EG' : language);
    req.setHeader('CountryId', '1');
    req.setHeader('RegionId', 'Africa/Cairo');
    req.setHeader('User-Agent', 'ZetaPharma-AccountsTab/1.0');
    HttpResponse res;
    try {
      res = new Http().send(req);
    } catch (Exception ex) {
      throw new AuraHandledException('Google Search is unavailable right now.');
    }
    Integer code = res.getStatusCode();
    if (code < 200 || code >= 300 || String.isBlank(res.getBody())) {
      throw new AuraHandledException('Google Search returned an unexpected response.');
    }
    return res.getBody();
  }

  private static Object parseJson(String body) {
    if (String.isBlank(body)) {
      return null;
    }
    try {
      return JSON.deserializeUntyped(body);
    } catch (Exception ex) {
      return null;
    }
  }

  private static String encodeQuery(String value) {
    return EncodingUtil.urlEncode(value, 'UTF-8').replace('+', '%20');
  }

  private static String safeDecode(String value) {
    try {
      return EncodingUtil.urlDecode(value, 'UTF-8');
    } catch (Exception ex) {
      return value;
    }
  }

  private static String normalizeToken(String value) {
    return value == null ? '' : value.toLowerCase().replace('_', ' ').replace('-', ' ').trim();
  }

  private static Map<String, Object> asMap(Object value) {
    return value instanceof Map<String, Object> ? (Map<String, Object>) value : null;
  }

  private static List<Object> asList(Object value) {
    return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
  }

  private static String asString(Object value) {
    return value == null ? null : String.valueOf(value);
  }

  private static String firstText(Map<String, Object> row, List<String> keys) {
    if (row == null) {
      return null;
    }
    for (String key : keys) {
      String text = asString(row.get(key));
      if (String.isNotBlank(text)) {
        return text;
      }
    }
    return null;
  }

  private static String firstNonBlank(String first, String second) {
    return String.isNotBlank(first) ? first : second;
  }

  private static String feeText(Object value) {
    Decimal amount = toDecimal(value);
    if (amount == null) {
      return null;
    }
    Decimal normalized = amount.stripTrailingZeros();
    return normalized.scale() <= 0 ? String.valueOf(normalized.intValue()) : String.valueOf(normalized);
  }

  private static Integer toInteger(Object value) {
    Decimal amount = toDecimal(value);
    return amount == null ? null : amount.intValue();
  }

  private static Decimal toDecimal(Object value) {
    if (value == null) {
      return null;
    }
    try {
      if (value instanceof Decimal) {
        return (Decimal) value;
      }
      if (value instanceof Integer || value instanceof Long) {
        return Decimal.valueOf(String.valueOf(value));
      }
      String text = String.valueOf(value).trim();
      return String.isBlank(text) ? null : Decimal.valueOf(text);
    } catch (Exception ex) {
      return null;
    }
  }
}
