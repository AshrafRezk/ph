/**
 * Re-matches unmapped distributor sellout clients (pharmacies in the distributor file) to Zeta pharmacy accounts.
 *
 * The original matcher only compared a client with other distributors' already-linked clients, so a distributor
 * such as IBNSINA, whose pharmacies were never linked by anyone else, stayed Unmatched. This service searches the
 * pharmacy master with the shared name engine (AccountCognitiveSearch), and uses the brick as the corroborating
 * signal:
 *
 *   - same brick + aligned name score >= threshold  -> Confirmed (BrickCode)
 *   - within proximity + name score >= 70           -> Confirmed when the blended score clears the threshold
 *   - anywhere else with name score >= 90           -> Suggested only, a person confirms it
 *
 * Only Unmatched and Suggested aliases without a pharmacy are touched. Confirmed and Rejected rows are left alone.
 */
public with sharing class DistributorSelloutRematchService {
    public static final Integer MAX_ALIASES_PER_RUN = 200;
    public static final Integer MAX_NAME_NEEDLES = 40;
    public static final Integer MIN_SUGGEST_SCORE = 90;
    public static final Integer MIN_BRICK_SCORE = 70;

    public class RematchResult {
        @AuraEnabled public Integer examined = 0;
        @AuraEnabled public Integer confirmed = 0;
        @AuraEnabled public Integer suggested = 0;
        @AuraEnabled public Integer unchanged = 0;
        @AuraEnabled public Boolean more = false;
        @AuraEnabled public String message;
        @AuraEnabled public String errors;
    }

    public class Candidate {
        public Id accountId;
        public String name;
        public Decimal latitude;
        public Decimal longitude;
    }

    @AuraEnabled
    public static RematchResult rematch(String distributorCode, Integer limitSize) {
        String code = String.isBlank(distributorCode) ? 'IBNSINA' : DistributorMatchingUtil.normalizeDistributorCode(distributorCode);
        List<String> codeVariants = DistributorMatchingUtil.distributorCodeVariants(code);
        Integer cap = limitSize == null || limitSize < 1 ? MAX_ALIASES_PER_RUN : Math.min(limitSize, MAX_ALIASES_PER_RUN);
        List<Distributor_Sellout_Alias__c> aliases = [
            SELECT
                Id,
                Distributor_Code__c,
                Distributor_Client_Name__c,
                Brick_Code__c,
                Latitude__c,
                Longitude__c,
                Pharmacy_Account__c,
                Status__c
            FROM Distributor_Sellout_Alias__c
            WHERE
                Distributor_Code__c IN :codeVariants
                AND Pharmacy_Account__c = NULL
                AND Status__c IN ('Unmatched', 'Suggested')
            WITH SYSTEM_MODE
            ORDER BY Id
            LIMIT :(cap + 1)
        ];
        RematchResult result = new RematchResult();
        if (aliases.size() > cap) {
            aliases.remove(aliases.size() - 1);
            result.more = true;
        }
        result.examined = aliases.size();
        if (aliases.isEmpty()) {
            result.message = 'Nothing to re-match for ' + code + '.';
            return result;
        }

        List<Distributor_Sellout_Alias__c> changed = matchAliases(aliases, result);
        if (!changed.isEmpty()) {
            List<Database.SaveResult> saves = Database.update(changed, false, AccessLevel.SYSTEM_MODE);
            Integer failed = 0;
            String firstError;
            for (Integer i = 0; i < saves.size(); i++) {
                if (!saves[i].isSuccess()) {
                    failed++;
                    if (firstError == null) {
                        firstError = saves[i].getErrors()[0].getMessage();
                    }
                    // A row that did not save is not a match.
                    if (changed[i].Status__c == 'Confirmed') {
                        result.confirmed--;
                    } else {
                        result.suggested--;
                    }
                }
            }
            if (failed > 0) {
                result.errors = failed + ' could not be saved: ' + firstError;
            }
        }
        result.unchanged = result.examined - result.confirmed - result.suggested;
        result.message =
            result.confirmed + ' confirmed, ' + result.suggested + ' suggested, ' + result.unchanged + ' left unmatched.' +
            (result.more ? ' Run again for the next batch.' : '') +
            (String.isBlank(result.errors) ? '' : ' ' + result.errors);
        return result;
    }

    /** Pure scoring step: mutates and returns only the aliases that got a (better) match. Public for tests. */
    public static List<Distributor_Sellout_Alias__c> matchAliases(
        List<Distributor_Sellout_Alias__c> aliases,
        RematchResult result
    ) {
        Set<String> brickCodes = new Set<String>();
        for (Distributor_Sellout_Alias__c a : aliases) {
            if (String.isNotBlank(a.Brick_Code__c)) {
                brickCodes.add(a.Brick_Code__c.trim());
            }
        }
        Map<String, List<Candidate>> byBrick = loadBrickCandidates(brickCodes);
        Map<Id, Candidate> broad = loadNameCandidates(aliases);
        Decimal threshold = DistributorMatchingUtil.autoConfirmThreshold();
        Decimal proximity = DistributorMatchingUtil.proximityMeters();

        List<Distributor_Sellout_Alias__c> changed = new List<Distributor_Sellout_Alias__c>();
        for (Distributor_Sellout_Alias__c alias : aliases) {
            String aliasName = cleanName(alias.Distributor_Client_Name__c);
            if (String.isBlank(aliasName)) {
                continue;
            }
            String brick = String.isBlank(alias.Brick_Code__c) ? null : alias.Brick_Code__c.trim();
            Set<Id> inBrick = new Set<Id>();
            Decimal bestScore = 0;
            Candidate bestCandidate;
            String bestMethod;

            if (brick != null && byBrick.containsKey(brick)) {
                for (Candidate c : byBrick.get(brick)) {
                    inBrick.add(c.accountId);
                    Integer name = AccountCognitiveSearch.scoreAlignedNames(aliasName, cleanName(c.name));
                    if (name >= MIN_BRICK_SCORE) {
                        Decimal blended = Math.min(100, name + 10);
                        if (blended > bestScore) {
                            bestScore = blended;
                            bestCandidate = c;
                            bestMethod = 'BrickCode';
                        }
                    }
                }
            }
            for (Candidate c : broad.values()) {
                if (inBrick.contains(c.accountId)) {
                    continue;
                }
                Integer name = AccountCognitiveSearch.scoreAlignedNames(aliasName, cleanName(c.name));
                if (name < MIN_BRICK_SCORE) {
                    continue;
                }
                Decimal score = 0;
                String method = 'FuzzyName';
                Boolean near = false;
                if (alias.Latitude__c != null && alias.Longitude__c != null && c.latitude != null && c.longitude != null) {
                    Decimal meters = DistributorMatchingUtil.haversineMeters(
                        alias.Latitude__c,
                        alias.Longitude__c,
                        c.latitude,
                        c.longitude
                    );
                    near = meters != null && meters <= proximity;
                }
                if (near) {
                    score = Math.min(100, 60 + (name * 0.4) + 10);
                    method = 'GeoProximity+Name';
                } else if (name >= MIN_SUGGEST_SCORE) {
                    // Name alone: cap below the auto-confirm line so a person reviews it.
                    score = Math.min(name, threshold - 1);
                }
                if (score > bestScore) {
                    bestScore = score;
                    bestCandidate = c;
                    bestMethod = method;
                }
            }

            if (bestCandidate == null || bestScore < 50) {
                continue;
            }
            Boolean confirm = bestScore >= threshold && bestMethod != 'FuzzyName';
            alias.Pharmacy_Account__c = bestCandidate.accountId;
            alias.Match_Confidence__c = bestScore;
            alias.Match_Method__c = bestMethod;
            alias.Status__c = confirm ? 'Confirmed' : 'Suggested';
            if (result != null) {
                if (confirm) {
                    result.confirmed++;
                } else {
                    result.suggested++;
                }
            }
            changed.add(alias);
        }
        return changed;
    }

    /** Drop pharmacy filler words so Arabic and English names compare on the real name tokens. */
    public static String cleanName(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        String s = DistributorMatchingUtil.normalizeName(raw);
        for (String filler : new List<String>{ 'صيدلية', 'صيدليه', 'صيدلة', 'د/', 'دكتور', 'الدكتور', 'PHARMACY', 'DRUGSTORE' }) {
            s = s.replace(filler, ' ');
        }
        return s.replaceAll('\\s+', ' ').trim();
    }

    private static Map<String, List<Candidate>> loadBrickCandidates(Set<String> brickCodes) {
        Map<String, List<Candidate>> out = new Map<String, List<Candidate>>();
        if (brickCodes.isEmpty()) {
            return out;
        }
        for (Brick_Pharmacy__c bp : [
            SELECT
                Brick__r.Brick_Code__c,
                Pharmacy_Account__c,
                Pharmacy_Account__r.Name,
                Pharmacy_Account__r.BillingLatitude,
                Pharmacy_Account__r.BillingLongitude
            FROM Brick_Pharmacy__c
            WHERE Is_Active__c = TRUE AND Brick__r.Brick_Code__c IN :brickCodes
            WITH SYSTEM_MODE
            LIMIT 20000
        ]) {
            String key = bp.Brick__r.Brick_Code__c == null ? null : bp.Brick__r.Brick_Code__c.trim();
            if (key == null || bp.Pharmacy_Account__c == null) {
                continue;
            }
            if (!out.containsKey(key)) {
                out.put(key, new List<Candidate>());
            }
            out.get(key).add(toCandidate(bp.Pharmacy_Account__r));
        }
        return out;
    }

    /** Pharmacy accounts whose name contains any dictionary-expanded needle of the aliases' leading name tokens. */
    private static Map<Id, Candidate> loadNameCandidates(List<Distributor_Sellout_Alias__c> aliases) {
        Set<String> needles = new Set<String>();
        for (Distributor_Sellout_Alias__c a : aliases) {
            List<String> tokens = AccountCognitiveSearch.tokenize(cleanName(a.Distributor_Client_Name__c));
            if (tokens.isEmpty()) {
                continue;
            }
            // The longest token is the most selective.
            String lead = tokens[0];
            for (String t : tokens) {
                if (t.length() > lead.length()) {
                    lead = t;
                }
            }
            for (String n : AccountCognitiveSearch.searchNeedles(lead)) {
                if (String.isNotBlank(n) && n.length() >= 3 && needles.size() < MAX_NAME_NEEDLES) {
                    needles.add(n);
                }
            }
        }
        Map<Id, Candidate> out = new Map<Id, Candidate>();
        if (needles.isEmpty()) {
            return out;
        }
        List<String> clauses = new List<String>();
        for (String n : needles) {
            clauses.add('Name LIKE \'%' + String.escapeSingleQuotes(n) + '%\'');
        }
        Id rt = pharmacyRecordTypeId();
        String soql =
            'SELECT Id, Name, BillingLatitude, BillingLongitude FROM Account WHERE (' +
            String.join(clauses, ' OR ') + ')' +
            (rt == null ? '' : ' AND RecordTypeId = \'' + rt + '\'') +
            ' LIMIT 2000';
        for (Account acc : Database.query(soql, AccessLevel.SYSTEM_MODE)) {
            out.put(acc.Id, toCandidate(acc));
        }
        return out;
    }

    private static Candidate toCandidate(Account acc) {
        Candidate c = new Candidate();
        c.accountId = acc.Id;
        c.name = acc.Name;
        c.latitude = acc.BillingLatitude;
        c.longitude = acc.BillingLongitude;
        return c;
    }

    private static Id pharmacyRecordTypeId() {
        for (Schema.RecordTypeInfo info : Schema.SObjectType.Account.getRecordTypeInfos()) {
            if (info.isAvailable() && info.getDeveloperName() == 'Pharmacy') {
                return info.getRecordTypeId();
            }
        }
        return null;
    }
}
