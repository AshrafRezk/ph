/**
 * Read-only Places and Vezeeta proposals for existing accounts.
 * Does not write Account fields. SFE greenlights via AccountQualityReviewService.
 */
public with sharing class AccountNurtureProposeService {
  private static final Integer NAME_ACCEPT = 90;
  private static final Integer NAME_NEAR = 72;
  private static final Decimal NEAR_KM = 0.8;

  public class FieldDiff {
    public String field;
    public String label;
    public String currentValue;
    public String proposedValue;
    public String kind;
    public Boolean accepted;
  }

  public class DoctorCandidate {
    public String urlName;
    public String name;
    public String specialty;
    public String address;
    public String profileUrl;
    public Integer nameScore;
  }

  public class ProposalDraft {
    public Id accountId;
    public String provider;
    public Integer score;
    public String possibilityLabel;
    public String summary;
    public String externalName;
    public String externalDetail;
    public String status;
    public List<FieldDiff> fields;
    public List<DoctorCandidate> doctorCandidates;
  }

  @TestVisible
  private static List<AccountMapsPlacesService.PlaceCandidate> testPlaceHits;
  @TestVisible
  private static List<VezeetaDoctorService.DoctorHit> testVezeetaHits;
  @TestVisible
  private static Map<String, VezeetaDoctorService.DoctorProfile> testVezeetaProfiles;

  public static ProposalDraft proposePlaces(Account acct) {
    ProposalDraft draft = emptyDraft(acct == null ? null : acct.Id, 'Places');
    if (acct == null || String.isBlank(acct.Name)) {
      return null;
    }

    String query = buildSearchQuery(acct);
    if (String.isBlank(query)) {
      return null;
    }

    List<AccountMapsPlacesService.PlaceCandidate> hits = searchPlacesForAccount(acct, query);
    AccountMapsPlacesService.PlaceCandidate best = pickPlace(acct, hits);
    if (best == null) {
      return null;
    }

    Integer nameScore = AccountCognitiveSearch.scoreAlignedNames(acct.Name, best.name);
    draft.score = nameScore;
    draft.possibilityLabel = nameScore >= 90 ? 'Very likely' : 'Likely';
    draft.externalName = best.name;
    draft.externalDetail = detailLine(
      new List<String>{ best.address, best.phone, best.provider }
    );
    draft.fields = buildPlaceDiffs(acct, best);
    if (draft.fields.isEmpty()) {
      return null;
    }
    draft.summary =
      draft.fields.size() +
      ' Places change(s) for ' +
      (String.isBlank(best.name) ? 'matched place' : best.name) +
      '.';
    draft.status = 'Pending';
    return draft;
  }

  public static ProposalDraft proposeVezeeta(Account acct) {
    ProposalDraft draft = emptyDraft(acct == null ? null : acct.Id, 'Vezeeta');
    if (acct == null || String.isBlank(acct.Name) || acct.IsPersonAccount != true) {
      return null;
    }

    String term = acct.Name.trim();
    if (term.length() < 2) {
      return null;
    }

    List<VezeetaDoctorService.DoctorHit> hits = searchVezeeta(term);
    List<ScoredDoctor> strong = new List<ScoredDoctor>();
    for (VezeetaDoctorService.DoctorHit hit : hits) {
      if (hit == null || String.isBlank(hit.name)) {
        continue;
      }
      Integer nameScore = AccountCognitiveSearch.scoreAlignedNames(acct.Name, hit.name);
      if (nameScore < NAME_ACCEPT) {
        continue;
      }
      ScoredDoctor row = new ScoredDoctor();
      row.hit = hit;
      row.nameScore = nameScore;
      row.geoOk = geoAgrees(acct, hit.city, hit.area, null);
      strong.add(row);
    }
    if (strong.isEmpty()) {
      return null;
    }

    List<ScoredDoctor> preferred = new List<ScoredDoctor>();
    for (ScoredDoctor row : strong) {
      if (row.geoOk) {
        preferred.add(row);
      }
    }
    List<ScoredDoctor> pool = preferred.isEmpty() ? strong : preferred;

    if (pool.size() > 1 && preferred.size() != 1) {
      draft.status = 'Needs Pick';
      draft.score = pool[0].nameScore;
      draft.possibilityLabel = 'Likely';
      draft.externalName = pool[0].hit.name;
      draft.doctorCandidates = new List<DoctorCandidate>();
      for (ScoredDoctor row : pool) {
        DoctorCandidate c = new DoctorCandidate();
        c.urlName = row.hit.urlName;
        c.name = row.hit.name;
        c.specialty = row.hit.specialty;
        c.address = detailLine(new List<String>{ row.hit.address, row.hit.area, row.hit.city });
        c.profileUrl = row.hit.profileUrl;
        c.nameScore = row.nameScore;
        draft.doctorCandidates.add(c);
      }
      draft.fields = new List<FieldDiff>();
      draft.summary =
        pool.size() +
        ' strong Vezeeta doctors. Pick one before greenlighting.';
      draft.externalDetail = draft.summary;
      return draft;
    }

    ScoredDoctor chosen = pool[0];
    VezeetaDoctorService.DoctorProfile profile = loadVezeetaProfile(chosen.hit);
    if (profile == null || String.isBlank(profile.name)) {
      return null;
    }
    Integer nameScore = AccountCognitiveSearch.scoreAlignedNames(acct.Name, profile.name);
    if (nameScore < NAME_ACCEPT) {
      return null;
    }
    draft.score = nameScore;
    draft.possibilityLabel = 'Very likely';
    draft.externalName = profile.name;
    draft.externalDetail = detailLine(
      new List<String>{
        profile.specialtyLabel,
        profile.street,
        profile.city,
        profile.governorate,
        profile.profileUrl
      }
    );
    draft.fields = buildVezeetaDiffs(acct, profile);
    if (draft.fields.isEmpty()) {
      return null;
    }
    draft.summary =
      draft.fields.size() +
      ' Vezeeta change(s) for ' +
      profile.name +
      '.';
    draft.status = 'Pending';
    return draft;
  }

  public static ProposalDraft buildVezeetaFromPick(Account acct, String urlName) {
    if (acct == null || String.isBlank(urlName)) {
      return null;
    }
    VezeetaDoctorService.DoctorHit hit = new VezeetaDoctorService.DoctorHit();
    hit.urlName = urlName;
    hit.profileUrl = 'https://www.vezeeta.com/en/dr/' + urlName;
    VezeetaDoctorService.DoctorProfile profile = loadVezeetaProfile(hit);
    if (profile == null) {
      return null;
    }
    ProposalDraft draft = emptyDraft(acct.Id, 'Vezeeta');
    draft.score = AccountCognitiveSearch.scoreAlignedNames(acct.Name, profile.name);
    draft.possibilityLabel = draft.score >= 90 ? 'Very likely' : 'Likely';
    draft.externalName = profile.name;
    draft.externalDetail = detailLine(
      new List<String>{ profile.specialtyLabel, profile.street, profile.city, profile.governorate }
    );
    draft.fields = buildVezeetaDiffs(acct, profile);
    draft.status = 'Pending';
    draft.summary =
      (draft.fields == null ? 0 : draft.fields.size()) +
      ' Vezeeta change(s) for ' +
      profile.name +
      '.';
    return draft;
  }

  public static String payloadJson(ProposalDraft draft) {
    Map<String, Object> root = new Map<String, Object>();
    List<Map<String, Object>> fields = new List<Map<String, Object>>();
    if (draft != null && draft.fields != null) {
      for (FieldDiff diff : draft.fields) {
        fields.add(
          new Map<String, Object>{
            'field' => diff.field,
            'label' => diff.label,
            'current' => diff.currentValue,
            'proposed' => diff.proposedValue,
            'kind' => diff.kind,
            'accepted' => diff.accepted != false
          }
        );
      }
    }
    root.put('fields', fields);
    if (draft != null && draft.doctorCandidates != null && !draft.doctorCandidates.isEmpty()) {
      List<Map<String, Object>> doctors = new List<Map<String, Object>>();
      for (DoctorCandidate c : draft.doctorCandidates) {
        doctors.add(
          new Map<String, Object>{
            'urlName' => c.urlName,
            'name' => c.name,
            'specialty' => c.specialty,
            'address' => c.address,
            'profileUrl' => c.profileUrl,
            'nameScore' => c.nameScore
          }
        );
      }
      root.put('doctors', doctors);
    }
    return JSON.serialize(root);
  }

  private class ScoredDoctor {
    VezeetaDoctorService.DoctorHit hit;
    Integer nameScore;
    Boolean geoOk;
  }

  private static ProposalDraft emptyDraft(Id accountId, String provider) {
    ProposalDraft draft = new ProposalDraft();
    draft.accountId = accountId;
    draft.provider = provider;
    draft.fields = new List<FieldDiff>();
    draft.doctorCandidates = new List<DoctorCandidate>();
    draft.status = 'Pending';
    return draft;
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
    parts.add('Egypt');
    return parts.isEmpty() ? null : String.join(parts, ', ');
  }

  private static List<AccountMapsPlacesService.PlaceCandidate> searchPlacesForAccount(
    Account acct,
    String query
  ) {
    if (testPlaceHits != null) {
      return testPlaceHits;
    }
    AccountMapsPlacesService.PlaceGeoBias bias = new AccountMapsPlacesService.PlaceGeoBias();
    if (acct.BillingLatitude != null && acct.BillingLongitude != null) {
      bias.latitude = acct.BillingLatitude;
      bias.longitude = acct.BillingLongitude;
      bias.radiusMeters = 3000;
    }
    String typeHint = acct.IsPersonAccount == true ? 'doctor' : 'pharmacy';
    if (acct.RecordType != null && String.isNotBlank(acct.RecordType.DeveloperName)) {
      typeHint = acct.RecordType.DeveloperName;
    }
    return AccountMapsPlacesService.searchPlaces(query, typeHint, bias);
  }

  private static AccountMapsPlacesService.PlaceCandidate pickPlace(
    Account acct,
    List<AccountMapsPlacesService.PlaceCandidate> hits
  ) {
    if (hits == null || hits.isEmpty()) {
      return null;
    }
    AccountMapsPlacesService.PlaceCandidate best = null;
    Integer bestScore = -1;
    for (AccountMapsPlacesService.PlaceCandidate hit : hits) {
      if (hit == null || String.isBlank(hit.name)) {
        continue;
      }
      Integer nameScore = AccountCognitiveSearch.scoreAlignedNames(acct.Name, hit.name);
      Boolean nearPin =
        acct.BillingLatitude != null &&
        acct.BillingLongitude != null &&
        hit.latitude != null &&
        hit.longitude != null &&
        distanceKm(
          acct.BillingLatitude,
          acct.BillingLongitude,
          hit.latitude,
          hit.longitude
        ) <= NEAR_KM;
      Boolean accept = nameScore >= NAME_ACCEPT || (nameScore >= NAME_NEAR && nearPin);
      if (!accept) {
        continue;
      }
      Integer rank = nameScore + (nearPin ? 5 : 0);
      if (rank > bestScore) {
        bestScore = rank;
        best = hit;
      }
    }
    return best;
  }

  private static List<VezeetaDoctorService.DoctorHit> searchVezeeta(String term) {
    if (testVezeetaHits != null) {
      return testVezeetaHits;
    }
    return VezeetaDoctorService.searchVezeetaDoctors(term);
  }

  private static VezeetaDoctorService.DoctorProfile loadVezeetaProfile(
    VezeetaDoctorService.DoctorHit hit
  ) {
    if (hit == null) {
      return null;
    }
    String key = String.isNotBlank(hit.urlName) ? hit.urlName : hit.profileUrl;
    if (testVezeetaProfiles != null && testVezeetaProfiles.containsKey(key)) {
      return testVezeetaProfiles.get(key);
    }
    if (testVezeetaProfiles != null && String.isNotBlank(hit.profileUrl) && testVezeetaProfiles.containsKey(hit.profileUrl)) {
      return testVezeetaProfiles.get(hit.profileUrl);
    }
    String profileUrl = String.isNotBlank(hit.profileUrl) ? hit.profileUrl : hit.urlName;
    return VezeetaDoctorService.getVezeetaDoctor(profileUrl);
  }

  private static List<FieldDiff> buildPlaceDiffs(
    Account acct,
    AccountMapsPlacesService.PlaceCandidate place
  ) {
    List<FieldDiff> diffs = new List<FieldDiff>();
    addPhoneDiff(diffs, acct, place.phone);
    addFillOrCorrect(
      diffs,
      'Maps_Place_Id__c',
      'Google place id',
      stringVal(acct, 'Maps_Place_Id__c'),
      place.placeId,
      false
    );

    String street = place.address;
    String city = null;
    String governorate = null;
    if (String.isNotBlank(place.address)) {
      List<String> parts = place.address.split(',');
      if (parts.size() >= 2) {
        city = parts[parts.size() - 2].trim();
      }
      governorate = findGovernorate(place.address);
    }
    Boolean addressChanged = false;
    addressChanged =
      addFillOrCorrect(diffs, 'BillingStreet', 'Street', acct.BillingStreet, street, true) ||
      addressChanged;
    addressChanged =
      addFillOrCorrect(diffs, 'BillingCity', 'City', acct.BillingCity, city, true) ||
      addressChanged;
    addressChanged =
      addFillOrCorrect(
        diffs,
        'Governorate__c',
        'Governorate',
        stringVal(acct, 'Governorate__c'),
        governorate,
        true
      ) || addressChanged;

    if (place.latitude != null && place.longitude != null) {
      String currentLat = acct.BillingLatitude == null ? null : String.valueOf(acct.BillingLatitude);
      String currentLng = acct.BillingLongitude == null ? null : String.valueOf(acct.BillingLongitude);
      String proposedLat = String.valueOf(place.latitude);
      String proposedLng = String.valueOf(place.longitude);
      Boolean pinBlank = String.isBlank(currentLat) || String.isBlank(currentLng);
      Boolean pinDiffers =
        !pinBlank &&
        (
          (Decimal.valueOf(currentLat) - place.latitude).abs() > 0.0005 ||
          (Decimal.valueOf(currentLng) - place.longitude).abs() > 0.0005
        );
      if (pinBlank || addressChanged || pinDiffers) {
        addDiff(
          diffs,
          'BillingLatitude',
          'Latitude',
          currentLat,
          proposedLat,
          pinBlank ? 'fill' : 'correction'
        );
        addDiff(
          diffs,
          'BillingLongitude',
          'Longitude',
          currentLng,
          proposedLng,
          pinBlank ? 'fill' : 'correction'
        );
      }
    }

    BrickMatch bricks = matchBricks(governorate, city);
    if (bricks != null) {
      if (bricks.brick702Id != null) {
        addFillOrCorrect(
          diffs,
          'Brick_702__c',
          'Brick 702',
          stringVal(acct, 'Brick_702__c'),
          String.valueOf(bricks.brick702Id),
          false
        );
      }
      if (bricks.brick148Id != null) {
        addFillOrCorrect(
          diffs,
          'Brick_148__c',
          'Brick 148',
          stringVal(acct, 'Brick_148__c'),
          String.valueOf(bricks.brick148Id),
          false
        );
      }
      if (bricks.brickId != null) {
        addFillOrCorrect(
          diffs,
          'Brick__c',
          'Brick',
          stringVal(acct, 'Brick__c'),
          String.valueOf(bricks.brickId),
          false
        );
      }
    }
    return diffs;
  }

  private class BrickMatch {
    Id brickId;
    Id brick148Id;
    Id brick702Id;
  }

  private static BrickMatch matchBricks(String governorate, String city) {
    try {
      List<Brick__c> bricks = new List<Brick__c>();
      if (String.isNotBlank(governorate)) {
        bricks = [
          SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, City__c, Governorate__c
          FROM Brick__c
          WHERE Is_Active__c = TRUE AND Governorate__c = :governorate
          WITH SYSTEM_MODE
          ORDER BY Brick_Level__c DESC
          LIMIT 40
        ];
      }
      Brick__c match = pickBrick(bricks, city);
      if (match == null && String.isNotBlank(city)) {
        String likeCity = '%' + city.left(40).replace('%', '').replace('_', '') + '%';
        bricks = [
          SELECT Id, Name, Brick_Code__c, Brick_Level__c, Parent_Brick__c, City__c, Governorate__c
          FROM Brick__c
          WHERE Is_Active__c = TRUE AND (Name LIKE :likeCity OR City__c LIKE :likeCity)
          WITH SYSTEM_MODE
          LIMIT 20
        ];
        match = pickBrick(bricks, city);
      }
      if (match == null) {
        return null;
      }
      BrickMatch result = new BrickMatch();
      if (match.Brick_Level__c == '702') {
        result.brickId = match.Id;
        result.brick702Id = match.Id;
        result.brick148Id = match.Parent_Brick__c;
      } else if (match.Brick_Level__c == '148') {
        result.brick148Id = match.Id;
      } else {
        result.brickId = match.Id;
      }
      return result;
    } catch (Exception ex) {
      return null;
    }
  }

  private static Brick__c pickBrick(List<Brick__c> bricks, String city) {
    if (bricks == null || bricks.isEmpty()) {
      return null;
    }
    Brick__c fallback = null;
    String needle = city == null ? '' : city.toLowerCase();
    for (Brick__c brick : bricks) {
      if (fallback == null && brick.Brick_Level__c == '702') {
        fallback = brick;
      }
      String haystack =
        ((brick.Name == null ? '' : brick.Name) + ' ' + (brick.City__c == null ? '' : brick.City__c))
          .toLowerCase();
      if (String.isNotBlank(needle) && (haystack.contains(needle) || needle.contains(haystack))) {
        return brick;
      }
    }
    return fallback == null ? bricks[0] : fallback;
  }

  private static List<FieldDiff> buildVezeetaDiffs(
    Account acct,
    VezeetaDoctorService.DoctorProfile profile
  ) {
    List<FieldDiff> diffs = new List<FieldDiff>();
    Boolean addressChanged = false;
    addressChanged =
      addFillOrCorrect(diffs, 'BillingStreet', 'Street', acct.BillingStreet, profile.street, true) ||
      addressChanged;
    addressChanged =
      addFillOrCorrect(diffs, 'BillingCity', 'City', acct.BillingCity, profile.city, true) ||
      addressChanged;
    addressChanged =
      addFillOrCorrect(
        diffs,
        'Governorate__c',
        'Governorate',
        stringVal(acct, 'Governorate__c'),
        profile.governorate,
        true
      ) || addressChanged;
    addFillOrCorrect(
      diffs,
      'Landmark__c',
      'Landmark',
      stringVal(acct, 'Landmark__c'),
      profile.landmark,
      false
    );
    addFillOrCorrect(diffs, 'Website', 'Vezeeta profile URL', acct.Website, profile.profileUrl, false);
    addFillOrCorrect(
      diffs,
      'Specialty_1__c',
      'Specialty 1',
      stringVal(acct, 'Specialty_1__c'),
      profile.specialty1,
      true
    );
    addFillOrCorrect(
      diffs,
      'Specialty_2__c',
      'Specialty 2',
      stringVal(acct, 'Specialty_2__c'),
      profile.specialty2,
      true
    );
    addFillOrCorrect(
      diffs,
      'Specialty_3__c',
      'Specialty 3',
      stringVal(acct, 'Specialty_3__c'),
      profile.specialty3,
      true
    );

    if (profile.latitude != null && profile.longitude != null) {
      String currentLat = acct.BillingLatitude == null ? null : String.valueOf(acct.BillingLatitude);
      String currentLng = acct.BillingLongitude == null ? null : String.valueOf(acct.BillingLongitude);
      Boolean pinBlank = String.isBlank(currentLat) || String.isBlank(currentLng);
      if (pinBlank || addressChanged) {
        addDiff(
          diffs,
          'BillingLatitude',
          'Latitude',
          currentLat,
          String.valueOf(profile.latitude),
          pinBlank ? 'fill' : 'correction'
        );
        addDiff(
          diffs,
          'BillingLongitude',
          'Longitude',
          currentLng,
          String.valueOf(profile.longitude),
          pinBlank ? 'fill' : 'correction'
        );
      }
    }

    if (profile.brick702Id != null) {
      addFillOrCorrect(
        diffs,
        'Brick_702__c',
        'Brick 702',
        stringVal(acct, 'Brick_702__c'),
        String.valueOf(profile.brick702Id),
        false
      );
    }
    if (profile.brick148Id != null) {
      addFillOrCorrect(
        diffs,
        'Brick_148__c',
        'Brick 148',
        stringVal(acct, 'Brick_148__c'),
        String.valueOf(profile.brick148Id),
        false
      );
    }
    if (profile.brickId != null) {
      addFillOrCorrect(
        diffs,
        'Brick__c',
        'Brick',
        stringVal(acct, 'Brick__c'),
        String.valueOf(profile.brickId),
        false
      );
    }
    return diffs;
  }

  private static void addPhoneDiff(List<FieldDiff> diffs, Account acct, String proposedPhone) {
    if (String.isBlank(proposedPhone)) {
      return;
    }
    String mapsPhone = stringVal(acct, 'Maps_Phone_Number__c');
    String proposedKey = phoneKey(proposedPhone);
    if (String.isBlank(proposedKey)) {
      return;
    }
    Set<String> existing = accountPhoneKeys(acct);
    if (existing.contains(proposedKey)) {
      if (String.isBlank(mapsPhone)) {
        addDiff(diffs, 'Maps_Phone_Number__c', 'Maps phone', mapsPhone, proposedPhone, 'fill');
      }
      return;
    }
    if (String.isBlank(mapsPhone)) {
      addDiff(diffs, 'Maps_Phone_Number__c', 'Maps phone', mapsPhone, proposedPhone, 'fill');
    } else if (phoneKey(mapsPhone) != proposedKey) {
      addDiff(diffs, 'Maps_Phone_Number__c', 'Maps phone', mapsPhone, proposedPhone, 'correction');
    }
    if (String.isBlank(acct.Phone)) {
      addDiff(diffs, 'Phone', 'Phone', acct.Phone, proposedPhone, 'fill');
    } else if (phoneKey(acct.Phone) != proposedKey) {
      addDiff(diffs, 'Phone', 'Phone', acct.Phone, proposedPhone, 'correction');
    }
  }

  private static Boolean addFillOrCorrect(
    List<FieldDiff> diffs,
    String field,
    String label,
    String currentValue,
    String proposedValue,
    Boolean allowCorrection
  ) {
    if (String.isBlank(proposedValue)) {
      return false;
    }
    String current = currentValue == null ? null : currentValue.trim();
    String proposed = proposedValue.trim();
    if (String.isBlank(current)) {
      addDiff(diffs, field, label, current, proposed, 'fill');
      return true;
    }
    if (allowCorrection && !sameText(current, proposed)) {
      addDiff(diffs, field, label, current, proposed, 'correction');
      return true;
    }
    return false;
  }

  private static void addDiff(
    List<FieldDiff> diffs,
    String field,
    String label,
    String currentValue,
    String proposedValue,
    String kind
  ) {
    if (String.isBlank(proposedValue)) {
      return;
    }
    FieldDiff diff = new FieldDiff();
    diff.field = field;
    diff.label = label;
    diff.currentValue = currentValue;
    diff.proposedValue = proposedValue;
    diff.kind = kind;
    diff.accepted = true;
    diffs.add(diff);
  }

  private static Boolean sameText(String left, String right) {
    return normalizeText(left) == normalizeText(right);
  }

  private static String normalizeText(String value) {
    return value == null ? '' : value.trim().toLowerCase().replaceAll('\\s+', ' ');
  }

  private static Boolean geoAgrees(Account acct, String city, String area, String governorate) {
    String accountCity = normalizeText(acct.BillingCity);
    String accountGov = normalizeText(stringVal(acct, 'Governorate__c'));
    String hitCity = normalizeText(city);
    String hitArea = normalizeText(area);
    String hitGov = normalizeText(governorate);
    if (String.isBlank(accountCity) && String.isBlank(accountGov)) {
      return true;
    }
    if (String.isNotBlank(accountCity) && (accountCity == hitCity || accountCity == hitArea)) {
      return true;
    }
    if (String.isNotBlank(accountGov) && (accountGov == hitGov || accountGov == hitCity)) {
      return true;
    }
    return false;
  }

  private static Set<String> accountPhoneKeys(Account acct) {
    Set<String> keys = new Set<String>();
    addPhoneKey(keys, acct.Phone);
    addPhoneKey(keys, stringVal(acct, 'PersonMobilePhone'));
    addPhoneKey(keys, stringVal(acct, 'Clinic_Phone__c'));
    addPhoneKey(keys, stringVal(acct, 'Maps_Phone_Number__c'));
    addPhoneKey(keys, stringVal(acct, 'WhatsApp_Number__c'));
    return keys;
  }

  private static void addPhoneKey(Set<String> keys, String value) {
    String key = phoneKey(value);
    if (String.isNotBlank(key)) {
      keys.add(key);
    }
  }

  @TestVisible
  private static String phoneKey(String value) {
    String digits = value == null ? '' : value.replaceAll('\\D', '');
    if (digits.startsWith('00')) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('20') && digits.length() > 10) {
      digits = digits.substring(2);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.length() > 10) {
      digits = digits.substring(digits.length() - 10);
    }
    return digits.length() >= 8 ? digits : null;
  }

  private static String stringVal(Account acct, String fieldName) {
    try {
      Object value = acct.get(fieldName);
      return value == null ? null : String.valueOf(value);
    } catch (Exception ex) {
      return null;
    }
  }

  private static String detailLine(List<String> parts) {
    List<String> clean = new List<String>();
    for (String part : parts) {
      if (String.isNotBlank(part)) {
        clean.add(part.trim());
      }
    }
    return clean.isEmpty() ? null : String.join(clean, ' · ');
  }

  private static String findGovernorate(String address) {
    if (String.isBlank(address)) {
      return null;
    }
    String lower = address.toLowerCase();
    for (String name : new List<String>{
      'Cairo',
      'Giza',
      'Alexandria',
      'Qalyubia',
      'Sharqia',
      'Dakahlia',
      'Beheira',
      'Gharbia',
      'Monufia',
      'Kafr El Sheikh',
      'Damietta',
      'Port Said',
      'Ismailia',
      'Suez',
      'Fayoum',
      'Beni Suef',
      'Minya',
      'Asyut',
      'Sohag',
      'Qena',
      'Luxor',
      'Aswan',
      'Red Sea',
      'New Valley',
      'Matrouh',
      'North Sinai',
      'South Sinai'
    }) {
      if (lower.contains(name.toLowerCase())) {
        return name;
      }
    }
    return null;
  }

  @TestVisible
  private static Decimal distanceKm(Decimal lat1, Decimal lon1, Decimal lat2, Decimal lon2) {
    Double earth = 6371.0;
    Double dLat = ((Double) (lat2 - lat1)) * Math.PI / 180;
    Double dLon = ((Double) (lon2 - lon1)) * Math.PI / 180;
    Double lat1Rad = ((Double) lat1) * Math.PI / 180;
    Double lat2Rad = ((Double) lat2) * Math.PI / 180;
    Double a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1Rad) * Math.cos(lat2Rad) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
    Double c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return Decimal.valueOf(earth * c);
  }
}
