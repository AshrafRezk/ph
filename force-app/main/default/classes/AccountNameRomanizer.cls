/**
 * Attested Arabic and Latin spellings for cognitive name search.
 * Data is the UNICEF arabic-name-romanizer index (MIT), Egypt-weighted,
 * plus Arabic given-name spellings, bundled in NameRomanizerIndex.
 * Matching never calls Yamli, Almaany, or Google.
 * Account search, duplicate check, and new-account creation all read it
 * through AccountCognitiveSearch.
 */
public with sharing class AccountNameRomanizer {
  private static Map<String, List<String>> index;

  public static List<String> variants(String token) {
    if (String.isBlank(token)) {
      return new List<String>();
    }
    ensure();
    String folded = AccountCognitiveSearch.foldName(token);
    List<String> found = lookup(folded);
    if (found != null) {
      return found;
    }
    String compact = AccountCognitiveSearch.foldCompact(token);
    if (compact != folded) {
      found = lookup(compact);
    }
    return found == null ? new List<String>() : found;
  }

  /**
   * Typeahead families whose folded key starts with the query stem.
   * "abd elham" / abdelham reaches Abdelhamid and عبد الحميد without a network call.
   */
  public static List<String> prefixVariants(String rawPrefix, Integer maxFamilies) {
    ensure();
    String prefix = AccountCognitiveSearch.foldCompact(rawPrefix);
    if (String.isBlank(prefix) || prefix.length() < 4 || index.isEmpty()) {
      return new List<String>();
    }
    Integer familyCap = maxFamilies == null || maxFamilies < 1 ? 4 : maxFamilies;
    List<PrefixKey> matched = new List<PrefixKey>();
    for (String key : index.keySet()) {
      String compact = AccountCognitiveSearch.foldCompact(key);
      if (String.isBlank(compact) || compact.length() < 4) {
        continue;
      }
      Boolean hit =
        compact.startsWith(prefix) ||
        (prefix.startsWith(compact) && compact.length() + 1 >= prefix.length());
      if (!hit) {
        continue;
      }
      PrefixKey row = new PrefixKey();
      row.key = key;
      row.delta = Math.abs(compact.length() - prefix.length());
      matched.add(row);
    }
    matched.sort();
    List<String> needles = new List<String>();
    Set<String> seen = new Set<String>();
    Integer families = 0;
    for (PrefixKey row : matched) {
      if (families >= familyCap || needles.size() >= 12) {
        break;
      }
      families++;
      addNeedle(needles, seen, row.key);
      List<String> values = index.get(row.key);
      if (values == null) {
        continue;
      }
      Integer arabic = 0;
      Integer latin = 0;
      for (String value : values) {
        if (String.isBlank(value) || value.trim().length() < 3) {
          continue;
        }
        Boolean isArabic = AccountTransliteration.containsArabic(value);
        if (isArabic && arabic >= 2) {
          continue;
        }
        if (!isArabic && latin >= 2) {
          continue;
        }
        addNeedle(needles, seen, value);
        if (isArabic) {
          arabic++;
        } else {
          latin++;
        }
        if (needles.size() >= 12) {
          break;
        }
      }
    }
    return needles;
  }

  private class PrefixKey implements Comparable {
    public String key;
    public Integer delta;

    public Integer compareTo(Object other) {
      PrefixKey right = (PrefixKey) other;
      Integer leftDelta = delta == null ? 0 : delta;
      Integer rightDelta = right.delta == null ? 0 : right.delta;
      return leftDelta - rightDelta;
    }
  }

  private static void addNeedle(List<String> needles, Set<String> seen, String value) {
    if (String.isBlank(value) || needles.size() >= 12) {
      return;
    }
    String trimmed = value.trim();
    if (trimmed.length() < 3) {
      return;
    }
    String key = AccountCognitiveSearch.foldCompact(trimmed);
    if (String.isBlank(key) || seen.contains(key)) {
      return;
    }
    seen.add(key);
    needles.add(trimmed);
  }

  private static List<String> lookup(String key) {
    if (String.isBlank(key) || !index.containsKey(key)) {
      return null;
    }
    return index.get(key);
  }

  private static void ensure() {
    if (index != null) {
      return;
    }
    index = new Map<String, List<String>>();
    List<StaticResource> rows = [
      SELECT Body
      FROM StaticResource
      WHERE Name = 'NameRomanizerIndex'
      LIMIT 1
    ];
    if (rows.isEmpty() || rows[0].Body == null) {
      return;
    }
    Object parsed = JSON.deserializeUntyped(rows[0].Body.toString());
    Map<String, Object> raw = (Map<String, Object>) parsed;
    for (String key : raw.keySet()) {
      List<Object> items = (List<Object>) raw.get(key);
      List<String> values = new List<String>();
      if (items != null) {
        for (Object item : items) {
          if (item != null) {
            values.add(String.valueOf(item));
          }
        }
      }
      index.put(key, values);
    }
  }
}
