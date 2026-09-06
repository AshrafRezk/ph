/**
 * Shared name intelligence for Accounts tab search and New Account master-list search.
 * Combines AccountTransliteration (general Arabic ? Latin), AccountNameDictionary
 * (person names + pharmacy brands), Arabic orthography folding, and light phonetic matching.
 */
public with sharing class AccountCognitiveSearch {
  private static final Integer MAX_VARIANTS_PER_TOKEN = 32;
  private static final Integer MIN_TOKEN_LENGTH = 2;

  private static Map<String, List<String>> familyByFold;
  private static Boolean familiesReady = false;

  /**
   * Fold a name for comparison: tashkeel off, alef/hamza/taa-marbuta/yaa normalized, lowercased.
   * Ahmad-with-hamza and Ahmad-without-hamza collide on this fold.
   */
  public static String foldName(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = stripTashkeelAndTatweel(raw);
    s = foldArabicLetters(s);
    s = s.toLowerCase();
    String cleaned = '';
    for (Integer i = 0; i < s.length(); i++) {
      Integer cp = s.charAt(i);
      Boolean keep =
        (cp >= 48 && cp <= 57) ||
        (cp >= 97 && cp <= 122) ||
        (cp >= 1569 && cp <= 1610) ||
        cp == 32;
      cleaned += keep ? s.substring(i, i + 1) : ' ';
    }
    return cleaned.replaceAll('\\s+', ' ').trim();
  }

  /** Space/hyphen-insensitive fold used as a dictionary key (Abd El Rahman -> abdelrahman). */
  public static String foldCompact(String raw) {
    return foldName(raw).replace(' ', '').replace('-', '');
  }

  public static List<String> tokenize(String rawTerm) {
    List<String> tokens = new List<String>();
    if (String.isBlank(rawTerm)) {
      return tokens;
    }
    String normalized = rawTerm.replace('-', ' ').replace('_', ' ');
    for (String part : normalized.trim().split('\\s+')) {
      if (String.isNotBlank(part)) {
        tokens.add(part);
      }
    }
    return tokens;
  }

  /**
   * Expand one query token into Latin + Arabic search variants
   * (dictionary, orthography, spelling, transliteration).
   */
  public static List<String> expandToken(String rawToken) {
    List<String> variants = new List<String>();
    if (String.isBlank(rawToken)) {
      return variants;
    }
    String token = rawToken.trim();
    addUnique(variants, token);
    if (isNumericOrCode(token)) {
      addUnique(variants, token.toLowerCase());
      return capPreferringScripts(variants);
    }
    if (token.length() < MIN_TOKEN_LENGTH) {
      return capPreferringScripts(variants);
    }

    ensureFamilies();
    String folded = foldName(token);
    String compact = foldCompact(token);
    String noArticle = AccountTransliteration.foldNoArticle(token);
    addUnique(variants, folded);
    addAllUnique(variants, arabicOrthographyVariants(token));

    List<String> family = lookupFamily(folded, compact);
    if (family == null && String.isNotBlank(noArticle) && noArticle != compact) {
      family = lookupFamily(foldName(noArticle), noArticle);
    }
    if (family != null) {
      addAllUnique(variants, family);
    }

    addAllUnique(variants, AccountTransliteration.scriptVariants(token));
    if (String.isNotBlank(noArticle) && noArticle != compact) {
      addAllUnique(variants, AccountTransliteration.scriptVariants(noArticle));
    }

    if (containsArabic(token)) {
      addAllUnique(variants, arabicOrthographyVariants(folded));
      for (String latin : AccountTransliteration.arabicToLatinVariants(folded)) {
        if (String.isBlank(latin) || latin.length() < MIN_TOKEN_LENGTH) {
          continue;
        }
        List<String> latinFamily = lookupFamily(foldName(latin), foldCompact(latin));
        if (latinFamily != null) {
          addAllUnique(variants, latinFamily);
        }
      }
    } else {
      addAllUnique(variants, latinSpellingVariants(folded));
      addAllUnique(variants, abdSpacingVariants(token));
      for (String arabic : AccountTransliteration.latinToArabicVariants(folded)) {
        if (String.isBlank(arabic) || !containsArabic(arabic)) {
          continue;
        }
        addAllUnique(variants, arabicOrthographyVariants(arabic));
        List<String> arabicFamily = lookupFamily(foldName(arabic), foldCompact(arabic));
        if (arabicFamily != null) {
          addAllUnique(variants, arabicFamily);
        }
      }
    }
    return capPreferringScripts(variants);
  }

  /** Flatten expansion of every token, plus Abd/El compound joins. */
  public static List<String> expandQuery(String rawTerm) {
    List<String> all = new List<String>();
    List<String> tokens = tokenize(rawTerm);
    for (String token : tokens) {
      addAllUnique(all, expandToken(token));
    }
    String compound = joinCompound(tokens);
    if (String.isNotBlank(compound)) {
      addAllUnique(all, expandToken(compound));
      addAllUnique(all, expandToken(compound.replace(' ', '')));
    }
    return all;
  }

  public static Boolean tokenMatchesHaystack(String haystack, String foldedHaystack, String token) {
    if (String.isBlank(token)) {
      return true;
    }
    String lowerHay = haystack == null ? '' : haystack.toLowerCase();
    String foldedHay = foldedHaystack == null ? foldName(haystack) : foldedHaystack;
    String compactHay = foldCompact(haystack);
    for (String variant : expandToken(token)) {
      if (String.isBlank(variant)) {
        continue;
      }
      if (lowerHay.contains(variant.toLowerCase())) {
        return true;
      }
      String foldedVariant = foldName(variant);
      if (String.isNotBlank(foldedVariant) && foldedHay.contains(foldedVariant)) {
        return true;
      }
      String compactVariant = foldCompact(variant);
      if (String.isNotBlank(compactVariant) && compactHay.contains(compactVariant)) {
        return true;
      }
      String noArtVariant = AccountTransliteration.foldNoArticle(variant);
      String noArtHay = AccountTransliteration.foldNoArticle(haystack);
      if (String.isNotBlank(noArtVariant) && noArtVariant.length() >= 3 && noArtHay.contains(noArtVariant)) {
        return true;
      }
    }
    return AccountTransliteration.phoneticMatch(token, haystack);
  }

  /** 0-100 score for cognitive / Did-you-mean ranking. */
  public static Integer scoreName(String query, String candidate) {
    if (String.isBlank(query) || String.isBlank(candidate)) {
      return 0;
    }
    String qFold = foldName(query);
    String cFold = foldName(candidate);
    if (String.isBlank(qFold) || String.isBlank(cFold)) {
      return 0;
    }
    if (qFold == cFold || foldCompact(query) == foldCompact(candidate)) {
      return 100;
    }
    if (cFold.contains(qFold) || qFold.contains(cFold)) {
      Decimal shorter = Math.min(qFold.length(), cFold.length());
      Decimal longer = Math.max(qFold.length(), cFold.length());
      return Integer.valueOf(((shorter / longer) * 92).setScale(0));
    }

    Integer best = 0;
    for (String qt : tokenize(qFold)) {
      List<String> qVars = expandToken(qt);
      for (String ct : tokenize(cFold)) {
        if (qVars.contains(ct) || foldName(qt) == foldName(ct) || foldCompact(qt) == foldCompact(ct)) {
          best = Math.max(best, 88);
          continue;
        }
        for (String qv : qVars) {
          String fv = foldName(qv);
          if (ct.contains(fv) || fv.contains(ct)) {
            best = Math.max(best, 76);
          }
        }
        String qs = consonantSkeleton(qt);
        String cs = consonantSkeleton(ct);
        if (String.isNotBlank(qs) && qs.length() >= 3 && qs == cs) {
          best = Math.max(best, 80);
        }
        if (AccountTransliteration.phoneticMatch(qt, ct)) {
          best = Math.max(best, 84);
        }
      }
    }
    if (AccountTransliteration.phoneticMatch(query, candidate)) {
      best = Math.max(best, 84);
    }
    if (best == 0) {
      Decimal sim = DistributorMatchingUtil.nameSimilarity(query, candidate);
      best = sim == null ? 0 : Integer.valueOf(sim.setScale(0));
    }
    return best;
  }

  public static Boolean isNumericOrCode(String token) {
    if (String.isBlank(token)) {
      return false;
    }
    String trimmed = token.trim();
    if (trimmed.length() < 2) {
      return false;
    }
    Integer digits = 0;
    for (Integer i = 0; i < trimmed.length(); i++) {
      Integer cp = trimmed.charAt(i);
      if (cp >= 48 && cp <= 57) {
        digits++;
      }
    }
    return digits >= 2 && digits >= (trimmed.length() / 2);
  }

  /**
   * Compact variants for non-name fields (phone, specialty, city, brick, address).
   * Keeps SOQL OR clauses bounded — full name-family expansion stays on Name/First/Last.
   */
  public static List<String> expandTokenForFieldSearch(String rawToken) {
    List<String> variants = new List<String>();
    if (String.isBlank(rawToken)) {
      return variants;
    }
    String token = rawToken.trim();
    addUnique(variants, token);
    addUnique(variants, foldName(token));
    addUnique(variants, foldCompact(token));
    if (isNumericOrCode(token) || looksLikePhoneToken(token)) {
      addAllUnique(variants, phoneSearchVariants(token));
    }
    String specApi = MedicalSpecialtyPicklist.resolveApiValue(token);
    if (String.isNotBlank(specApi)) {
      addUnique(variants, specApi);
    }
    String specLabel = MedicalSpecialtyPicklist.getLabel(token);
    if (String.isNotBlank(specLabel)) {
      addUnique(variants, specLabel);
    }
    if (variants.size() <= 12) {
      return variants;
    }
    List<String> limited = new List<String>();
    for (Integer i = 0; i < 12; i++) {
      limited.add(variants[i]);
    }
    return limited;
  }

  private static Boolean looksLikePhoneToken(String token) {
    return AccountCreateQualityService.looksLikePhoneQuery(token);
  }

  private static List<String> phoneSearchVariants(String token) {
    List<String> out = new List<String>();
    addAllUnique(out, AccountCreateQualityService.egyptPhoneSearchQueries(token));
    String digits = AccountCreateQualityService.phoneDigits(token);
    if (String.isNotBlank(digits)) {
      addUnique(out, digits);
    }
    return out;
  }

  @TestVisible
  static String stripTashkeelAndTatweel(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String out = '';
    for (Integer i = 0; i < raw.length(); i++) {
      Integer cp = raw.charAt(i);
      if (isTashkeel(cp) || cp == 1600) {
        continue;
      }
      out += raw.substring(i, i + 1);
    }
    return out;
  }

  @TestVisible
  static List<String> arabicOrthographyVariants(String raw) {
    List<String> out = new List<String>();
    if (String.isBlank(raw) || !containsArabic(raw)) {
      return out;
    }
    String folded = foldArabicLetters(stripTashkeelAndTatweel(raw));
    addUnique(out, raw);
    addUnique(out, folded);
    addUnique(out, folded.replace('\u0627', '\u0623'));
    addUnique(out, folded.replace('\u0627', '\u0625'));
    addUnique(out, folded.replace('\u0647', '\u0629'));
    addUnique(out, folded.replace('\u064A', '\u0649'));
    if (folded.startsWith('\u0627') && folded.length() > 1) {
      addUnique(out, '\u0623' + folded.substring(1));
      addUnique(out, '\u0625' + folded.substring(1));
      addUnique(out, '\u0622' + folded.substring(1));
    }
    if (folded.endsWith('\u0647')) {
      addUnique(out, folded.substring(0, folded.length() - 1) + '\u0629');
    }
    if (folded.endsWith('\u0629')) {
      addUnique(out, folded.substring(0, folded.length() - 1) + '\u0647');
    }
    return out;
  }

  private static void ensureFamilies() {
    if (familiesReady == true) {
      return;
    }
    familyByFold = new Map<String, List<String>>();
    for (List<String> family : AccountNameDictionary.allGroups()) {
      List<String> expanded = new List<String>();
      for (String member : family) {
        addUnique(expanded, member);
        addAllUnique(expanded, arabicOrthographyVariants(member));
        addAllUnique(expanded, abdSpacingVariants(member));
      }
      for (String member : expanded) {
        String folded = foldName(member);
        String compact = foldCompact(member);
        String noArt = AccountTransliteration.foldNoArticle(member);
        if (String.isNotBlank(folded)) {
          familyByFold.put(folded, expanded);
        }
        if (String.isNotBlank(compact)) {
          familyByFold.put(compact, expanded);
        }
        if (String.isNotBlank(noArt)) {
          familyByFold.put(noArt, expanded);
        }
      }
    }
    familiesReady = true;
  }

  private static List<String> lookupFamily(String folded, String compact) {
    if (String.isNotBlank(folded) && familyByFold.containsKey(folded)) {
      return familyByFold.get(folded);
    }
    if (String.isNotBlank(compact) && familyByFold.containsKey(compact)) {
      return familyByFold.get(compact);
    }
    String noArt = AccountTransliteration.foldNoArticle(compact);
    if (String.isNotBlank(noArt) && familyByFold.containsKey(noArt)) {
      return familyByFold.get(noArt);
    }
    return null;
  }

  private static String joinCompound(List<String> tokens) {
    if (tokens == null || tokens.size() < 2) {
      return null;
    }
    String first = foldCompact(tokens[0]);
    Boolean abdPrefix =
      first == 'abd' ||
      first == 'abdel' ||
      first == 'abdul' ||
      first == 'abdur' ||
      first == '\u0639\u0628\u062F' ||
      first.startsWith('abdel') ||
      first.startsWith('abdul') ||
      first.startsWith('\u0639\u0628\u062F');
    Boolean elPrefix = first == 'el' || first == 'al' || first == '\u0627\u0644';
    if (abdPrefix != true && elPrefix != true) {
      return null;
    }
    Integer take = Math.min(tokens.size(), 4);
    List<String> parts = new List<String>();
    for (Integer i = 0; i < take; i++) {
      parts.add(tokens[i]);
    }
    return String.join(parts, ' ');
  }

  private static List<String> abdSpacingVariants(String raw) {
    List<String> out = new List<String>();
    if (String.isBlank(raw)) {
      return out;
    }
    String compact = foldCompact(raw);
    if (compact.startsWith('abdel') && compact.length() > 5) {
      addUnique(out, 'Abdel ' + compact.substring(5));
      addUnique(out, 'Abdul ' + compact.substring(5));
      addUnique(out, 'Abd El ' + compact.substring(5));
    }
    if (compact.startsWith('abdul') && compact.length() > 5) {
      addUnique(out, 'Abdel ' + compact.substring(5));
      addUnique(out, 'Abd El ' + compact.substring(5));
    }
    if (compact.startsWith('\u0639\u0628\u062F\u0627\u0644') && compact.length() > 5) {
      addUnique(out, '\u0639\u0628\u062F \u0627\u0644' + compact.substring(5));
    }
    if (
      compact.startsWith('\u0639\u0628\u062F') &&
      compact.length() > 3 &&
      !compact.startsWith('\u0639\u0628\u062F\u0627\u0644')
    ) {
      addUnique(out, '\u0639\u0628\u062F\u0627\u0644' + compact.substring(3));
      addUnique(out, 'Abdel' + compact.substring(3));
    }
    return out;
  }

  private static List<String> latinSpellingVariants(String folded) {
    List<String> out = new List<String>();
    if (String.isBlank(folded)) {
      return out;
    }
    addUnique(out, folded);
    addUnique(out, folded.replace('e', 'a'));
    addUnique(out, folded.replace('a', 'e'));
    addUnique(out, folded.replace('ou', 'u'));
    addUnique(out, folded.replace('oo', 'u'));
    addUnique(out, folded.replace('mm', 'm'));
    addUnique(out, folded.replace('nn', 'n'));
    addUnique(out, folded.replace('el ', ''));
    addUnique(out, folded.replace('el-', ''));
    addUnique(out, folded.replace('al-', ''));
    if (folded.startsWith('el') && folded.length() > 3) {
      addUnique(out, folded.substring(2));
    }
    if (folded.startsWith('al') && folded.length() > 3) {
      addUnique(out, folded.substring(2));
    }
    return out;
  }

  @TestVisible
  static String latinToArabic(String foldedLatin) {
    return AccountTransliteration.preferredArabic(foldedLatin);
  }

  @TestVisible
  static String arabicToLatin(String foldedArabic) {
    return AccountTransliteration.preferredLatin(foldedArabic);
  }

  private static String foldArabicLetters(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = raw;
    s = s.replace('\u0623', '\u0627').replace('\u0625', '\u0627').replace('\u0622', '\u0627').replace('\u0671', '\u0627');
    s = s.replace('\u0629', '\u0647').replace('\u0649', '\u064A').replace('\u0626', '\u064A').replace('\u0624', '\u0648');
    s = s.replace('\u0621', '');
    s = s.replace('\u06A9', '\u0643').replace('\u06CC', '\u064A').replace('\u06C0', '\u0647');
    return s;
  }

  private static Boolean isTashkeel(Integer cp) {
    return (cp >= 1611 && cp <= 1631) || cp == 1648 || (cp >= 1750 && cp <= 1773);
  }

  private static Boolean containsArabic(String raw) {
    if (String.isBlank(raw)) {
      return false;
    }
    for (Integer i = 0; i < raw.length(); i++) {
      Integer cp = raw.charAt(i);
      if (cp >= 1569 && cp <= 1791) {
        return true;
      }
    }
    return false;
  }

  private static String consonantSkeleton(String folded) {
    if (String.isBlank(folded)) {
      return '';
    }
    String latin = containsArabic(folded) ? arabicToLatin(folded) : folded.toLowerCase();
    String out = '';
    for (Integer i = 0; i < latin.length(); i++) {
      String ch = latin.substring(i, i + 1);
      if (!'aeiou '.contains(ch)) {
        out += ch;
      }
    }
    return out;
  }

  private static void addUnique(List<String> target, String value) {
    if (String.isBlank(value)) {
      return;
    }
    String v = value.trim();
    if (String.isBlank(v)) {
      return;
    }
    if (!target.contains(v)) {
      target.add(v);
    }
  }

  private static void addAllUnique(List<String> target, List<String> values) {
    if (values == null) {
      return;
    }
    for (String value : values) {
      addUnique(target, value);
    }
  }

  private static List<String> capPreferringScripts(List<String> variants) {
    if (variants.size() <= MAX_VARIANTS_PER_TOKEN) {
      return variants;
    }
    List<String> arabic = new List<String>();
    List<String> latin = new List<String>();
    for (Integer i = 0; i < variants.size(); i++) {
      if (i == 0) {
        continue;
      }
      String v = variants[i];
      if (containsArabic(v)) {
        arabic.add(v);
      } else {
        latin.add(v);
      }
    }
    List<String> limited = new List<String>{ variants[0] };
    for (String v : arabic) {
      if (limited.size() >= MAX_VARIANTS_PER_TOKEN) {
        break;
      }
      addUnique(limited, v);
    }
    for (String v : latin) {
      if (limited.size() >= MAX_VARIANTS_PER_TOKEN) {
        break;
      }
      addUnique(limited, v);
    }
    return limited;
  }
}
