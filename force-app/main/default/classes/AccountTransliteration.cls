/**
 * General Arabic ? Latin grapheme transliteration for Egypt/MENA account search.
 * Handles pharmacy/HCO brands and unknown tokens � not just person given names.
 * Ain (?) may be written as 3, a/e at the start, or omitted (ezaby ? ????).
 */
public with sharing class AccountTransliteration {
  private static final String ALEF = '\u0627';
  private static final String AIN = '\u0639';
  private static final String AL = '\u0627\u0644';
  private static final String YA = '\u064A';
  private static final String ALEF_MAQSURA = '\u0649';
  private static final Integer MAX_VARIANTS = 24;

  public static Boolean containsArabic(String raw) {
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

  /** Compact form with ?? / el / al / il stripped so ezaby and ?????? share a stem. */
  public static String foldNoArticle(String raw) {
    return stripArticleCompact(compactAlnum(raw));
  }

  /**
   * Script-agnostic consonant key: ??????, ????, ezaby, El-Ezaby ? zby.
   * Ain is omitted because Egyptian Latin often drops it.
   */
  public static String phoneticKey(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String compact = foldNoArticle(raw);
    String latin = containsArabic(compact) ? arabicLettersToLatin(compact, '') : compact.toLowerCase();
    String out = '';
    for (Integer i = 0; i < latin.length(); i++) {
      Integer cp = latin.charAt(i);
      String ch = latin.substring(i, i + 1);
      if (ch == '3' || 'aeiou'.contains(ch)) {
        continue;
      }
      if ((cp >= 97 && cp <= 122) || containsArabic(ch)) {
        out += ch;
      }
    }
    return out;
  }

  public static List<String> latinToArabicVariants(String raw) {
    List<String> out = new List<String>();
    if (String.isBlank(raw) || containsArabic(raw)) {
      return out;
    }
    String stem = stripLatinArticle(normalizeLatin(raw));
    if (String.isBlank(stem) || stem.length() < 2) {
      return out;
    }
    String core = latinConsonantCore(stem);
    if (String.isBlank(core)) {
      return out;
    }
    Boolean startedWithVowel = isLatinVowel(stem.substring(0, 1)) || stem.startsWith('3');
    Boolean preferAin = startedWithVowel && !startsWithLatinH(stem);
    addUnique(out, core);
    if (!core.startsWith(AIN) && startedWithVowel) {
      addUnique(out, AIN + core);
      addUnique(out, ALEF + core);
    }
    if (stem.startsWith('3') && !core.startsWith(AIN)) {
      addUnique(out, AIN + core);
    }
    if (core.endsWith(YA)) {
      addUnique(out, core.substring(0, core.length() - 1) + ALEF_MAQSURA);
      if (core.startsWith(AIN)) {
        addUnique(out, core.substring(0, core.length() - 1) + ALEF_MAQSURA);
      }
    }
    List<String> withArticle = new List<String>();
    for (String stemAr : new List<String>(out)) {
      if (!stemAr.startsWith(AL)) {
        addUnique(withArticle, AL + stemAr);
      }
    }
    addAllUnique(out, withArticle);
    if (preferAin) {
      out = preferStarting(out, AIN);
    }
    return cap(out);
  }

  public static List<String> arabicToLatinVariants(String raw) {
    List<String> out = new List<String>();
    if (String.isBlank(raw) || !containsArabic(raw)) {
      return out;
    }
    String folded = foldArabicGlyphs(stripTashkeel(raw));
    String stem = stripArabicArticle(folded.replace(' ', '').replace('-', ''));
    if (String.isBlank(stem)) {
      return out;
    }
    addUnique(out, stem);
    if (!stem.startsWith(AL) && stem.length() >= 2) {
      addUnique(out, AL + stem);
    }
    List<String> stems = new List<String>();
    for (String ain : new List<String>{ 'e', 'a', '3', '', 'o' }) {
      String mapped = arabicLettersToLatin(stem, ain);
      if (String.isBlank(mapped) || mapped.length() < 2) {
        continue;
      }
      addUnique(stems, mapped);
      String voiced = insertABetweenHard(mapped);
      if (voiced != mapped) {
        addUnique(stems, voiced);
      }
    }
    for (String s : stems) {
      addUnique(out, s);
      addAllUnique(out, latinArticlePrefixes(s));
    }
    return cap(out);
  }

  /** Latin + Arabic search strings for one token, including el/al ? ??. */
  public static List<String> scriptVariants(String raw) {
    List<String> out = new List<String>();
    if (String.isBlank(raw)) {
      return out;
    }
    String token = raw.trim();
    addUnique(out, token);
    if (containsArabic(token)) {
      addAllUnique(out, arabicToLatinVariants(token));
      String stem = stripArabicArticle(foldArabicGlyphs(stripTashkeel(token)).replace(' ', ''));
      addUnique(out, stem);
      if (String.isNotBlank(stem) && !stem.startsWith(AL)) {
        addUnique(out, AL + stem);
      }
    } else {
      String latin = normalizeLatin(token);
      String stem = stripLatinArticle(latin);
      addUnique(out, latin);
      addUnique(out, stem);
      addAllUnique(out, latinArticlePrefixes(stem));
      addAllUnique(out, latinToArabicVariants(token));
    }
    return cap(out);
  }

  public static String preferredArabic(String foldedLatin) {
    List<String> vars = latinToArabicVariants(foldedLatin);
    Boolean preferAin =
      String.isNotBlank(foldedLatin) &&
      !containsArabic(foldedLatin) &&
      isLatinVowel(foldedLatin.substring(0, 1)) &&
      !startsWithLatinH(foldedLatin);
    String fallback = '';
    for (String v : vars) {
      if (!containsArabic(v) || v.startsWith(AL)) {
        continue;
      }
      if (preferAin && v.startsWith(AIN)) {
        return v;
      }
      if (!preferAin && v.startsWith(ALEF)) {
        return v;
      }
      if (String.isBlank(fallback)) {
        fallback = v;
      }
    }
    return fallback;
  }

  public static String preferredLatin(String foldedArabic) {
    List<String> vars = arabicToLatinVariants(foldedArabic);
    for (String v : vars) {
      if (String.isNotBlank(v) && !containsArabic(v) && !v.contains(' ') && !v.contains('-')) {
        return v;
      }
    }
    return vars.isEmpty() ? '' : vars[0];
  }

  public static Integer editDistance(String left, String right) {
    if (left == right) {
      return 0;
    }
    if (left == null || right == null) {
      return 99;
    }
    Integer n = left.length();
    Integer m = right.length();
    if (Math.abs(n - m) > 2 || n > 32 || m > 32) {
      return 99;
    }
    List<Integer> prev = new List<Integer>();
    List<Integer> cur = new List<Integer>();
    for (Integer j = 0; j <= m; j++) {
      prev.add(j);
      cur.add(0);
    }
    for (Integer i = 1; i <= n; i++) {
      cur.set(0, i);
      String ci = left.substring(i - 1, i);
      for (Integer j = 1; j <= m; j++) {
        Integer cost = ci == right.substring(j - 1, j) ? 0 : 1;
        Integer del = prev[j] + 1;
        Integer ins = cur[j - 1] + 1;
        Integer sub = prev[j - 1] + cost;
        cur.set(j, Math.min(Math.min(del, ins), sub));
      }
      List<Integer> swap = prev;
      prev = cur;
      cur = swap;
    }
    return prev[m];
  }

  public static Boolean phoneticMatch(String query, String candidate) {
    String qKey = phoneticKey(query);
    String cKey = phoneticKey(candidate);
    if (String.isBlank(qKey) || String.isBlank(cKey) || qKey.length() < 3) {
      return false;
    }
    if (cKey.contains(qKey) || qKey.contains(cKey)) {
      return true;
    }
    return qKey.length() >= 3 && cKey.length() >= 3 && editDistance(qKey, cKey) <= 1;
  }

  /**
   * Extra lookup keys for a Latin token the index does not store as written.
   * Arabizi digits become the usual letters (7amada → hamada, 5aled → khaled).
   * A doubled letter collapses (Kirollos → kirolos). A doubled form that still
   * starts with a vowel also drops that vowel (Eissa → isa).
   */
  public static List<String> phoneticAliases(String raw) {
    List<String> out = new List<String>();
    if (String.isBlank(raw) || containsArabic(raw)) {
      return out;
    }
    String folded = raw.trim().toLowerCase();
    String decoded = decodeArabizi(folded);
    String collapsed = collapseRepeatedLetters(decoded);
    addAlias(out, folded, decoded);
    addAlias(out, folded, collapsed);
    if (
      collapsed != decoded &&
      collapsed.length() >= 4 &&
      isLatinVowel(collapsed.substring(0, 1))
    ) {
      addAlias(out, folded, collapsed.substring(1));
    }
    return out;
  }

  private static void addAlias(List<String> out, String original, String alias) {
    if (String.isBlank(alias) || alias == original || alias.length() < 3) {
      return;
    }
    if (!out.contains(alias)) {
      out.add(alias);
    }
  }

  private static String decodeArabizi(String folded) {
    String out = '';
    Integer i = 0;
    while (i < folded.length()) {
      String two = i + 1 < folded.length() ? folded.substring(i, i + 2) : '';
      String one = folded.substring(i, i + 1);
      if (two == '3\'' || two == '\'3') {
        out += 'gh';
        i += 2;
      } else if (two == '7\'') {
        out += 'kh';
        i += 2;
      } else if (two == '6\'') {
        out += 'z';
        i += 2;
      } else if (two == '9\'') {
        out += 'd';
        i += 2;
      } else if (one == '5') {
        out += 'kh';
        i += 1;
      } else if (one == '7') {
        out += 'h';
        i += 1;
      } else if (one == '6') {
        out += 't';
        i += 1;
      } else if (one == '8') {
        out += 'q';
        i += 1;
      } else if (one == '9') {
        out += 's';
        i += 1;
      } else if (one == '2' || one == '3') {
        i += 1;
      } else {
        out += one;
        i += 1;
      }
    }
    return out;
  }

  private static String collapseRepeatedLetters(String folded) {
    String out = '';
    String prev = '';
    for (Integer i = 0; i < folded.length(); i++) {
      String ch = folded.substring(i, i + 1);
      if (ch == prev) {
        continue;
      }
      out += ch;
      prev = ch;
    }
    return out;
  }

  private static String latinConsonantCore(String stem) {
    String out = '';
    Integer i = 0;
    while (i < stem.length()) {
      String two = i + 1 < stem.length() ? stem.substring(i, i + 2) : '';
      String one = stem.substring(i, i + 1);
      Boolean atStart = out.length() == 0;
      if (one == '3' || one == '\'') {
        out += AIN;
        i += 1;
      } else if (two == 'kh') {
        out += '\u062E';
        i += 2;
      } else if (two == 'sh' || two == 'ch') {
        out += '\u0634';
        i += 2;
      } else if (two == 'gh') {
        out += '\u063A';
        i += 2;
      } else if (two == 'th') {
        out += '\u062B';
        i += 2;
      } else if (two == 'dh') {
        out += '\u0630';
        i += 2;
      } else if (two == 'ph') {
        out += '\u0641';
        i += 2;
      } else if (two == 'aa') {
        out += ALEF;
        i += 2;
      } else if (two == 'ee' || two == 'ii' || two == 'ie') {
        out += YA;
        i += 2;
      } else if (two == 'oo' || two == 'uu' || two == 'ou') {
        out += '\u0648';
        i += 2;
      } else if (isLatinVowel(one)) {
        Boolean isLast = i == stem.length() - 1;
        if (isLast && (one == 'i' || one == 'e') && out.length() > 0) {
          out += YA;
        } else if (isLast && (one == 'a' || one == 'o' || one == 'u') && out.length() > 0) {
          out += one == 'a' ? ALEF : '\u0648';
        }
        i += 1;
      } else {
        out += latinConsonantToArabic(one, atStart && startsWithLatinVowel(stem));
        if (i + 1 < stem.length() && stem.substring(i + 1, i + 2) == one) {
          i += 1;
        }
        i += 1;
      }
    }
    return out;
  }

  private static String latinConsonantToArabic(String one, Boolean afterInitialVowel) {
    if (one == 'b') {
      return '\u0628';
    }
    if (one == 't') {
      return '\u062A';
    }
    if (one == 'j' || one == 'g') {
      return '\u062C';
    }
    if (one == 'h') {
      return afterInitialVowel ? '\u062D' : '\u0647';
    }
    if (one == 'd') {
      return '\u062F';
    }
    if (one == 'r') {
      return '\u0631';
    }
    if (one == 'z') {
      return '\u0632';
    }
    if (one == 's') {
      return '\u0633';
    }
    if (one == 'f') {
      return '\u0641';
    }
    if (one == 'q') {
      return '\u0642';
    }
    if (one == 'k') {
      return '\u0643';
    }
    if (one == 'l') {
      return '\u0644';
    }
    if (one == 'm') {
      return '\u0645';
    }
    if (one == 'n') {
      return '\u0646';
    }
    if (one == 'w') {
      return '\u0648';
    }
    if (one == 'y') {
      return YA;
    }
    if (one == 'x') {
      return '\u0643\u0633';
    }
    return '';
  }

  private static String arabicLettersToLatin(String arabic, String ainReplacement) {
    String out = '';
    for (Integer i = 0; i < arabic.length(); i++) {
      String ch = arabic.substring(i, i + 1);
      if (ch == ALEF || ch == '\u0623' || ch == '\u0625' || ch == '\u0622') {
        out += i == 0 ? 'a' : 'a';
      } else if (ch == '\u0628') {
        out += 'b';
      } else if (ch == '\u062A') {
        out += 't';
      } else if (ch == '\u062B') {
        out += 'th';
      } else if (ch == '\u062C') {
        out += 'g';
      } else if (ch == '\u062D') {
        out += 'h';
      } else if (ch == '\u062E') {
        out += 'kh';
      } else if (ch == '\u062F') {
        out += 'd';
      } else if (ch == '\u0630') {
        out += 'dh';
      } else if (ch == '\u0631') {
        out += 'r';
      } else if (ch == '\u0632') {
        out += 'z';
      } else if (ch == '\u0633') {
        out += 's';
      } else if (ch == '\u0634') {
        out += 'sh';
      } else if (ch == '\u0635') {
        out += 's';
      } else if (ch == '\u0636') {
        out += 'd';
      } else if (ch == '\u0637') {
        out += 't';
      } else if (ch == '\u0638') {
        out += 'z';
      } else if (ch == AIN) {
        out += ainReplacement == null ? '' : ainReplacement;
      } else if (ch == '\u063A') {
        out += 'gh';
      } else if (ch == '\u0641') {
        out += 'f';
      } else if (ch == '\u0642') {
        out += 'q';
      } else if (ch == '\u0643') {
        out += 'k';
      } else if (ch == '\u0644') {
        out += 'l';
      } else if (ch == '\u0645') {
        out += 'm';
      } else if (ch == '\u0646') {
        out += 'n';
      } else if (ch == '\u0647' || ch == '\u0629') {
        out += 'h';
      } else if (ch == '\u0648') {
        out += 'w';
      } else if (ch == YA || ch == ALEF_MAQSURA) {
        out += 'y';
      } else if (ch == '\u0621') {
        out += '';
      }
    }
    return out;
  }

  private static List<String> latinArticlePrefixes(String stem) {
    List<String> out = new List<String>();
    if (String.isBlank(stem) || stem.length() < 2) {
      return out;
    }
    String titled = titleCaseLatin(stem);
    addUnique(out, 'el' + stem);
    addUnique(out, 'al' + stem);
    addUnique(out, 'el-' + stem);
    addUnique(out, 'al-' + stem);
    addUnique(out, 'el ' + stem);
    addUnique(out, 'al ' + stem);
    addUnique(out, 'El ' + titled);
    addUnique(out, 'Al ' + titled);
    addUnique(out, 'El-' + titled);
    addUnique(out, titled);
    return out;
  }

  private static String titleCaseLatin(String stem) {
    if (String.isBlank(stem)) {
      return stem;
    }
    if (stem.length() == 1) {
      return stem.toUpperCase();
    }
    return stem.substring(0, 1).toUpperCase() + stem.substring(1).toLowerCase();
  }

  private static String normalizeLatin(String raw) {
    String s = raw == null ? '' : raw.toLowerCase().trim();
    s = s.replace('\u0640', '');
    String cleaned = '';
    for (Integer i = 0; i < s.length(); i++) {
      Integer cp = s.charAt(i);
      String ch = s.substring(i, i + 1);
      if (cp >= 97 && cp <= 122) {
        cleaned += ch;
      } else if (cp >= 48 && cp <= 57) {
        cleaned += ch;
      } else if (ch == '\'' || ch == '`') {
        cleaned += '\'';
      } else {
        // hyphens, spaces, tatweel already dropped; keep nothing
      }
    }
    return cleaned;
  }

  private static String compactAlnum(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = foldArabicGlyphs(stripTashkeel(raw)).toLowerCase();
    String cleaned = '';
    for (Integer i = 0; i < s.length(); i++) {
      Integer cp = s.charAt(i);
      Boolean keep =
        (cp >= 48 && cp <= 57) ||
        (cp >= 97 && cp <= 122) ||
        (cp >= 1569 && cp <= 1610);
      if (keep) {
        cleaned += s.substring(i, i + 1);
      }
    }
    return cleaned;
  }

  private static String stripArticleCompact(String compact) {
    if (String.isBlank(compact)) {
      return '';
    }
    if (compact.startsWith(AL) && compact.length() > 3) {
      return compact.substring(2);
    }
    if (
      (compact.startsWith('el') || compact.startsWith('al') || compact.startsWith('il')) &&
      compact.length() >= 5
    ) {
      return compact.substring(2);
    }
    return compact;
  }

  private static String stripLatinArticle(String latin) {
    if (String.isBlank(latin)) {
      return '';
    }
    if (
      (latin.startsWith('el') || latin.startsWith('al') || latin.startsWith('il')) &&
      latin.length() >= 5
    ) {
      return latin.substring(2);
    }
    return latin;
  }

  private static String stripArabicArticle(String arabic) {
    if (String.isBlank(arabic)) {
      return '';
    }
    if (arabic.startsWith(AL) && arabic.length() > 3) {
      return arabic.substring(2);
    }
    return arabic;
  }

  private static String foldArabicGlyphs(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String s = raw;
    s = s.replace('\u0623', ALEF).replace('\u0625', ALEF).replace('\u0622', ALEF).replace('\u0671', ALEF);
    s = s.replace('\u0629', '\u0647').replace(ALEF_MAQSURA, YA).replace('\u0626', YA).replace('\u0624', '\u0648');
    s = s.replace('\u0621', '');
    s = s.replace('\u06A9', '\u0643').replace('\u06CC', YA);
    return s;
  }

  private static String stripTashkeel(String raw) {
    if (String.isBlank(raw)) {
      return '';
    }
    String out = '';
    for (Integer i = 0; i < raw.length(); i++) {
      Integer cp = raw.charAt(i);
      if ((cp >= 1611 && cp <= 1631) || cp == 1648 || (cp >= 1750 && cp <= 1773) || cp == 1600) {
        continue;
      }
      out += raw.substring(i, i + 1);
    }
    return out;
  }

  private static String insertABetweenHard(String s) {
    if (String.isBlank(s) || s.length() < 2) {
      return s;
    }
    String out = s.substring(0, 1);
    for (Integer i = 0; i < s.length() - 1; i++) {
      String cur = s.substring(i, i + 1);
      String nxt = s.substring(i + 1, i + 2);
      if (isHardLatin(cur) && isHardLatin(nxt)) {
        out += 'a';
      }
      out += nxt;
    }
    return out;
  }

  private static Boolean isHardLatin(String ch) {
    return String.isNotBlank(ch) && 'bcdfghjklmnpqrstvxz'.contains(ch);
  }

  private static Boolean isLatinVowel(String ch) {
    return String.isNotBlank(ch) && 'aeiou'.contains(ch);
  }

  private static Boolean startsWithLatinVowel(String s) {
    return String.isNotBlank(s) && isLatinVowel(s.substring(0, 1));
  }

  private static Boolean startsWithLatinH(String s) {
    String n = normalizeLatin(s);
    n = stripLatinArticle(n);
    return n.length() >= 2 && isLatinVowel(n.substring(0, 1)) && n.substring(1, 2) == 'h';
  }

  private static List<String> preferStarting(List<String> variants, String prefix) {
    List<String> preferred = new List<String>();
    List<String> rest = new List<String>();
    for (String v : variants) {
      if (v != null && v.startsWith(prefix)) {
        preferred.add(v);
      } else {
        rest.add(v);
      }
    }
    preferred.addAll(rest);
    return preferred;
  }

  private static List<String> cap(List<String> variants) {
    if (variants.size() <= MAX_VARIANTS) {
      return variants;
    }
    List<String> arabic = new List<String>();
    List<String> latin = new List<String>();
    for (String v : variants) {
      if (containsArabic(v)) {
        arabic.add(v);
      } else {
        latin.add(v);
      }
    }
    List<String> limited = new List<String>();
    for (String v : arabic) {
      if (limited.size() >= MAX_VARIANTS) {
        break;
      }
      addUnique(limited, v);
    }
    for (String v : latin) {
      if (limited.size() >= MAX_VARIANTS) {
        break;
      }
      addUnique(limited, v);
    }
    return limited;
  }

  private static void addUnique(List<String> target, String value) {
    if (String.isBlank(value)) {
      return;
    }
    String v = value.trim();
    if (String.isBlank(v) || target.contains(v)) {
      return;
    }
    target.add(v);
  }

  private static void addAllUnique(List<String> target, List<String> values) {
    if (values == null) {
      return;
    }
    for (String value : values) {
      addUnique(target, value);
    }
  }
}