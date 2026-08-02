public without sharing class AccountAffiliationModuleSeed {

    private static final Integer HCP_COUNT = 500;
    private static final Integer BATCH_SIZE = 200;

    public class SeedResult {
        public Integer hcpCount;
        public Integer hcoCount;
        public Integer pharmacyCount;
        public Integer affiliationCount;
        public Integer territoryAssignmentCount;
        public String message;
    }

    /**
     * Seeds demo HCPs, HCOs, pharmacies, affiliations, and territory alignment.
     * Run after TerritoryModuleSeed.seedTerritoriesAndUsers();
     */
    private static Integer getHcpCount() {
        return Test.isRunningTest() ? 5 : HCP_COUNT;
    }

    public static SeedResult seedDemoData() {
        SeedResult result = new SeedResult();
        Integer existing = [
            SELECT COUNT()
            FROM Account
            WHERE External_ID__c LIKE 'DEMO_%'
            WITH SYSTEM_MODE
        ];
        if (!Test.isRunningTest() && existing >= HCP_COUNT) {
            result.message = 'Demo accounts already seeded (' + existing + ' found). Skipping.';
            return result;
        }

        Id personRtId = getRecordTypeId('SDO_PersonAccounts');
        Id hcoRtId = getRecordTypeId('Institution_HCO');
        Id pharmacyRtId = getRecordTypeId('Pharmacy');
        List<Id> mrTerritoryIds = new List<Id>();
        for (Id territoryId : TerritoryModuleSeed.getMrTerritoryIds()) {
            if (territoryId != null) {
                mrTerritoryIds.add(territoryId);
            }
        }

        Map<String, Account> accountsByExtId = new Map<String, Account>();
        Map<String, String> childParentExtIds = new Map<String, String>();

        List<Account> hcos = buildHcoAccounts(hcoRtId, childParentExtIds);
        insertInBatches(hcos, accountsByExtId);

        List<Account> pharmacies = buildPharmacyAccounts(pharmacyRtId, childParentExtIds);
        insertInBatches(pharmacies, accountsByExtId);

        applyParentRelationships(accountsByExtId, childParentExtIds);

        List<Account> hcps = buildHcpAccounts(personRtId, mrTerritoryIds);
        insertInBatches(hcps, accountsByExtId);

        result.hcoCount = hcos.size();
        result.pharmacyCount = pharmacies.size();
        result.hcpCount = hcps.size();

        List<Account_Affiliation__c> affiliations = buildAffiliations(hcos, pharmacies, hcps, accountsByExtId);
        insertInBatches(affiliations, null);
        result.affiliationCount = affiliations.size();

        List<ObjectTerritory2Association> assignments = buildTerritoryAssignments(
            accountsByExtId.values(),
            mrTerritoryIds
        );
        insertInBatches(assignments, null);
        result.territoryAssignmentCount = assignments.size();

        result.message = 'Seeded ' + result.hcpCount + ' HCPs, ' + result.hcoCount +
            ' HCOs, ' + result.pharmacyCount + ' pharmacies, ' + result.affiliationCount + ' affiliations.';
        AccountEgyptianLocalization.localizeAllAccounts();
        return result;
    }

    private static Id getRecordTypeId(String developerName) {
        List<RecordType> recordTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account'
                AND DeveloperName = :developerName
                AND IsActive = true
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (recordTypes.isEmpty()) {
            throw new AuraHandledException('Active Account record type not found: ' + developerName);
        }
        return recordTypes[0].Id;
    }

    private static List<Account> buildHcoAccounts(Id businessRtId, Map<String, String> childParentExtIds) {
        List<Account> accounts = new List<Account>();
        List<ChainDefinition> chains = getHcoChains();
        Integer index = 0;
        for (ChainDefinition chain : chains) {
            String parentExtId = 'DEMO_HCO_PARENT_' + padIndex(index);
            GeoPoint parentGeo = chain.locations[0];
            accounts.add(buildBusinessAccount(
                businessRtId,
                parentExtId,
                chain.parentName,
                'Hospital',
                null,
                parentGeo,
                'Institution'
            ));
            for (Integer branchIdx = 1; branchIdx < chain.branches.size(); branchIdx++) {
                String childExtId = 'DEMO_HCO_' + padIndex(index) + '_' + String.valueOf(branchIdx);
                childParentExtIds.put(childExtId, parentExtId);
                accounts.add(buildBusinessAccount(
                    businessRtId,
                    childExtId,
                    chain.branches[branchIdx],
                    'Hospital',
                    parentExtId,
                    chain.locations[branchIdx],
                    'Branch'
                ));
            }
            index++;
        }
        return accounts;
    }

    private static List<Account> buildPharmacyAccounts(Id businessRtId, Map<String, String> childParentExtIds) {
        List<Account> accounts = new List<Account>();
        List<ChainDefinition> chains = getPharmacyChains();
        Integer index = 0;
        for (ChainDefinition chain : chains) {
            String parentExtId = 'DEMO_PH_PARENT_' + padIndex(index);
            accounts.add(buildBusinessAccount(
                businessRtId,
                parentExtId,
                chain.parentName,
                'Pharmacy',
                null,
                chain.locations[0],
                'Chain'
            ));
            for (Integer branchIdx = 1; branchIdx < chain.branches.size(); branchIdx++) {
                String childExtId = 'DEMO_PH_' + padIndex(index) + '_' + String.valueOf(branchIdx);
                childParentExtIds.put(childExtId, parentExtId);
                accounts.add(buildBusinessAccount(
                    businessRtId,
                    childExtId,
                    chain.branches[branchIdx],
                    'Pharmacy',
                    parentExtId,
                    chain.locations[branchIdx],
                    'Retail'
                ));
            }
            index++;
        }
        return accounts;
    }

    private static Account buildBusinessAccount(
        Id recordTypeId,
        String externalId,
        String name,
        String accountType,
        String parentExtId,
        GeoPoint geo,
        String institutionOrPharmacyType
    ) {
        Account acct = new Account(
            RecordTypeId = recordTypeId,
            Name = name,
            Type = accountType,
            External_ID__c = externalId,
            BillingStreet = geo.street,
            BillingCity = geo.city,
            BillingState = geo.state,
            BillingCountry = geo.country,
            BillingPostalCode = geo.postalCode,
            BillingLatitude = geo.latitude,
            BillingLongitude = geo.longitude,
            Account_Status__c = 'Active',
            Tier__c = 'B'
        );
        if (accountType == 'Pharmacy') {
            acct.Pharmacy_Type__c = institutionOrPharmacyType == 'Chain' ? 'Chain' : 'Retail';
        } else {
            acct.Institution_Type__c = institutionOrPharmacyType == 'Branch' ? 'Clinic' : 'Hospital';
        }
        AccountPhoneDefaults.applyDemoPhone(acct);
        return acct;
    }

    private static List<Account> buildHcpAccounts(Id personRtId, List<Id> mrTerritoryIds) {
        List<Account> accounts = new List<Account>();
        List<HcpDefinition> definitions = buildHcpDefinitions();
        List<GeoPoint> geoPoints = getHcpGeoPoints();

        for (Integer i = 0; i < getHcpCount(); i++) {
            HcpDefinition def = definitions[Math.mod(i, definitions.size())];
            GeoPoint geo = geoPoints[Math.mod(i, geoPoints.size())];
            List<String> tiers = new List<String>{ 'A', 'B', 'C' };
            Account acct = new Account(
                RecordTypeId = personRtId,
                Salutation = def.salutation,
                FirstName = def.firstName,
                LastName = def.lastName + (i >= definitions.size() ? ' ' + String.valueOf(i) : ''),
                PersonEmail = def.emailPrefix + i + '@hcp.eg',
                Type = 'Healthcare Provider',
                External_ID__c = 'DEMO_HCP_' + padIndex(i, 4),
                BillingStreet = geo.street,
                BillingCity = geo.city,
                BillingState = geo.state,
                BillingCountry = geo.country,
                BillingPostalCode = geo.postalCode,
                BillingLatitude = geo.latitude,
                BillingLongitude = geo.longitude,
                Account_Status__c = 'Active',
                Tier__c = tiers[Math.mod(i, tiers.size())],
                Specialty_1__c = def.specialty
            );
            AccountPhoneDefaults.applyDemoPhoneForPerson(acct);
            accounts.add(acct);
        }
        return accounts;
    }

    private static List<Account_Affiliation__c> buildAffiliations(
        List<Account> hcos,
        List<Account> pharmacies,
        List<Account> hcps,
        Map<String, Account> accountsByExtId
    ) {
        List<Account_Affiliation__c> affiliations = new List<Account_Affiliation__c>();
        Map<String, Id> idByExt = new Map<String, Id>();
        for (String extId : accountsByExtId.keySet()) {
            idByExt.put(extId, accountsByExtId.get(extId).Id);
        }

        List<String> strengths = new List<String>{ 'Strong', 'Medium', 'Weak' };
        List<String> influences = new List<String>{ 'High', 'Medium', 'Low' };

        for (Integer i = 0; i < hcps.size(); i++) {
            Account hcp = hcps[i];
            Account practice = hcos[Math.mod(i, hcos.size())];
            affiliations.add(new Account_Affiliation__c(
                Primary_Account__c = hcp.Id,
                Related_Account__c = practice.Id,
                Affiliation_Type__c = 'Practice',
                Role__c = 'Physician',
                Strength__c = strengths[Math.mod(i, strengths.size())],
                Influence__c = influences[Math.mod(i, influences.size())],
                Is_Active__c = Math.mod(i, 10) != 0,
                Outside_Territory__c = Math.mod(i, 7) == 0,
                Description__c = 'Primary practice affiliation'
            ));
            if (Math.mod(i, 3) == 0) {
                Account pharmacy = pharmacies[Math.mod(i, pharmacies.size())];
                affiliations.add(new Account_Affiliation__c(
                    Primary_Account__c = hcp.Id,
                    Related_Account__c = pharmacy.Id,
                    Affiliation_Type__c = 'Partner',
                    Role__c = 'Pharmacist',
                    Strength__c = strengths[Math.mod(i + 1, strengths.size())],
                    Influence__c = influences[Math.mod(i + 1, influences.size())],
                    Is_Active__c = true,
                    Outside_Territory__c = Math.mod(i, 11) == 0,
                    Description__c = 'Preferred pharmacy relationship'
                ));
            }
        }

        for (Account hco : hcos) {
            if (hco.External_ID__c != null && hco.External_ID__c.startsWith('DEMO_HCO_') &&
                !hco.External_ID__c.contains('PARENT')) {
                String parentKey = 'DEMO_HCO_PARENT_' + hco.External_ID__c.split('_')[2];
                if (idByExt.containsKey(parentKey)) {
                    affiliations.add(new Account_Affiliation__c(
                        Primary_Account__c = idByExt.get(parentKey),
                        Related_Account__c = hco.Id,
                        Affiliation_Type__c = 'Subsidiary',
                        Role__c = 'Admin',
                        Strength__c = 'Strong',
                        Influence__c = 'High',
                        Is_Active__c = true,
                        Outside_Territory__c = false,
                        Description__c = 'Institution branch affiliation'
                    ));
                }
            }
        }

        for (Account pharmacy : pharmacies) {
            if (pharmacy.External_ID__c.startsWith('DEMO_PH_') && !pharmacy.External_ID__c.contains('PARENT')) {
                String parentKey = 'DEMO_PH_PARENT_' + pharmacy.External_ID__c.split('_')[2];
                if (idByExt.containsKey(parentKey)) {
                    affiliations.add(new Account_Affiliation__c(
                        Primary_Account__c = idByExt.get(parentKey),
                        Related_Account__c = pharmacy.Id,
                        Affiliation_Type__c = 'Affiliate',
                        Role__c = 'Pharmacist',
                        Strength__c = 'Medium',
                        Influence__c = 'Medium',
                        Is_Active__c = true,
                        Outside_Territory__c = false,
                        Description__c = 'Pharmacy chain branch'
                    ));
                }
            }
        }
        return affiliations;
    }

    private static List<ObjectTerritory2Association> buildTerritoryAssignments(
        List<Account> accounts,
        List<Id> mrTerritoryIds
    ) {
        List<ObjectTerritory2Association> assignments = new List<ObjectTerritory2Association>();
        Set<String> existingKeys = new Set<String>();
        Integer index = 0;
        for (Account acct : accounts) {
            if (acct.Id == null || mrTerritoryIds.isEmpty()) {
                continue;
            }
            Id territoryId = mrTerritoryIds[Math.mod(index, mrTerritoryIds.size())];
            String key = String.valueOf(acct.Id) + '-' + String.valueOf(territoryId);
            if (!existingKeys.contains(key)) {
                assignments.add(new ObjectTerritory2Association(
                    ObjectId = acct.Id,
                    Territory2Id = territoryId,
                    AssociationCause = 'Territory2Manual'
                ));
                existingKeys.add(key);
            }
            index++;
        }
        return assignments;
    }

    private static void insertInBatches(List<SObject> records, Map<String, Account> accountsByExtId) {
        if (records == null || records.isEmpty()) {
            return;
        }
        for (Integer start = 0; start < records.size(); start += BATCH_SIZE) {
            Integer endIdx = Math.min(start + BATCH_SIZE, records.size());
            List<SObject> batch = new List<SObject>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(records[i]);
            }
            Database.SaveResult[] results = Database.insert(batch, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error err : results[i].getErrors()) {
                        throw new DmlException(
                            err.getStatusCode() + ': ' + err.getMessage() +
                            ' [' + batch[i] + ']'
                        );
                    }
                }
            }
            if (accountsByExtId != null) {
                for (SObject record : batch) {
                    Account acct = (Account) record;
                    if (acct.External_ID__c != null) {
                        accountsByExtId.put(acct.External_ID__c, acct);
                    }
                }
            }
        }
    }

    private class ChainDefinition {
        public String parentName;
        public List<String> branches;
        public List<GeoPoint> locations;
    }

    private class GeoPoint {
        public String street;
        public String city;
        public String state;
        public String country;
        public String postalCode;
        public Decimal latitude;
        public Decimal longitude;
    }

    private class HcpDefinition {
        public String salutation;
        public String firstName;
        public String lastName;
        public String emailPrefix;
        public String specialty;
    }

    private static List<ChainDefinition> getHcoChains() {
        return new List<ChainDefinition>{
            chain('Mayo Clinic', new List<String>{
                'Mayo Clinic', 'Mayo Clinic Rochester', 'Mayo Clinic Jacksonville',
                'Mayo Clinic Phoenix', 'Mayo Clinic Scottsdale'
            }, geoList(new List<String>{
                '200 First St SW,Rochester,MN,55905,44.0225,-92.4699',
                '1216 2nd St SW,Rochester,MN,55902,44.0053,-92.4802',
                '4500 San Pablo Rd,Jacksonville,FL,32224,30.2597,-81.5261',
                '5777 E Mayo Blvd,Phoenix,AZ,85054,33.6598,-111.9553',
                '13400 E Shea Blvd,Scottsdale,AZ,85259,33.5831,-111.8836'
            })),
            chain('Cleveland Clinic', new List<String>{
                'Cleveland Clinic', 'Cleveland Clinic Main Campus', 'Cleveland Clinic Florida',
                'Cleveland Clinic London', 'Cleveland Clinic Abu Dhabi'
            }, geoList(new List<String>{
                '9500 Euclid Ave,Cleveland,OH,44195,41.5034,-81.6214',
                '9500 Euclid Ave,Cleveland,OH,44195,41.5034,-81.6214',
                '2950 Cleveland Clinic Blvd,Weston,FL,33331,26.0891,-80.3624',
                '33 Grosvenor Place,London,,SW1X 7HY,51.5007,-0.1540',
                'Al Maryah Island,Abu Dhabi,,00000,24.5000,54.3900'
            })),
            chain('Johns Hopkins Medicine', new List<String>{
                'Johns Hopkins Medicine', 'The Johns Hopkins Hospital', 'Johns Hopkins Bayview',
                'Sibley Memorial Hospital', 'Johns Hopkins All Children\'s'
            }, geoList(new List<String>{
                '1800 Orleans St,Baltimore,MD,21287,39.2971,-76.5929',
                '1800 Orleans St,Baltimore,MD,21287,39.2971,-76.5929',
                '4940 Eastern Ave,Baltimore,MD,21224,39.2898,-76.5474',
                '5255 Loughboro Rd NW,Washington,DC,20016,38.9350,-77.1086',
                '501 6th Ave S,St Petersburg,FL,33701,27.7676,-82.6403'
            })),
            chain('Mass General Brigham', new List<String>{
                'Mass General Brigham', 'Massachusetts General Hospital', 'Brigham and Women\'s Hospital',
                'Newton-Wellesley Hospital', 'Salem Hospital'
            }, geoList(new List<String>{
                '399 Revolution Dr,Somerville,MA,02145,42.3943,-71.0815',
                '55 Fruit St,Boston,MA,02114,42.3631,-71.0686',
                '75 Francis St,Boston,MA,02115,42.3364,-71.1068',
                '2014 Washington St,Newton,MA,02462,42.3309,-71.2500',
                '55 Highland Ave,Salem,MA,01970,42.5151,-70.8950'
            })),
            chain('Cedars-Sinai', new List<String>{
                'Cedars-Sinai', 'Cedars-Sinai Medical Center', 'Cedars-Sinai Marina del Rey',
                'Cedars-Sinai Guerin Children\'s', 'Cedars-Sinai Tarzana'
            }, geoList(new List<String>{
                '8700 Beverly Blvd,Los Angeles,CA,90048,34.0753,-118.3803',
                '8700 Beverly Blvd,Los Angeles,CA,90048,34.0753,-118.3803',
                '4320 Marina City Dr,Marina del Rey,CA,90292,33.9850,-118.4515',
                '8700 Beverly Blvd,Los Angeles,CA,90048,34.0753,-118.3803',
                '18321 Clark St,Tarzana,CA,91356,34.1722,-118.5448'
            })),
            chain('NYU Langone Health', new List<String>{
                'NYU Langone Health', 'NYU Langone Tisch Hospital', 'NYU Langone Brooklyn',
                'NYU Langone Long Island', 'NYU Langone Orthopedic Hospital'
            }, geoList(new List<String>{
                '550 1st Ave,New York,NY,10016,40.7421,-73.9742',
                '550 1st Ave,New York,NY,10016,40.7421,-73.9742',
                '150 55th St,Brooklyn,NY,11220,40.6324,-74.0170',
                '200 Community Dr,Manhasset,NY,11030,40.7890,-73.6990',
                '301 E 17th St,New York,NY,10003,40.7347,-73.9857'
            })),
            chain('Mount Sinai Health System', new List<String>{
                'Mount Sinai Health System', 'Mount Sinai Hospital', 'Mount Sinai West',
                'Mount Sinai Morningside', 'Mount Sinai Queens'
            }, geoList(new List<String>{
                '1 Gustave L Levy Pl,New York,NY,10029,40.7901,-73.9529',
                '1 Gustave L Levy Pl,New York,NY,10029,40.7901,-73.9529',
                '1000 10th Ave,New York,NY,10019,40.7698,-73.9870',
                '1111 Amsterdam Ave,New York,NY,10025,40.8075,-73.9590',
                '25-10 30th Ave,Astoria,NY,11102,40.7689,-73.9190'
            })),
            chain('Stanford Medicine', new List<String>{
                'Stanford Medicine', 'Stanford Hospital', 'Stanford Children\'s Health',
                'Stanford ValleyCare', 'Stanford Palo Alto Clinic'
            }, geoList(new List<String>{
                '300 Pasteur Dr,Stanford,CA,94305,37.4335,-122.1750',
                '300 Pasteur Dr,Stanford,CA,94305,37.4335,-122.1750',
                '725 Welch Rd,Palo Alto,CA,94304,37.4352,-122.1750',
                '5555 W Las Positas Blvd,Pleasanton,CA,94588,37.6819,-121.8920',
                '211 Quarry Rd,Palo Alto,CA,94304,37.4419,-122.1630'
            })),
            chain('UCSF Health', new List<String>{
                'UCSF Health', 'UCSF Medical Center Parnassus', 'UCSF Mission Bay',
                'UCSF Mount Zion', 'UCSF Benioff Children\'s'
            }, geoList(new List<String>{
                '505 Parnassus Ave,San Francisco,CA,94143,37.7626,-122.4586',
                '505 Parnassus Ave,San Francisco,CA,94143,37.7626,-122.4586',
                '1855 4th St,San Francisco,CA,94158,37.7670,-122.3910',
                '1600 Divisadero St,San Francisco,CA,94115,37.7847,-122.4380',
                '1975 4th St,San Francisco,CA,94158,37.7649,-122.3900'
            })),
            chain('Houston Methodist', new List<String>{
                'Houston Methodist', 'Houston Methodist Hospital', 'Houston Methodist Sugar Land',
                'Houston Methodist Willowbrook', 'Houston Methodist Baytown'
            }, geoList(new List<String>{
                '6565 Fannin St,Houston,TX,77030,29.7098,-95.3984',
                '6565 Fannin St,Houston,TX,77030,29.7098,-95.3984',
                '16655 Southwest Fwy,Sugar Land,TX,77479,29.6205,-95.6350',
                '18220 State Hwy 249,Houston,TX,77070,29.9608,-95.5410',
                '4401 Garth Rd,Baytown,TX,77521,29.7780,-94.9770'
            }))
        };
    }

    private static List<ChainDefinition> getPharmacyChains() {
        return new List<ChainDefinition>{
            chain('CVS Pharmacy', new List<String>{
                'CVS Pharmacy', 'CVS Boston Downtown', 'CVS New York Midtown',
                'CVS Chicago Loop', 'CVS Los Angeles Westwood', 'CVS Miami Beach', 'CVS Dallas Uptown'
            }, geoList(new List<String>{
                '1 CVS Dr,Woonsocket,RI,02895,42.0029,-71.5148',
                '80 Summer St,Boston,MA,02110,42.3539,-71.0577',
                '150 E 42nd St,New York,NY,10017,40.7505,-73.9754',
                '1 S State St,Chicago,IL,60603,41.8819,-87.6278',
                '10889 Wilshire Blvd,Los Angeles,CA,90024,34.0596,-118.4452',
                '1670 Meridian Ave,Miami Beach,FL,33139,25.7907,-80.1368',
                '2800 Main St,Dallas,TX,75226,32.7831,-96.7836'
            })),
            chain('Walgreens', new List<String>{
                'Walgreens', 'Walgreens Seattle Capitol Hill', 'Walgreens Denver LoDo',
                'Walgreens Atlanta Midtown', 'Walgreens Phoenix Central', 'Walgreens Philadelphia Center City', 'Walgreens Houston Medical Center'
            }, geoList(new List<String>{
                '108 Wilmot Rd,Deerfield,IL,60015,42.1514,-87.8598',
                '600 Broadway E,Seattle,WA,98102,47.6250,-122.3210',
                '1600 Wewatta St,Denver,CO,80202,39.7547,-105.0014',
                '650 Ponce de Leon Ave NE,Atlanta,GA,30308,33.7740,-84.3655',
                '3402 N Central Ave,Phoenix,AZ,85012,33.4839,-112.0740',
                '1600 Market St,Philadelphia,PA,19103,39.9526,-75.1677',
                '7900 Fannin St,Houston,TX,77054,29.6984,-95.3995'
            })),
            chain('Boots Pharmacy', new List<String>{
                'Boots Pharmacy', 'Boots London Oxford Street', 'Boots Manchester Market St',
                'Boots Birmingham New St', 'Boots Edinburgh Princes St', 'Boots Glasgow Buchanan St', 'Boots Belfast Donegall Place'
            }, geoList(new List<String>{
                '1 Thane Road,Nottingham,,NG2 3AA,52.9438,-1.1332',
                '214 Oxford St,London,,W1D 1LA,51.5154,-0.1419',
                '32 Market St,Manchester,,M1 1PL,53.4828,-2.2426',
                '38 New St,Birmingham,,B2 4BQ,52.4784,-1.8986',
                '101 Princes St,Edinburgh,,EH2 3AA,55.9521,-3.1965',
                '98 Buchanan St,Glasgow,,G1 3HF,55.8617,-4.2520',
                '35 Donegall Place,Belfast,,BT1 5AD,54.5973,-5.9301'
            })),
            chain('Rite Aid', new List<String>{
                'Rite Aid', 'Rite Aid Portland Downtown', 'Rite Aid San Diego Hillcrest',
                'Rite Aid Detroit Midtown', 'Rite Aid Minneapolis Uptown', 'Rite Aid Tampa Hyde Park', 'Rite Aid Charlotte Uptown'
            }, geoList(new List<String>{
                '30 Hunter Ln,Camp Hill,PA,17011,40.2398,-76.9199',
                '630 SW 5th Ave,Portland,OR,97204,45.5189,-122.6784',
                '401 University Ave,San Diego,CA,92103,32.7489,-117.1544',
                '440 Woodward Ave,Detroit,MI,48226,42.3314,-83.0458',
                '2929 Hennepin Ave,Minneapolis,MN,55408,44.9484,-93.2983',
                '1500 W Swann Ave,Tampa,FL,33606,27.9395,-82.4764',
                '200 S Tryon St,Charlotte,NC,28202,35.2271,-80.8431'
            })),
            chain('Duane Reade', new List<String>{
                'Duane Reade', 'Duane Reade Times Square', 'Duane Reade Brooklyn Heights',
                'Duane Reade Bronx Fordham', 'Duane Reade Queens Astoria', 'Duane Reade Staten Island', 'Duane Reade Jersey City'
            }, geoList(new List<String>{
                '440 9th Ave,New York,NY,10001,40.7549,-73.9940',
                '1550 Broadway,New York,NY,10036,40.7580,-73.9855',
                '98 Montague St,Brooklyn,NY,11201,40.6958,-73.9956',
                '238 W Fordham Rd,Bronx,NY,10468,40.8618,-73.9015',
                '31-01 Broadway,Astoria,NY,11106,40.7614,-73.9255',
                '2655 Richmond Ave,Staten Island,NY,10314,40.5801,-74.1668',
                '35 Journal Square,Jersey City,NJ,07306,40.7330,-74.0630'
            }))
        };
    }

    private static ChainDefinition chain(String parentName, List<String> branches, List<GeoPoint> locations) {
        ChainDefinition def = new ChainDefinition();
        def.parentName = parentName;
        def.branches = branches;
        def.locations = locations;
        return def;
    }

    private static List<GeoPoint> geoList(List<String> encoded) {
        List<GeoPoint> points = new List<GeoPoint>();
        for (String row : encoded) {
            List<String> parts = row.split(',');
            GeoPoint geo = new GeoPoint();
            geo.street = parts[0];
            geo.city = parts[1];
            geo.state = parts[2];
            geo.postalCode = parts[3];
            geo.latitude = Decimal.valueOf(parts[4]);
            geo.longitude = Decimal.valueOf(parts[5]);
            geo.country = 'Egypt';
            points.add(geo);
        }
        return points;
    }

    private static List<HcpDefinition> buildHcpDefinitions() {
        List<HcpDefinition> defs = new List<HcpDefinition>();
        addHcp(defs, 'Dr.', 'Anthony', 'Fauci', 'afauci', 'Tropical_Medicine');
        addHcp(defs, 'Dr.', 'Sanjay', 'Gupta', 'sgupta', 'Child_Surgery');
        addHcp(defs, 'Dr.', 'Eric', 'Topol', 'etopol', 'Cardiology');
        addHcp(defs, 'Dr.', 'Atul', 'Gawande', 'agawande', 'Endoscopic_Surgery');
        addHcp(defs, 'Dr.', 'Paul', 'Farmer', 'pfarmer', 'Tropical_Medicine');
        addHcp(defs, 'Dr.', 'Vivek', 'Murthy', 'vmurthy', 'Administration');
        addHcp(defs, 'Dr.', 'Megan', 'Ranney', 'mranney', 'Accident_and_Emergency');
        addHcp(defs, 'Dr.', 'Leana', 'Wen', 'lwen', 'Administration');
        addHcp(defs, 'Dr.', 'Harvey', 'Karp', 'hkarp', 'Paediatrics');
        addHcp(defs, 'Dr.', 'William', 'Li', 'wli', 'Paediatric_Oncology');
        addHcp(defs, 'Dr.', 'Lisa', 'Saunders', 'lsaunders', 'Diabetology');
        addHcp(defs, 'Dr.', 'Robert', 'Califf', 'rcaliff', 'Cardiology');
        addHcp(defs, 'Dr.', 'Francis', 'Collins', 'fcollins', 'Genetics');
        addHcp(defs, 'Dr.', 'Patricia', 'Bath', 'pbath', 'Miscellaneous');
        addHcp(defs, 'Dr.', 'Bennet', 'Omalu', 'bomalu', 'Pathology');
        addHcp(defs, 'Dr.', 'Nancy', 'Snyderman', 'nsnyderman', 'Otorhinolaryngology');
        addHcp(defs, 'Dr.', 'David', 'Agus', 'dagus', 'Paediatric_Oncology');
        addHcp(defs, 'Dr.', 'Jennifer', 'Ashton', 'jashton', 'Fertility_Reproductive');
        addHcp(defs, 'Dr.', 'Mehmet', 'Oz', 'moz', 'Cardiothoracic_Thoracic_Surgery');
        addHcp(defs, 'Dr.', 'Deepak', 'Chopra', 'dchopra', 'Geriatrics');
        List<String> firstNames = new List<String>{
            'James', 'Mary', 'Robert', 'Patricia', 'John', 'Jennifer', 'Michael', 'Linda',
            'David', 'Elizabeth', 'Richard', 'Barbara', 'Joseph', 'Susan', 'Thomas', 'Jessica'
        };
        List<String> lastNames = new List<String>{
            'Smith', 'Johnson', 'Williams', 'Brown', 'Jones', 'Garcia', 'Miller', 'Davis',
            'Rodriguez', 'Martinez', 'Hernandez', 'Lopez', 'Gonzalez', 'Wilson', 'Anderson', 'Thomas'
        };
        List<String> specialties = new List<String>{
            'Cardiology', 'Diabetology', 'Geriatrics', 'Paediatrics', 'Paediatric_Oncology', 'Pneumology'
        };
        while (defs.size() < 120) {
            Integer idx = defs.size();
            addHcp(
                defs,
                'Dr.',
                firstNames[Math.mod(idx, firstNames.size())],
                lastNames[Math.mod(idx, lastNames.size())],
                'hcp' + idx,
                specialties[Math.mod(idx, specialties.size())]
            );
        }
        return defs;
    }

    private static void addHcp(
        List<HcpDefinition> defs,
        String salutation,
        String firstName,
        String lastName,
        String emailPrefix,
        String specialty
    ) {
        HcpDefinition def = new HcpDefinition();
        def.salutation = salutation;
        def.firstName = firstName;
        def.lastName = lastName;
        def.emailPrefix = emailPrefix;
        def.specialty = specialty;
        defs.add(def);
    }

    private static List<GeoPoint> getHcpGeoPoints() {
        return geoList(new List<String>{
            '75 Francis St,Boston,MA,02115,42.3364,-71.1068',
            '9500 Euclid Ave,Cleveland,OH,44195,41.5034,-81.6214',
            '1800 Orleans St,Baltimore,MD,21287,39.2971,-76.5929',
            '8700 Beverly Blvd,Los Angeles,CA,90048,34.0753,-118.3803',
            '200 First St SW,Rochester,MN,55905,44.0225,-92.4699',
            '300 Pasteur Dr,Stanford,CA,94305,37.4335,-122.1750',
            '505 Parnassus Ave,San Francisco,CA,94143,37.7626,-122.4586',
            '1500 E Medical Center Dr,Ann Arbor,MI,48109,42.2920,-83.7227',
            '5841 S Maryland Ave,Chicago,IL,60637,41.7891,-87.6045',
            '1 Gustave L Levy Pl,New York,NY,10029,40.7901,-73.9529',
            '3400 Spruce St,Philadelphia,PA,19104,39.9509,-75.1930',
            '1215 4th Ave,Seattle,WA,98101,47.6062,-122.3321'
        });
    }

    private static void applyParentRelationships(
        Map<String, Account> accountsByExtId,
        Map<String, String> childParentExtIds
    ) {
        List<Account> updates = new List<Account>();
        for (String childExtId : childParentExtIds.keySet()) {
            String parentExtId = childParentExtIds.get(childExtId);
            if (accountsByExtId.containsKey(childExtId) && accountsByExtId.containsKey(parentExtId)) {
                updates.add(new Account(
                    Id = accountsByExtId.get(childExtId).Id,
                    ParentId = accountsByExtId.get(parentExtId).Id
                ));
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, AccessLevel.SYSTEM_MODE);
        }
    }

    private static String padIndex(Integer value) {
        return padIndex(value, 2);
    }

    private static String padIndex(Integer value, Integer width) {
        String raw = String.valueOf(value);
        while (raw.length() < width) {
            raw = '0' + raw;
        }
        return raw;
    }
}
