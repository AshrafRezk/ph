/**
 * Cognitive account lookup for field requests and orders.
 * Uses AccountCognitiveSearch, the bundled romanizer index, and grapheme
 * transliteration. Never calls Yamli or any other network transliteration API.
 */
public with sharing class FieldAccountSearch {
    public class Hit implements Comparable {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public Id visitId;
        @AuraEnabled public String visitLabel;
        @AuraEnabled public String reason;
        @AuraEnabled public String recordTypeLabel;
        @AuraEnabled public String recordTypeDeveloperName;
        @AuraEnabled public String iconName;
        @AuraEnabled public Integer score;

        public Integer compareTo(Object other) {
            Hit right = (Hit) other;
            Integer leftScore = score == null ? 0 : score;
            Integer rightScore = right.score == null ? 0 : right.score;
            if (leftScore != rightScore) {
                return rightScore - leftScore;
            }
            String leftName = accountName == null ? '' : accountName;
            String rightName = right.accountName == null ? '' : right.accountName;
            return leftName.compareTo(rightName);
        }
    }

    @AuraEnabled
    public static List<Hit> search(String term) {
        String needle = term == null ? '' : term.trim();
        if (needle.length() < 2) {
            return new List<Hit>();
        }
        List<String> needles = collectNeedles(needle, false);
        List<Hit> hits = rank(needle, needles, queryByNeedles(needles));
        if (!hits.isEmpty()) {
            return hits;
        }
        List<String> phonetic = collectNeedles(needle, true);
        return rank(needle, phonetic, queryByNeedles(phonetic));
    }

    public static String iconFor(String developerName) {
        if (String.isBlank(developerName)) {
            return 'standard:account';
        }
        String key = developerName.trim();
        if (
            key == 'PersonAccount' ||
            key == 'SDO_PersonAccounts' ||
            key == 'Medical_Professional_HCP'
        ) {
            return 'standard:person_account';
        }
        if (key == 'Pharmacy') {
            return 'standard:household';
        }
        if (key == 'Business_Contact') {
            return 'standard:contact';
        }
        if (key == 'Institution_HCO') {
            return 'standard:account';
        }
        return 'standard:account';
    }

    public static Hit fromAccount(
        Account account,
        Id visitId,
        String visitLabel,
        String reason
    ) {
        Hit hit = new Hit();
        if (account == null) {
            return hit;
        }
        hit.accountId = account.Id;
        hit.accountName = account.Name;
        hit.visitId = visitId;
        hit.visitLabel = visitLabel;
        hit.reason = reason;
        if (account.RecordType != null) {
            hit.recordTypeLabel = account.RecordType.Name;
            hit.recordTypeDeveloperName = account.RecordType.DeveloperName;
        }
        hit.iconName = iconFor(hit.recordTypeDeveloperName);
        return hit;
    }

    private static List<String> collectNeedles(String term, Boolean phoneticOnly) {
        List<String> tokens = AccountCognitiveSearch.tokenize(term);
        String stem = compoundStem(tokens);
        List<String> needles = new List<String>();
        Set<String> seen = new Set<String>();
        if (phoneticOnly == true) {
            addAll(needles, seen, AccountTransliteration.scriptVariants(term));
            if (String.isNotBlank(stem)) {
                addAll(needles, seen, AccountTransliteration.scriptVariants(stem));
            }
            for (String token : tokens) {
                if (token != null && token.length() >= 3) {
                    addAll(needles, seen, AccountTransliteration.scriptVariants(token));
                }
            }
            addOne(needles, seen, term);
            return cap(needles, 12);
        }
        if (String.isNotBlank(stem) && stem.length() >= 4) {
            addAll(needles, seen, AccountNameRomanizer.prefixVariants(stem, 4));
            addAll(needles, seen, AccountCognitiveSearch.searchNeedles(stem));
        } else {
            List<String> significant = new List<String>();
            for (String token : tokens) {
                if (token != null && AccountCognitiveSearch.foldName(token).length() >= 3) {
                    significant.add(token);
                }
            }
            if (significant.size() <= 1) {
                String token = significant.isEmpty() ? term : significant[0];
                addAll(needles, seen, AccountNameRomanizer.prefixVariants(token, 4));
                addAll(needles, seen, AccountCognitiveSearch.searchNeedles(token));
                if (AccountNameRomanizer.variants(token).isEmpty()) {
                    addAll(needles, seen, AccountTransliteration.scriptVariants(token));
                }
            } else {
                for (String token : significant) {
                    addAll(needles, seen, AccountCognitiveSearch.searchNeedles(token));
                }
            }
        }
        addOne(needles, seen, term);
        return cap(needles, 12);
    }

    private static String compoundStem(List<String> tokens) {
        if (tokens == null || tokens.size() < 2) {
            return null;
        }
        String first = AccountCognitiveSearch.foldCompact(tokens[0]);
        Boolean abdPrefix =
            first == 'abd' ||
            first == 'abdel' ||
            first == 'abdul' ||
            first == 'abdur' ||
            first == '\u0639\u0628\u062F' ||
            (first != null &&
            (first.startsWith('abdel') ||
            first.startsWith('abdul') ||
            first.startsWith('\u0639\u0628\u062F')));
        Boolean elPrefix = first == 'el' || first == 'al' || first == '\u0627\u0644';
        if (abdPrefix != true && elPrefix != true) {
            return null;
        }
        String joined = '';
        Integer take = Math.min(tokens.size(), 4);
        for (Integer i = 0; i < take; i++) {
            joined += AccountCognitiveSearch.foldCompact(tokens[i]);
        }
        return joined;
    }

    private static List<Account> queryByNeedles(List<String> needles) {
        List<String> ors = new List<String>();
        if (needles != null) {
            for (String needle : needles) {
                String literal = likeContains(needle);
                if (String.isNotBlank(literal)) {
                    ors.add('Name LIKE ' + literal);
                }
            }
        }
        if (ors.isEmpty()) {
            return new List<Account>();
        }
        String soql =
            'SELECT Id, Name, RecordType.Name, RecordType.DeveloperName FROM Account WHERE (' +
            String.join(ors, ' OR ') +
            ') ORDER BY Name LIMIT 40';
        return Database.query(soql, AccessLevel.USER_MODE);
    }

    private static List<Hit> rank(String term, List<String> needles, List<Account> rows) {
        List<Hit> hits = new List<Hit>();
        Set<Id> seen = new Set<Id>();
        if (rows == null) {
            return hits;
        }
        for (Account account : rows) {
            if (account == null || seen.contains(account.Id)) {
                continue;
            }
            seen.add(account.Id);
            Integer score = AccountCognitiveSearch.scoreName(term, account.Name);
            if (containsNeedle(account.Name, needles)) {
                score = Math.max(score, 84);
            }
            if (score < 40) {
                continue;
            }
            Hit hit = fromAccount(account, null, null, 'Search');
            hit.score = score;
            hits.add(hit);
        }
        hits.sort();
        if (hits.size() <= 12) {
            return hits;
        }
        List<Hit> limited = new List<Hit>();
        for (Integer i = 0; i < 12; i++) {
            limited.add(hits[i]);
        }
        return limited;
    }

    private static Boolean containsNeedle(String name, List<String> needles) {
        String folded = AccountCognitiveSearch.foldName(name);
        if (String.isBlank(folded) || needles == null) {
            return false;
        }
        for (String needle : needles) {
            String foldedNeedle = AccountCognitiveSearch.foldName(needle);
            if (String.isNotBlank(foldedNeedle) && foldedNeedle.length() >= 4 && folded.contains(foldedNeedle)) {
                return true;
            }
        }
        return false;
    }

    private static String likeContains(String raw) {
        if (String.isBlank(raw) || raw.trim().length() < 3) {
            return null;
        }
        String safe = raw.trim().replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_');
        return '\'%' + String.escapeSingleQuotes(safe) + '%\'';
    }

    private static void addOne(List<String> needles, Set<String> seen, String value) {
        if (String.isBlank(value)) {
            return;
        }
        String trimmed = value.trim();
        if (trimmed.length() < 3) {
            return;
        }
        String key = AccountCognitiveSearch.foldCompact(trimmed);
        if (seen.contains(key) || needles.size() >= 16) {
            return;
        }
        seen.add(key);
        needles.add(trimmed);
    }

    private static void addAll(List<String> needles, Set<String> seen, List<String> values) {
        if (values == null) {
            return;
        }
        for (String value : values) {
            addOne(needles, seen, value);
        }
    }

    private static List<String> cap(List<String> needles, Integer maxSize) {
        if (needles.size() <= maxSize) {
            return needles;
        }
        List<String> limited = new List<String>();
        for (Integer i = 0; i < maxSize; i++) {
            limited.add(needles[i]);
        }
        return limited;
    }
}
