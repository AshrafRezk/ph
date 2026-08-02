public without sharing class AccountEgyptianLocalization {

    private static final Integer BATCH_SIZE = 200;
    private static final String COUNTRY = 'Egypt';

    public class LocalizationResult {
        public Integer updatedCount;
        public Integer failedCount;
        public String message;
    }

    public static LocalizationResult localizeAllAccounts() {
        LocalizationResult result = new LocalizationResult();
        result.updatedCount = 0;
        result.failedCount = 0;

        Map<String, BusinessEntry> hcoEntries = buildHcoLookup();
        Map<String, BusinessEntry> pharmacyEntries = buildPharmacyLookup();
        List<HcpEntry> hcpDefs = buildHcpDefinitions();
        List<GeoPoint> hcpGeos = getHcpGeoPoints();

        List<Account> updates = new List<Account>();
        for (Account acct : [
            SELECT Id, Name, External_ID__c, RecordType.DeveloperName,
                   FirstName, LastName, Salutation, PersonEmail, IsPersonAccount
            FROM Account
            WITH SYSTEM_MODE
        ]) {
            Account patch = buildLocalizedAccount(
                acct,
                hcoEntries,
                pharmacyEntries,
                hcpDefs,
                hcpGeos
            );
            if (patch != null) {
                AccountPhoneDefaults.applyDemoPhone(patch);
                if (acct.IsPersonAccount) {
                    AccountPhoneDefaults.applyDemoPhoneForPerson(patch);
                }
                updates.add(patch);
            }
        }

        for (Integer start = 0; start < updates.size(); start += BATCH_SIZE) {
            Integer endIdx = Math.min(start + BATCH_SIZE, updates.size());
            List<Account> batch = new List<Account>();
            for (Integer i = start; i < endIdx; i++) {
                batch.add(updates[i]);
            }
            Database.SaveResult[] results = Database.update(batch, false, AccessLevel.SYSTEM_MODE);
            for (Database.SaveResult sr : results) {
                if (sr.isSuccess()) {
                    result.updatedCount++;
                } else {
                    result.failedCount++;
                }
            }
        }

        result.message = 'Localized ' + result.updatedCount + ' accounts (' + result.failedCount + ' failed).';
        return result;
    }

    private static Account buildLocalizedAccount(
        Account acct,
        Map<String, BusinessEntry> hcoEntries,
        Map<String, BusinessEntry> pharmacyEntries,
        List<HcpEntry> hcpDefs,
        List<GeoPoint> hcpGeos
    ) {
        String extId = acct.External_ID__c;
        Account patch = new Account(Id = acct.Id);

        if (extId != null && extId.startsWith('DEMO_HCP_')) {
            Integer idx = Integer.valueOf(extId.substring('DEMO_HCP_'.length()));
            HcpEntry def = hcpDefs[Math.mod(idx, hcpDefs.size())];
            GeoPoint geo = hcpGeos[Math.mod(idx, hcpGeos.size())];
            patch.Salutation = def.salutation;
            patch.FirstName = def.firstName;
            patch.LastName = def.lastName + (idx >= hcpDefs.size() ? ' ' + String.valueOf(idx) : '');
            patch.PersonEmail = def.emailPrefix + idx + '@hcp.eg';
            applyGeo(patch, geo);
            return patch;
        }

        if (extId != null && hcoEntries.containsKey(extId)) {
            BusinessEntry entry = hcoEntries.get(extId);
            patch.Name = entry.name;
            applyGeo(patch, entry.geo);
            return patch;
        }

        if (extId != null && pharmacyEntries.containsKey(extId)) {
            BusinessEntry entry = pharmacyEntries.get(extId);
            patch.Name = entry.name;
            applyGeo(patch, entry.geo);
            return patch;
        }

        if (extId == null || !extId.startsWith('DEMO_')) {
            Integer legacyIdx = Math.abs(hashCode(acct.Id)) ;
            List<String> legacyNames = getLegacyEgyptianNames();
            patch.Name = legacyNames[Math.mod(legacyIdx, legacyNames.size())];
            applyGeo(patch, getHcpGeoPoints()[Math.mod(legacyIdx, getHcpGeoPoints().size())]);
            if (acct.RecordType.DeveloperName == 'SDO_PersonAccounts') {
                List<HcpEntry> defs = buildHcpDefinitions();
                HcpEntry def = defs[Math.mod(legacyIdx, defs.size())];
                patch.Salutation = 'Dr.';
                patch.FirstName = def.firstName;
                patch.LastName = def.lastName;
                patch.PersonEmail = 'legacy' + legacyIdx + '@hcp.eg';
            }
            return patch;
        }

        return null;
    }

    private static void applyGeo(Account acct, GeoPoint geo) {
        acct.BillingStreet = geo.street;
        acct.BillingCity = geo.city;
        acct.BillingState = geo.state;
        acct.BillingCountry = COUNTRY;
        acct.BillingPostalCode = geo.postalCode;
        acct.BillingLatitude = geo.latitude;
        acct.BillingLongitude = geo.longitude;
        acct.ShippingStreet = geo.street;
        acct.ShippingCity = geo.city;
        acct.ShippingState = geo.state;
        acct.ShippingCountry = COUNTRY;
        acct.ShippingPostalCode = geo.postalCode;
    }

    private static Integer hashCode(Id recordId) {
        String token = String.valueOf(recordId);
        Integer hash = 0;
        for (Integer i = 0; i < token.length(); i++) {
            hash = (hash * 31) + token.charAt(i);
        }
        return Math.abs(hash);
    }

    private class BusinessEntry {
        public String name;
        public GeoPoint geo;
    }

    private class GeoPoint {
        public String street;
        public String city;
        public String state;
        public String postalCode;
        public Decimal latitude;
        public Decimal longitude;
    }

    private class HcpEntry {
        public String salutation;
        public String firstName;
        public String lastName;
        public String emailPrefix;
    }

    private static Map<String, BusinessEntry> buildHcoLookup() {
        Map<String, BusinessEntry> lookup = new Map<String, BusinessEntry>();
        Integer chainIdx = 0;
        for (ChainDefinition chain : getHcoChains()) {
            String parentExtId = 'DEMO_HCO_PARENT_' + padIndex(chainIdx);
            addBusinessEntry(lookup, parentExtId, chain.parentName, chain.locations[0]);
            for (Integer branchIdx = 1; branchIdx < chain.branches.size(); branchIdx++) {
                String childExtId = 'DEMO_HCO_' + padIndex(chainIdx) + '_' + String.valueOf(branchIdx);
                addBusinessEntry(lookup, childExtId, chain.branches[branchIdx], chain.locations[branchIdx]);
            }
            chainIdx++;
        }
        return lookup;
    }

    private static Map<String, BusinessEntry> buildPharmacyLookup() {
        Map<String, BusinessEntry> lookup = new Map<String, BusinessEntry>();
        Integer chainIdx = 0;
        for (ChainDefinition chain : getPharmacyChains()) {
            String parentExtId = 'DEMO_PH_PARENT_' + padIndex(chainIdx);
            addBusinessEntry(lookup, parentExtId, chain.parentName, chain.locations[0]);
            for (Integer branchIdx = 1; branchIdx < chain.branches.size(); branchIdx++) {
                String childExtId = 'DEMO_PH_' + padIndex(chainIdx) + '_' + String.valueOf(branchIdx);
                addBusinessEntry(lookup, childExtId, chain.branches[branchIdx], chain.locations[branchIdx]);
            }
            chainIdx++;
        }
        return lookup;
    }

    private static void addBusinessEntry(
        Map<String, BusinessEntry> lookup,
        String extId,
        String name,
        GeoPoint geo
    ) {
        BusinessEntry entry = new BusinessEntry();
        entry.name = name;
        entry.geo = geo;
        lookup.put(extId, entry);
    }

    private static List<String> getLegacyEgyptianNames() {
        return new List<String>{
            'Delta Pharma Egypt',
            'Nile Medical Supplies',
            'Cairo Health Partners',
            'Alexandria Care Group',
            'Giza Pharmaceutical Trading',
            'Upper Egypt Clinics',
            'Red Sea Healthcare Services'
        };
    }

    private class ChainDefinition {
        public String parentName;
        public List<String> branches;
        public List<GeoPoint> locations;
    }

    private static List<ChainDefinition> getHcoChains() {
        return new List<ChainDefinition>{
            chain('Ain Shams University Hospitals', new List<String>{
                'Ain Shams University Hospitals', 'Ain Shams El-Demerdash Hospital',
                'Ain Shams El-Khanka Hospital', 'Ain Shams Heliopolis Hospital', 'Ain Shams Obour Hospital'
            }, egyptGeoList(new List<String>{
                'Ramses St,Abbassia,Cairo,11566,30.0697,31.2800',
                'Ramses St,Abbassia,Cairo,11566,30.0697,31.2800',
                'El-Khanka,Qalyubia,Cairo,13714,30.2100,31.3200',
                'El-Orouba Rd,Heliopolis,Cairo,11341,30.0876,31.3249',
                'Industrial Zone,Obour City,Cairo,11828,30.1780,31.4650'
            })),
            chain('Cairo University Hospitals', new List<String>{
                'Cairo University Hospitals', 'Kasr Al Ainy Teaching Hospital',
                'Qasr El Eyni Faculty Hospital', 'Beni Suef University Hospital Branch',
                'Fayoum University Hospital Branch'
            }, egyptGeoList(new List<String>{
                'Kasr Al Ainy St,Cairo,Cairo,11562,30.0287,31.2310',
                'Kasr Al Ainy St,Cairo,Cairo,11562,30.0287,31.2310',
                'Manial,Cairo,Cairo,11553,30.0220,31.2240',
                'Beni Suef,Beni Suef,Beni Suef,62511,29.3667,31.0900',
                'Fayoum,Fayoum,Fayoum,63514,29.3084,30.8428'
            })),
            chain('Cleopatra Hospital Group', new List<String>{
                'Cleopatra Hospital Group', 'Cleopatra Hospital Heliopolis',
                'Cleopatra Hospital Maadi', 'Cleopatra Hospital Nasr City', 'Cleopatra Hospital 6th October'
            }, egyptGeoList(new List<String>{
                'Cleopatra Hospital,Heliopolis,Cairo,11341,30.0876,31.3249',
                'Cleopatra Hospital,Heliopolis,Cairo,11341,30.0876,31.3249',
                'Road 9,Maadi,Cairo,11431,29.9602,31.2569',
                'Abbas El Akkad St,Nasr City,Cairo,11765,30.0511,31.3656',
                'Central Axis,6th of October,Giza,12573,29.9285,30.9188'
            })),
            chain('Saudi German Hospital Egypt', new List<String>{
                'Saudi German Hospital Egypt', 'Saudi German Hospital Cairo',
                'Saudi German Hospital Hurghada', 'Saudi German Hospital Alexandria',
                'Saudi German Hospital Sharm El Sheikh'
            }, egyptGeoList(new List<String>{
                'Ring Rd,Nasr City,Cairo,11765,30.0511,31.3656',
                'Ring Rd,Nasr City,Cairo,11765,30.0511,31.3656',
                'Airport Rd,Hurghada,Red Sea,84511,27.2579,33.8116',
                'Victoria Sq,Smouha,Alexandria,21599,31.2156,29.9427',
                'Naama Bay,Sharm El Sheikh,South Sinai,46619,27.9158,34.3300'
            })),
            chain('Dar Al Fouad Hospital', new List<String>{
                'Dar Al Fouad Hospital', 'Dar Al Fouad Nasr City',
                'Dar Al Fouad Mohandessin', 'Dar Al Fouad Maadi', 'Dar Al Fouad Alexandria'
            }, egyptGeoList(new List<String>{
                '26th July Corridor,Nasr City,Cairo,11765,30.0511,31.3656',
                '26th July Corridor,Nasr City,Cairo,11765,30.0511,31.3656',
                'Gameat El Dewal,Mohandessin,Giza,12611,30.0500,31.2000',
                'Road 9,Maadi,Cairo,11431,29.9602,31.2569',
                'Stanley,Alexandria,Alexandria,21599,31.2396,29.9602'
            })),
            chain('57357 Children\'s Cancer Hospital Egypt', new List<String>{
                '57357 Children\'s Cancer Hospital Egypt', '57357 Outpatient Clinic',
                '57357 Research Center', '57357 Bone Marrow Unit', '57357 Imaging Center'
            }, egyptGeoList(new List<String>{
                'Sekket El Gdida,New Cairo,Cairo,11835,30.0300,31.4700',
                'Sekket El Gdida,New Cairo,Cairo,11835,30.0300,31.4700',
                'Sekket El Gdida,New Cairo,Cairo,11835,30.0310,31.4710',
                'Sekket El Gdida,New Cairo,Cairo,11835,30.0320,31.4720',
                'Sekket El Gdida,New Cairo,Cairo,11835,30.0330,31.4730'
            })),
            chain('Nasser Institute Hospital', new List<String>{
                'Nasser Institute Hospital', 'Nasser Institute Cardiology Wing',
                'Nasser Institute Oncology Wing', 'Nasser Institute Neurology Wing',
                'Nasser Institute Rehabilitation Center'
            }, egyptGeoList(new List<String>{
                'Corniche El Nile,Dokki,Giza,12613,30.0380,31.2120',
                'Corniche El Nile,Dokki,Giza,12613,30.0380,31.2120',
                'Corniche El Nile,Dokki,Giza,12613,30.0385,31.2125',
                'Corniche El Nile,Dokki,Giza,12613,30.0390,31.2130',
                'Corniche El Nile,Dokki,Giza,12613,30.0395,31.2135'
            })),
            chain('As-Salam International Hospital', new List<String>{
                'As-Salam International Hospital', 'As-Salam Mohandessin',
                'As-Salam Maadi', 'As-Salam Sheikh Zayed', 'As-Salam New Cairo'
            }, egyptGeoList(new List<String>{
                'Corniche El Nil,Mohandessin,Giza,12611,30.0500,31.2000',
                'Corniche El Nil,Mohandessin,Giza,12611,30.0500,31.2000',
                'Road 9,Maadi,Cairo,11431,29.9602,31.2569',
                'Sheikh Zayed City,Giza,Giza,12588,30.0280,30.9780',
                'Suez Rd,New Cairo,Cairo,11835,30.0300,31.4700'
            })),
            chain('Maadi Military Hospital', new List<String>{
                'Maadi Military Hospital', 'Maadi Military Emergency Unit',
                'Maadi Military Specialty Center', 'Maadi Military Outpatient Clinic',
                'Maadi Military Rehabilitation Unit'
            }, egyptGeoList(new List<String>{
                'Maadi Corniche,Maadi,Cairo,11431,29.9602,31.2569',
                'Maadi Corniche,Maadi,Cairo,11431,29.9602,31.2569',
                'Maadi Corniche,Maadi,Cairo,11431,29.9610,31.2575',
                'Maadi Corniche,Maadi,Cairo,11431,29.9615,31.2580',
                'Maadi Corniche,Maadi,Cairo,11431,29.9620,31.2585'
            })),
            chain('Alexandria University Hospitals', new List<String>{
                'Alexandria University Hospitals', 'El Hadara University Hospital',
                'El Shatby University Hospital', 'Smouha University Hospital',
                'Borg El Arab University Hospital'
            }, egyptGeoList(new List<String>{
                'Champollion St,Alexandria,Alexandria,21111,31.2001,29.9187',
                'El Hadara,Alexandria,Alexandria,21526,31.2100,29.9300',
                'El Shatby,Alexandria,Alexandria,21516,31.2200,29.9400',
                'Smouha,Alexandria,Alexandria,21599,31.2156,29.9427',
                'Borg El Arab,Alexandria,Alexandria,21934,30.9178,29.5695'
            }))
        };
    }

    private static List<ChainDefinition> getPharmacyChains() {
        return new List<ChainDefinition>{
            chain('El Ezaby Pharmacy', new List<String>{
                'El Ezaby Pharmacy', 'El Ezaby Zamalek', 'El Ezaby Nasr City',
                'El Ezaby Maadi', 'El Ezaby Heliopolis', 'El Ezaby Alexandria', 'El Ezaby Mansoura'
            }, egyptGeoList(new List<String>{
                '26th July St,Zamalek,Cairo,11211,30.0626,31.2197',
                '26th July St,Zamalek,Cairo,11211,30.0626,31.2197',
                'Abbas El Akkad St,Nasr City,Cairo,11765,30.0511,31.3656',
                'Road 9,Maadi,Cairo,11431,29.9602,31.2569',
                'El-Orouba Rd,Heliopolis,Cairo,11341,30.0876,31.3249',
                'Stanley,Alexandria,Alexandria,21599,31.2396,29.9602',
                'Gomhoria St,Mansoura,Dakahlia,35511,31.0409,31.3785'
            })),
            chain('Seif Pharmacies', new List<String>{
                'Seif Pharmacies', 'Seif Pharmacies Dokki', 'Seif Pharmacies Mohandessin',
                'Seif Pharmacies 6th October', 'Seif Pharmacies Tanta', 'Seif Pharmacies Zagazig',
                'Seif Pharmacies Luxor'
            }, egyptGeoList(new List<String>{
                'Tahrir St,Dokki,Giza,12613,30.0380,31.2120',
                'Tahrir St,Dokki,Giza,12613,30.0380,31.2120',
                'Lebanon St,Mohandessin,Giza,12611,30.0500,31.2000',
                'Central Axis,6th of October,Giza,12573,29.9285,30.9188',
                'El Galaa St,Tanta,Gharbia,31511,30.7865,31.0004',
                'El Galaa St,Zagazig,Sharqia,44511,30.5877,31.5020',
                'Karnak St,Luxor,Luxor,85951,25.6872,32.6396'
            })),
            chain('Gad Pharmacy', new List<String>{
                'Gad Pharmacy', 'Gad Pharmacy Heliopolis', 'Gad Pharmacy Nasr City',
                'Gad Pharmacy Giza', 'Gad Pharmacy Alexandria', 'Gad Pharmacy Ismailia',
                'Gad Pharmacy Port Said'
            }, egyptGeoList(new List<String>{
                'El Hegaz St,Heliopolis,Cairo,11341,30.0876,31.3249',
                'El Hegaz St,Heliopolis,Cairo,11341,30.0876,31.3249',
                'Mostafa El Nahas St,Nasr City,Cairo,11765,30.0511,31.3656',
                'Pyramids Rd,Giza,Giza,12511,30.0131,31.2089',
                'Fouad St,Alexandria,Alexandria,21111,31.2001,29.9187',
                'Salah Salem St,Ismailia,Ismailia,41511,30.5965,32.2715',
                '23rd July St,Port Said,Port Said,42511,31.2653,32.3019'
            })),
            chain('El Nabawy Pharmacy', new List<String>{
                'El Nabawy Pharmacy', 'El Nabawy Shubra', 'El Nabawy Downtown Cairo',
                'El Nabawy Faisal Giza', 'El Nabawy Hurghada', 'El Nabawy Aswan', 'El Nabawy Suez'
            }, egyptGeoList(new List<String>{
                'Shubra St,Shubra,Cairo,11651,30.0710,31.2450',
                'Shubra St,Shubra,Cairo,11651,30.0710,31.2450',
                'Talaat Harb St,Downtown Cairo,Cairo,11511,30.0444,31.2357',
                'Faisal St,Giza,Giza,12511,30.0131,31.2089',
                'Sheraton Rd,Hurghada,Red Sea,84511,27.2579,33.8116',
                'Corniche,Aswan,Aswan,81511,24.0889,32.8998',
                'Salah Salem St,Suez,Suez,43511,29.9668,32.5498'
            })),
            chain('Kareem Pharmacies', new List<String>{
                'Kareem Pharmacies', 'Kareem Pharmacies Rehab City', 'Kareem Pharmacies New Cairo',
                'Kareem Pharmacies Sheikh Zayed', 'Kareem Pharmacies Banha', 'Kareem Pharmacies Minya',
                'Kareem Pharmacies Assiut'
            }, egyptGeoList(new List<String>{
                'Rehab City,Cairo,Cairo,11841,30.0600,31.4900',
                'Rehab City,Cairo,Cairo,11841,30.0600,31.4900',
                'Fifth Settlement,New Cairo,Cairo,11835,30.0300,31.4700',
                'Sheikh Zayed City,Giza,Giza,12588,30.0280,30.9780',
                'Banha,Banha,Qalyubia,13511,30.4600,31.1800',
                'Minya,Minya,Minya,61511,28.1099,30.7503',
                'Assiut,Assiut,Assiut,71511,27.1783,31.1859'
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

    private static List<GeoPoint> egyptGeoList(List<String> encoded) {
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
            points.add(geo);
        }
        return points;
    }

    private static List<GeoPoint> getHcpGeoPoints() {
        return egyptGeoList(new List<String>{
            'Kasr Al Ainy St,Cairo,Cairo,11562,30.0287,31.2310',
            'Ramses St,Abbassia,Cairo,11566,30.0697,31.2800',
            'Corniche El Nile,Dokki,Giza,12613,30.0380,31.2120',
            'Cleopatra Hospital,Heliopolis,Cairo,11341,30.0876,31.3249',
            'Road 9,Maadi,Cairo,11431,29.9602,31.2569',
            '26th July St,Zamalek,Cairo,11211,30.0626,31.2197',
            'Abbas El Akkad St,Nasr City,Cairo,11765,30.0511,31.3656',
            'Stanley,Alexandria,Alexandria,21599,31.2396,29.9602',
            'Gomhoria St,Mansoura,Dakahlia,35511,31.0409,31.3785',
            'El Galaa St,Tanta,Gharbia,31511,30.7865,31.0004',
            'Sekket El Gdida,New Cairo,Cairo,11835,30.0300,31.4700',
            'Sheikh Zayed City,Giza,Giza,12588,30.0280,30.9780'
        });
    }

    private static List<HcpEntry> buildHcpDefinitions() {
        List<HcpEntry> defs = new List<HcpEntry>();
        addHcp(defs, 'Dr.', 'Magdi', 'Yacoub', 'magdi.yacoub');
        addHcp(defs, 'Dr.', 'Mohamed', 'Ghoneim', 'mohamed.ghoneim');
        addHcp(defs, 'Dr.', 'Ahmed', 'Shafik', 'ahmed.shafik');
        addHcp(defs, 'Dr.', 'Nadia', 'El-Abd', 'nadia.elabd');
        addHcp(defs, 'Dr.', 'Hossam', 'Mowafi', 'hossam.mowafi');
        addHcp(defs, 'Dr.', 'Sherif', 'Fouad', 'sherif.fouad');
        addHcp(defs, 'Dr.', 'Amr', 'Hassan', 'amr.hassan');
        addHcp(defs, 'Dr.', 'Heba', 'El-Sayed', 'heba.elsayed');
        addHcp(defs, 'Dr.', 'Yasmine', 'Farouk', 'yasmine.farouk');
        addHcp(defs, 'Dr.', 'Tarek', 'Nasser', 'tarek.nasser');
        addHcp(defs, 'Dr.', 'Rania', 'Mansour', 'rania.mansour');
        addHcp(defs, 'Dr.', 'Khaled', 'Saad', 'khaled.saad');
        addHcp(defs, 'Dr.', 'Dina', 'Khalil', 'dina.khalil');
        addHcp(defs, 'Dr.', 'Omar', 'Fahmy', 'omar.fahmy');
        addHcp(defs, 'Dr.', 'Salma', 'Rizk', 'salma.rizk');
        addHcp(defs, 'Dr.', 'Mahmoud', 'Bekheet', 'mahmoud.bekheet');
        addHcp(defs, 'Dr.', 'Fatma', 'Awad', 'fatma.awad');
        addHcp(defs, 'Dr.', 'Youssef', 'Hamza', 'youssef.hamza');
        addHcp(defs, 'Dr.', 'Nour', 'Ibrahim', 'nour.ibrahim');
        addHcp(defs, 'Dr.', 'Hana', 'Ali', 'hana.ali');

        List<String> firstNames = new List<String>{
            'Mohamed', 'Ahmed', 'Mahmoud', 'Youssef', 'Omar', 'Hassan', 'Ibrahim', 'Karim',
            'Tarek', 'Khaled', 'Fatma', 'Nour', 'Heba', 'Salma', 'Dina', 'Amira', 'Rania',
            'Nadia', 'Yasmine', 'Mona', 'Hana', 'Layla', 'Reem', 'Samar', 'Ghada'
        };
        List<String> lastNames = new List<String>{
            'Hassan', 'Ibrahim', 'Mohamed', 'Ali', 'El-Sayed', 'Abdel Rahman', 'Nasser',
            'Mansour', 'Saad', 'Khalil', 'Fahmy', 'Rizk', 'Bekheet', 'Awad', 'Farouk',
            'Hamza', 'Ghoneim', 'Shafik', 'Mowafi', 'Fouad'
        };
        while (defs.size() < 120) {
            Integer idx = defs.size();
            HcpEntry def = new HcpEntry();
            def.salutation = 'Dr.';
            def.firstName = firstNames[Math.mod(idx, firstNames.size())];
            def.lastName = lastNames[Math.mod(idx, lastNames.size())];
            def.emailPrefix = def.firstName.toLowerCase() + '.' + def.lastName.toLowerCase().replace(' ', '');
            defs.add(def);
        }
        return defs;
    }

    private static void addHcp(
        List<HcpEntry> defs,
        String salutation,
        String firstName,
        String lastName,
        String emailPrefix
    ) {
        HcpEntry def = new HcpEntry();
        def.salutation = salutation;
        def.firstName = firstName;
        def.lastName = lastName;
        def.emailPrefix = emailPrefix;
        defs.add(def);
    }

    private static String padIndex(Integer value) {
        String raw = String.valueOf(value);
        while (raw.length() < 2) {
            raw = '0' + raw;
        }
        return raw;
    }
}
