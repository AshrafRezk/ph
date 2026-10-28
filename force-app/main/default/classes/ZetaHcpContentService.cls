/**
 * Read-only content for the Zeta app for HCPs on the /meet site: products, news, the HCP's own
 * invitations, open events and their requests. Runs without sharing because the site guest user
 * has no access to these records; every query filters to what an HCP may see.
 */
public without sharing class ZetaHcpContentService {
    static final String TZ = 'Africa/Cairo';
    static final Set<String> CLOSED_MEETING_STATUSES = new Set<String>{ 'Cancelled', 'Rejected', 'Closed' };
    static final Map<String, String> LINE_AREAS = new Map<String, String>{
        'DIAB' => 'Diabetes',
        'CVM' => 'Cardiology',
        'GIT' => 'Gastroenterology',
        'ORTHO' => 'Orthopedics',
        'PEDIA' => 'Pediatrics',
        'GYNA' => 'Women\'s health',
        'DERMA' => 'Dermatology',
        'NEURO' => 'Neurology',
        'NEUROSCIENCE' => 'Neurology',
        'CHC' => 'Consumer health',
        'URO' => 'Urology',
        'RESP' => 'Respiratory'
    };
    static final Set<String> CHILD_TYPES = new Set<String>{ 'Detail', 'Sample', 'Brand Reminder' };

    /** The HCP behind an invitation: their account (when the guest is a customer), name, phone and email. */
    public class Hcp {
        public Id accountId;
        public String name;
        public String phone;
        public String email;
        public String code;
    }

    public static Hcp hcpFor(Meeting_Invitation__c invitation) {
        Hcp hcp = new Hcp();
        if (invitation == null) {
            return hcp;
        }
        Meeting_Invitation__c row = [
            SELECT Guest_Name__c, Phone__c, Email__c, Code__c, Meeting_Member__r.Customer__c
            FROM Meeting_Invitation__c
            WHERE Id = :invitation.Id
        ];
        hcp.accountId = row.Meeting_Member__r == null ? null : row.Meeting_Member__r.Customer__c;
        hcp.name = row.Guest_Name__c;
        hcp.phone = row.Phone__c;
        hcp.email = row.Email__c;
        hcp.code = row.Code__c;
        return hcp;
    }

    public static List<Map<String, Object>> products() {
        return products(null);
    }

    /**
     * Brands shown in the HCP app, then each brand's detail products.
     * A brand is rated when the brand itself, or any of its details, has a rating on any territory.
     */
    public static List<Map<String, Object>> products(Id accountId) {
        Set<String> ratedKeys = ratedProductKeys(accountId);
        List<Product2> catalogue = [
            SELECT Id, Name, Description, Product_Image_URL__c, Therapy_Area__c, Sales_Line__c,
                Strength__c, Form__c, Product_Type__c
            FROM Product2
            WHERE IsActive = true AND Show_In_HCP_App__c = true
            ORDER BY Name
            LIMIT 300
        ];
        List<Product2> brands = new List<Product2>();
        for (Product2 row : catalogue) {
            if (!CHILD_TYPES.contains(row.Product_Type__c)) {
                brands.add(row);
            }
        }
        Map<Id, Product2> brandById = new Map<Id, Product2>(brands);
        List<Product2> details = brandById.isEmpty()
            ? new List<Product2>()
            : [
                SELECT Id, Name, Description, Product_Image_URL__c, Therapy_Area__c, Sales_Line__c,
                    Strength__c, Form__c, Parent_Product__c
                FROM Product2
                WHERE IsActive = true
                    AND Product_Type__c = 'Detail'
                    AND Parent_Product__c IN :brandById.keySet()
                ORDER BY Name
                LIMIT 2000
            ];
        Set<Id> ratedBrandIds = new Set<Id>();
        for (Product2 brand : brands) {
            if (isRated(ratedKeys, brand.Id)) {
                ratedBrandIds.add(brand.Id);
            }
        }
        for (Product2 detail : details) {
            if (detail.Parent_Product__c != null && isRated(ratedKeys, detail.Id)) {
                ratedBrandIds.add(detail.Parent_Product__c);
            }
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Product2 brand : brands) {
            out.add(productRow(
                brand,
                'brand',
                null,
                ratedBrandIds.contains(brand.Id),
                brand.Product_Image_URL__c,
                therapyArea(brand.Therapy_Area__c, brand.Sales_Line__c)
            ));
        }
        for (Product2 detail : details) {
            Product2 brand = brandById.get(detail.Parent_Product__c);
            String image = String.isNotBlank(detail.Product_Image_URL__c)
                ? detail.Product_Image_URL__c
                : (brand == null ? null : brand.Product_Image_URL__c);
            String area = String.isNotBlank(detail.Therapy_Area__c)
                ? detail.Therapy_Area__c
                : (brand == null
                    ? therapyArea(null, detail.Sales_Line__c)
                    : therapyArea(brand.Therapy_Area__c, brand.Sales_Line__c));
            out.add(productRow(detail, 'detail', detail.Parent_Product__c, isRated(ratedKeys, detail.Id), image, area));
        }
        return out;
    }

    static Map<String, Object> productRow(Product2 product, String kind, Id brandId, Boolean rated, String image, String area) {
        return new Map<String, Object>{
            'id' => product.Id,
            'name' => product.Name,
            'image' => image,
            'area' => area,
            'strength' => product.Strength__c,
            'form' => product.Form__c,
            'description' => product.Description,
            'kind' => kind,
            'brandId' => brandId,
            'rated' => rated
        };
    }

    static Set<String> ratedProductKeys(Id accountId) {
        Set<String> keys = new Set<String>();
        if (accountId == null) {
            return keys;
        }
        for (Account_Territory_Product_Fields__c row : [
            SELECT Product2_Id__c, Product_Matrix_Rating__c, Adoption__c, Loyalty__c,
                Rx_Per_Week__c, Potential__c, Penetration__c
            FROM Account_Territory_Product_Fields__c
            WHERE Account__c = :accountId AND Product2_Id__c != NULL
        ]) {
            if (!hasProductRating(row)) {
                continue;
            }
            String raw = row.Product2_Id__c.trim();
            keys.add(raw);
            if (raw.length() >= 15) {
                keys.add(raw.left(15));
            }
        }
        return keys;
    }

    @TestVisible
    static Boolean hasProductRating(Account_Territory_Product_Fields__c row) {
        return row != null && (
            String.isNotBlank(row.Product_Matrix_Rating__c)
            || String.isNotBlank(row.Adoption__c)
            || String.isNotBlank(row.Loyalty__c)
            || row.Rx_Per_Week__c != null
            || row.Potential__c != null
            || row.Penetration__c != null
        );
    }

    static Boolean isRated(Set<String> keys, Id productId) {
        if (productId == null || keys.isEmpty()) {
            return false;
        }
        String full = String.valueOf(productId);
        return keys.contains(full) || keys.contains(full.left(15));
    }

    @TestVisible
    static String therapyArea(String area, String salesLine) {
        if (String.isNotBlank(area)) {
            return area;
        }
        if (String.isBlank(salesLine)) {
            return 'Other';
        }
        String key = salesLine.toUpperCase().split('[^A-Z]')[0];
        return LINE_AREAS.containsKey(key) ? LINE_AREAS.get(key) : salesLine;
    }

    public static List<Map<String, Object>> news() {
        Date today = Date.today();
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Zeta_News__c n : [
            SELECT Id, Name, Summary__c, Body__c, Image_URL__c, Article_URL__c, Category__c, Therapy_Area__c, Publish_Date__c
            FROM Zeta_News__c
            WHERE Published__c = true
                AND (Publish_Date__c = null OR Publish_Date__c <= :today)
                AND (Expiry_Date__c = null OR Expiry_Date__c >= :today)
            ORDER BY Publish_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT 30
        ]) {
            out.add(new Map<String, Object>{
                'id' => n.Id,
                'title' => n.Name,
                'summary' => n.Summary__c,
                'body' => n.Body__c,
                'image' => n.Image_URL__c,
                'link' => n.Article_URL__c,
                'category' => n.Category__c,
                'area' => n.Therapy_Area__c,
                'date' => n.Publish_Date__c == null ? null : DateTime.newInstance(n.Publish_Date__c, Time.newInstance(12, 0, 0, 0)).format('d MMM yyyy')
            });
        }
        return out;
    }

    /** Upcoming invitations for the same HCP account, or the same mobile number for walk-in guests. */
    public static List<Map<String, Object>> myEvents(Hcp hcp, Id currentInvitationId) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (hcp == null || (hcp.accountId == null && String.isBlank(hcp.phone) && currentInvitationId == null)) {
            return out;
        }
        DateTime since = System.now().addHours(-6);
        Id accountId = hcp.accountId;
        String phone = String.isBlank(hcp.phone) ? '__none__' : hcp.phone;
        for (Meeting_Invitation__c i : [
            SELECT Id, Code__c, Status__c, Meeting__c, Meeting__r.Name, Meeting__r.Objectives__c, Meeting__r.Start_Date_Time__c,
                Meeting__r.Venue__c, Meeting__r.Status__c
            FROM Meeting_Invitation__c
            WHERE Active__c = true
                AND (Id = :currentInvitationId OR Phone__c = :phone OR (Meeting_Member__r.Customer__c != null AND Meeting_Member__r.Customer__c = :accountId))
                AND Meeting__r.Status__c NOT IN :CLOSED_MEETING_STATUSES
                AND (Meeting__r.Start_Date_Time__c = null OR Meeting__r.Start_Date_Time__c >= :since)
            ORDER BY Meeting__r.Start_Date_Time__c ASC NULLS LAST
            LIMIT 20
        ]) {
            out.add(new Map<String, Object>{
                'meetingId' => i.Meeting__c,
                'code' => i.Code__c,
                'title' => title(i.Meeting__r),
                'when' => whenText(i.Meeting__r.Start_Date_Time__c),
                'day' => dayParts(i.Meeting__r.Start_Date_Time__c),
                'venue' => i.Meeting__r.Venue__c,
                'status' => i.Status__c,
                'current' => i.Id == currentInvitationId
            });
        }
        return out;
    }

    public static List<Map<String, Object>> openEvents(List<Map<String, Object>> mine) {
        Set<Id> invited = new Set<Id>();
        for (Map<String, Object> row : mine) {
            invited.add((Id) row.get('meetingId'));
        }
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Meeting__c m : [
            SELECT Id, Name, Objectives__c, Start_Date_Time__c, Venue__c
            FROM Meeting__c
            WHERE Show_In_HCP_App__c = true
                AND Status__c NOT IN :CLOSED_MEETING_STATUSES
                AND Start_Date_Time__c >= :System.now()
                AND Id NOT IN :invited
            ORDER BY Start_Date_Time__c ASC
            LIMIT 20
        ]) {
            out.add(new Map<String, Object>{
                'id' => m.Id,
                'title' => title(m),
                'when' => whenText(m.Start_Date_Time__c),
                'day' => dayParts(m.Start_Date_Time__c),
                'venue' => m.Venue__c
            });
        }
        return out;
    }

    public static Boolean isOpenEvent(Id meetingId) {
        return [
            SELECT COUNT() FROM Meeting__c
            WHERE Id = :meetingId AND Show_In_HCP_App__c = true AND Status__c NOT IN :CLOSED_MEETING_STATUSES
        ] > 0;
    }

    /** Requests this HCP sent from the app, matched by their personal code or their account. */
    public static List<Map<String, Object>> myRequests(Hcp hcp) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        if (hcp == null || (String.isBlank(hcp.code) && hcp.accountId == null)) {
            return out;
        }
        String code = String.isBlank(hcp.code) ? '__none__' : hcp.code;
        Id accountId = hcp.accountId;
        for (Case c : [
            SELECT CaseNumber, Subject, Status, Request_Type__c, CreatedDate, Response_Text__c, IsClosed
            FROM Case
            WHERE Origin = :ZetaHcpRequestService.ORIGIN
                AND (HCP_App_Code__c = :code OR (Inquirer_Account__c != null AND Inquirer_Account__c = :accountId))
            ORDER BY CreatedDate DESC
            LIMIT 20
        ]) {
            out.add(new Map<String, Object>{
                'number' => c.CaseNumber,
                'type' => c.Request_Type__c,
                'subject' => c.Subject,
                'state' => requestState(c),
                'created' => c.CreatedDate.format('d MMM, h:mm a', TZ),
                'response' => c.Response_Text__c
            });
        }
        return out;
    }

    @TestVisible
    static String requestState(Case c) {
        if (String.isNotBlank(c.Response_Text__c) || c.IsClosed == true) {
            return 'Answered';
        }
        return c.Status == 'New' ? 'Submitted' : 'In progress';
    }

    public static String title(Meeting__c m) {
        return String.isNotBlank(m.Objectives__c) ? m.Objectives__c.left(160) : m.Name;
    }

    static String whenText(DateTime value) {
        return value == null ? null : value.format('EEE d MMM, h:mm a', TZ);
    }

    static Map<String, String> dayParts(DateTime value) {
        return value == null ? null : new Map<String, String>{ 'd' => value.format('d', TZ), 'm' => value.format('MMM', TZ) };
    }
}
