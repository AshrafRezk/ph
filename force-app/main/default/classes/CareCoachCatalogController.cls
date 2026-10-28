/**
 * Products and knowledge (care scripts) for Care Coach Co-pilot.
 */
public with sharing class CareCoachCatalogController {
    public class ProductCard {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String code;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String description;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Integer totalPatients = 0;
        @AuraEnabled public Integer ongoing = 0;
        @AuraEnabled public Integer pending = 0;
        @AuraEnabled public Integer dropped = 0;
        @AuraEnabled public Integer newThisMonth = 0;
        @AuraEnabled public Integer ordersThisMonth = 0;
        @AuraEnabled public Integer unitsThisMonth = 0;
        @AuraEnabled public Integer scripts = 0;
    }

    public class TherapyGroup {
        @AuraEnabled public String therapyArea;
        @AuraEnabled public List<ProductCard> products = new List<ProductCard>();
    }

    public class ScriptRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String scriptNumber;
        @AuraEnabled public String title;
        @AuraEnabled public String question;
        @AuraEnabled public String answer;
        @AuraEnabled public String summary;
        @AuraEnabled public Id productId;
        @AuraEnabled public String productName;
        @AuraEnabled public String therapyArea;
        @AuraEnabled public String category;
        @AuraEnabled public String language;
        @AuraEnabled public String validationStatus;
        @AuraEnabled public String publicationStatus;
        @AuraEnabled public Date publishedDate;
        @AuraEnabled public Integer helpful;
        @AuraEnabled public Datetime lastModified;
    }

    @AuraEnabled
    public static List<TherapyGroup> getProducts(String scope) {
        String resolved = CareCoachAccess.resolveScope(scope);
        Id me = UserInfo.getUserId();
        Boolean mine = resolved == CareCoachAccess.SCOPE_MINE;

        Map<Id, ProductCard> cards = new Map<Id, ProductCard>();
        Map<String, TherapyGroup> groups = new Map<String, TherapyGroup>();
        List<TherapyGroup> ordered = new List<TherapyGroup>();
        for (Product2 p : CareCoachPatientService.pspProducts()) {
            ProductCard c = new ProductCard();
            c.id = p.Id;
            c.name = p.Name;
            c.code = p.ProductCode;
            c.therapyArea = String.isBlank(p.Therapy_Area__c) ? 'Other' : p.Therapy_Area__c;
            c.description = p.Description;
            c.imageUrl = p.Product_Image_URL__c;
            cards.put(p.Id, c);
            TherapyGroup g = groups.get(c.therapyArea);
            if (g == null) {
                g = new TherapyGroup();
                g.therapyArea = c.therapyArea;
                groups.put(c.therapyArea, g);
                ordered.add(g);
            }
            g.products.add(c);
        }
        if (cards.isEmpty()) {
            return ordered;
        }
        Set<Id> ids = cards.keySet();

        List<AggregateResult> statusRows = mine
            ? [SELECT Primary_Product__c p, Status__c s, COUNT(Id) c FROM Patient__c WHERE Primary_Product__c IN :ids AND Care_Coach__c = :me WITH USER_MODE GROUP BY Primary_Product__c, Status__c]
            : [SELECT Primary_Product__c p, Status__c s, COUNT(Id) c FROM Patient__c WHERE Primary_Product__c IN :ids WITH USER_MODE GROUP BY Primary_Product__c, Status__c];
        for (AggregateResult ar : statusRows) {
            ProductCard c = cards.get((Id) ar.get('p'));
            Integer n = (Integer) ar.get('c');
            String s = (String) ar.get('s');
            c.totalPatients += n;
            if (s == 'Ongoing') c.ongoing += n;
            else if (s == 'Pending') c.pending += n;
            else if (s != null && s.startsWith('Dropped')) c.dropped += n;
        }
        List<AggregateResult> newRows = mine
            ? [SELECT Primary_Product__c p, COUNT(Id) c FROM Patient__c WHERE Primary_Product__c IN :ids AND Care_Coach__c = :me AND Enrollment_Date__c = THIS_MONTH WITH USER_MODE GROUP BY Primary_Product__c]
            : [SELECT Primary_Product__c p, COUNT(Id) c FROM Patient__c WHERE Primary_Product__c IN :ids AND Enrollment_Date__c = THIS_MONTH WITH USER_MODE GROUP BY Primary_Product__c];
        for (AggregateResult ar : newRows) {
            cards.get((Id) ar.get('p')).newThisMonth = (Integer) ar.get('c');
        }
        List<AggregateResult> orderRows = mine
            ? [SELECT Product__c p, COUNT(Id) c, SUM(Quantity__c) q FROM Patient_Order__c WHERE Product__c IN :ids AND Patient__r.Care_Coach__c = :me AND Order_Date__c = THIS_MONTH WITH USER_MODE GROUP BY Product__c]
            : [SELECT Product__c p, COUNT(Id) c, SUM(Quantity__c) q FROM Patient_Order__c WHERE Product__c IN :ids AND Order_Date__c = THIS_MONTH WITH USER_MODE GROUP BY Product__c];
        for (AggregateResult ar : orderRows) {
            ProductCard c = cards.get((Id) ar.get('p'));
            c.ordersThisMonth = (Integer) ar.get('c');
            Decimal q = (Decimal) ar.get('q');
            c.unitsThisMonth = q == null ? 0 : q.intValue();
        }
        for (AggregateResult ar : [
            SELECT Product__c p, COUNT(Id) c FROM Care_Script__c WHERE Product__c IN :ids WITH USER_MODE GROUP BY Product__c
        ]) {
            cards.get((Id) ar.get('p')).scripts = (Integer) ar.get('c');
        }
        return ordered;
    }

    @AuraEnabled
    public static List<ScriptRow> getScripts(String search, String productId, String category, Boolean publishedOnly) {
        Map<String, Object> binds = new Map<String, Object>();
        List<String> clauses = new List<String>();
        if (String.isNotBlank(search)) {
            binds.put('term', '%' + search.trim() + '%');
            clauses.add('(Title__c LIKE :term OR Question__c LIKE :term OR Summary__c LIKE :term OR Name LIKE :term)');
        }
        if (String.isNotBlank(productId)) {
            binds.put('productId', productId);
            clauses.add('Product__c = :productId');
        }
        if (String.isNotBlank(category)) {
            binds.put('category', category);
            clauses.add('Category__c = :category');
        }
        if (publishedOnly == true) {
            clauses.add('Publication_Status__c = \'Published\'');
        }
        String sql =
            'SELECT Id, Name, Title__c, Question__c, Summary__c, Product__c, Product__r.Name, Therapy_Area__c, Category__c,' +
            ' Language__c, Validation_Status__c, Publication_Status__c, Published_Date__c, Helpful_Count__c, LastModifiedDate' +
            ' FROM Care_Script__c' + (clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ')) +
            ' ORDER BY Name LIMIT 200';
        List<ScriptRow> out = new List<ScriptRow>();
        for (Care_Script__c s : (List<Care_Script__c>) Database.queryWithBinds(sql, binds, AccessLevel.USER_MODE)) {
            out.add(toScript(s, false));
        }
        return out;
    }

    @AuraEnabled
    public static ScriptRow getScript(Id scriptId) {
        Care_Script__c s = [
            SELECT Id, Name, Title__c, Question__c, Answer__c, Summary__c, Product__c, Product__r.Name, Therapy_Area__c,
                Category__c, Language__c, Validation_Status__c, Publication_Status__c, Published_Date__c,
                Helpful_Count__c, LastModifiedDate
            FROM Care_Script__c
            WHERE Id = :scriptId
            WITH USER_MODE
            LIMIT 1
        ];
        return toScript(s, true);
    }

    @AuraEnabled
    public static Integer markHelpful(Id scriptId) {
        CareCoachAccess.assertCanEdit();
        Care_Script__c s = [SELECT Id, Helpful_Count__c FROM Care_Script__c WHERE Id = :scriptId WITH USER_MODE LIMIT 1];
        s.Helpful_Count__c = (s.Helpful_Count__c == null ? 0 : s.Helpful_Count__c) + 1;
        new SystemContext().save(s);
        return s.Helpful_Count__c.intValue();
    }

    /** Scripts are org-wide read-only for coaches; only the vote counter is written, in system context. */
    private without sharing class SystemContext {
        void save(Care_Script__c s) {
            update new Care_Script__c(Id = s.Id, Helpful_Count__c = s.Helpful_Count__c);
        }
    }

    private static ScriptRow toScript(Care_Script__c s, Boolean withAnswer) {
        ScriptRow r = new ScriptRow();
        r.id = s.Id;
        r.scriptNumber = s.Name;
        r.title = s.Title__c;
        r.question = s.Question__c;
        r.summary = s.Summary__c;
        r.productId = s.Product__c;
        r.productName = s.Product__r?.Name;
        r.therapyArea = s.Therapy_Area__c;
        r.category = s.Category__c;
        r.language = s.Language__c;
        r.validationStatus = s.Validation_Status__c;
        r.publicationStatus = s.Publication_Status__c;
        r.publishedDate = s.Published_Date__c;
        r.helpful = s.Helpful_Count__c == null ? 0 : s.Helpful_Count__c.intValue();
        r.lastModified = s.LastModifiedDate;
        if (withAnswer) {
            r.answer = s.Answer__c;
        }
        return r;
    }
}