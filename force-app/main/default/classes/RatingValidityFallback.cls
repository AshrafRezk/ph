public with sharing class RatingValidityFallback {
    public static final String FALLBACK_MESSAGE =
        'We couldn\'t verify this rating online right now. Your ratings are still valid to save—review them against your local knowledge and recent visits.';

    public static RatingValidityTypes.RatingValidityResult build(
        RatingValidityTypes.ValidationContext context
    ) {
        RatingValidityTypes.RatingValidityResult result = new RatingValidityTypes.RatingValidityResult();
        List<String> reasons = new List<String>();
        Integer score = 70;

        Map<String, Object> territory = context.territoryRatings == null
            ? new Map<String, Object>()
            : context.territoryRatings;
        String potential = stringValue(territory.get('Potential__c'));
        String penetration = stringValue(territory.get('Penetration__c'));
        String matrix = stringValue(territory.get('Matrix_Rating__c'));
        String classification = stringValue(territory.get('Classification__c'));

        if (String.isBlank(potential) && String.isBlank(penetration)) {
            score -= 20;
            reasons.add('No territory potential or access ratings were provided to compare.');
        } else {
            reasons.add(
                'Territory ratings captured locally: potential ' +
                displayOrUnknown(potential) +
                ', access ' +
                displayOrUnknown(penetration) +
                '.'
            );
        }

        if (!String.isBlank(potential) && !String.isBlank(penetration) && String.isBlank(matrix)) {
            score -= 10;
            reasons.add('Matrix rating is not yet calculated from potential and access.');
        } else if (!String.isBlank(matrix)) {
            reasons.add('Matrix rating ' + matrix + ' is consistent with the entered potential and access.');
        }

        if (!String.isBlank(classification)) {
            reasons.add('Classification bucket is ' + classification + ' based on current matrix.');
        }

        if (ClmRatingLayoutService.VARIANT_HCO.equals(context.accountVariant)) {
            score += applyHcoChecks(territory, reasons);
        } else {
            score += applyHcpChecks(territory, reasons);
        }

        Integer productCount = context.productRatings == null ? 0 : context.productRatings.size();
        if (productCount > 0) {
            reasons.add(productCount + ' product rating set(s) were reviewed locally.');
        } else {
            score -= 5;
            reasons.add('No product-level ratings were entered for validation.');
        }

        reasons.add('Online public-profile verification was unavailable; score is an offline estimate.');

        result.validityScore = Math.max(0, Math.min(100, score));
        result.summary = 'Offline validity estimate based on rating completeness and internal consistency.';
        result.reasons = reasons;
        result.source = RatingValidityTypes.SOURCE_FALLBACK;
        result.usedFallback = true;
        result.fallbackMessage = FALLBACK_MESSAGE;
        return result;
    }

    private static Integer applyHcpChecks(Map<String, Object> territory, List<String> reasons) {
        Integer adjustment = 0;
        Boolean isKol = booleanValue(territory.get('Is_KOL__c'));
        String kolReason = stringValue(territory.get('KOL_In_What__c'));
        String potential = stringValue(territory.get('Potential__c'));

        if (isKol == true && 'C'.equalsIgnoreCase(potential)) {
            adjustment -= 15;
            reasons.add('KOL designation with low strategic priority may need reconciliation.');
        } else if (isKol == true) {
            reasons.add('KOL flag is set' + (String.isBlank(kolReason) ? '.' : ' as ' + kolReason + '.'));
        }

        if (isKol == false && !String.isBlank(kolReason)) {
            adjustment -= 10;
            reasons.add('KOL reason is populated but the KOL toggle is off.');
        }
        return adjustment;
    }

    private static Integer applyHcoChecks(Map<String, Object> territory, List<String> reasons) {
        Integer adjustment = 0;
        Boolean hasKols = booleanValue(territory.get('Has_KOLs__c'));
        String kolProfile = stringValue(territory.get('KOL_Profile__c'));
        String potential = stringValue(territory.get('Potential__c'));

        if (hasKols == true && 'C'.equalsIgnoreCase(potential)) {
            adjustment -= 15;
            reasons.add('Organization marked as having KOLs but with low strategic priority may need review.');
        } else if (hasKols == true) {
            reasons.add(
                'Organization KOL profile' +
                (String.isBlank(kolProfile) ? ' is indicated.' : ' is ' + kolProfile + '.')
            );
        }

        if (hasKols == false && !String.isBlank(kolProfile)) {
            adjustment -= 10;
            reasons.add('KOL profile is populated but Has KOLs is off.');
        }
        return adjustment;
    }

    private static String stringValue(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Boolean booleanValue(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String text = String.valueOf(value);
        if ('true'.equalsIgnoreCase(text)) {
            return true;
        }
        if ('false'.equalsIgnoreCase(text)) {
            return false;
        }
        return null;
    }

    private static String displayOrUnknown(String value) {
        return String.isBlank(value) ? 'not set' : value;
    }
}
