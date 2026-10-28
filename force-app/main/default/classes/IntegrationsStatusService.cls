/**
 * Honest integration status for Admin → Integrations Management.
 * Does not invent Connected/Configured when no feed, credentials, or linked data exist.
 */
public with sharing class IntegrationsStatusService {
    public class IntegrationStatus {
        @AuraEnabled public String id;
        @AuraEnabled public String status;
        @AuraEnabled public String statusTone;
        @AuraEnabled public String metaLabel;
        @AuraEnabled public String metaValue;
        @AuraEnabled public String detail;
    }

    @TestVisible
    private static Set<String> namedCredentialOverride;
    @TestVisible
    private static Integer brickCountOverride;
    @TestVisible
    private static Integer pharmacyLinksOverride;
    @TestVisible
    private static Integer accountsWithBrickOverride;
    @TestVisible
    private static Integer selloutAliasOverride;

    @AuraEnabled(cacheable=true)
    public static List<IntegrationStatus> getStatuses() {
        Set<String> namedCreds = loadNamedCredentialNames();
        Integer imsBrickCount = brickCountOverride != null
            ? brickCountOverride
            : [SELECT COUNT() FROM Brick__c WHERE Data_Source__c = 'IQVIA IMS'];
        Integer pharmacyLinks = pharmacyLinksOverride != null
            ? pharmacyLinksOverride
            : [SELECT COUNT() FROM Brick_Pharmacy__c];
        Integer accountsWithBrick = accountsWithBrickOverride != null
            ? accountsWithBrickOverride
            : [SELECT COUNT() FROM Account WHERE Brick__c != null];
        Integer selloutAliases = selloutAliasOverride != null
            ? selloutAliasOverride
            : [SELECT COUNT() FROM Distributor_Sellout_Alias__c];

        List<IntegrationStatus> rows = new List<IntegrationStatus>();
        rows.add(imsStatus(imsBrickCount, pharmacyLinks, accountsWithBrick));
        rows.add(oneKeyStatus());
        rows.add(mapsStatus(namedCreds));
        rows.add(mendixStatus(namedCreds));
        rows.add(wholesalerStatus(selloutAliases));
        rows.add(planned('veeva-network'));
        rows.add(planned('outlook'));
        rows.add(planned('sap-erp'));
        return rows;
    }

    private static IntegrationStatus imsStatus(
        Integer brickCount,
        Integer pharmacyLinks,
        Integer accountsWithBrick
    ) {
        IntegrationStatus row = base('ims-health');
        Boolean hasLinkedData = pharmacyLinks > 0 || accountsWithBrick > 0;

        // Brick codes labeled IQVIA IMS (organogram) are not an IMS sell-out feed.
        if (hasLinkedData) {
            row.status = 'Partial';
            row.statusTone = 'configured';
            row.metaLabel = 'Data status';
            row.metaValue = 'Pharmacy links present — no IMS API';
            row.detail =
                brickCount +
                ' IMS bricks · ' +
                pharmacyLinks +
                ' pharmacy links · ' +
                accountsWithBrick +
                ' accounts with Brick__c. No live IMS connector.';
            return row;
        }

        if (brickCount > 0) {
            row.status = 'Not connected';
            row.statusTone = 'pending';
            row.metaLabel = 'Data status';
            row.metaValue = 'Catalog only — no IMS data linked';
            row.detail =
                brickCount +
                ' brick codes exist; ' +
                pharmacyLinks +
                ' pharmacy memberships; ' +
                accountsWithBrick +
                ' accounts with Brick__c. No IMS API / sell-out feed configured.';
            return row;
        }

        row.status = 'Not configured';
        row.statusTone = 'pending';
        row.metaLabel = 'Data status';
        row.metaValue = 'No IMS feed';
        row.detail = 'No IQVIA IMS brick catalog, pharmacy links, or API credentials.';
        return row;
    }

    private static IntegrationStatus oneKeyStatus() {
        IntegrationStatus row = base('onekey');
        row.status = 'Not configured';
        row.statusTone = 'pending';
        row.metaLabel = 'Data status';
        row.metaValue = 'No OneKey connector';
        row.detail =
            'OneKey identifiers, credentials, and enrichment jobs are not set up. Status must not show Configured until a connector exists.';
        return row;
    }

    private static IntegrationStatus mapsStatus(Set<String> namedCreds) {
        IntegrationStatus row = base('maps');
        Boolean google = namedCreds.contains('Google_Geocoding');
        Boolean osm = namedCreds.contains('OpenStreetMap_Nominatim');
        if (google || osm) {
            row.status = 'Connected';
            row.statusTone = 'connected';
            row.metaLabel = 'Credentials';
            row.metaValue = 'Present';
            List<String> parts = new List<String>();
            if (google) {
                parts.add('Google Places');
            }
            if (osm) {
                parts.add('OpenStreetMap');
            }
            row.detail = String.join(parts, ' · ') + ' named credentials present.';
            return row;
        }
        row.status = 'Not configured';
        row.statusTone = 'pending';
        row.metaLabel = 'Data status';
        row.metaValue = 'No map credentials';
        row.detail = 'Google_Geocoding / OpenStreetMap_Nominatim named credentials missing.';
        return row;
    }

    private static IntegrationStatus mendixStatus(Set<String> namedCreds) {
        IntegrationStatus row = base('mendix');
        Boolean api = namedCreds.contains('Mendix_API');
        Boolean requests = namedCreds.contains('Mendix_Requests');
        if (api || requests) {
            row.status = 'Pending Setup';
            row.statusTone = 'pending';
            row.metaLabel = 'Credentials';
            row.metaValue = 'Named credentials present';
            List<String> parts = new List<String>();
            if (api) {
                parts.add('Mendix_API');
            }
            if (requests) {
                parts.add('Mendix_Requests');
            }
            row.detail =
                String.join(parts, ' · ') +
                ' configured; live bi-directional sync still pending validation.';
            return row;
        }
        row.status = 'Not configured';
        row.statusTone = 'pending';
        row.metaLabel = 'Data status';
        row.metaValue = 'No Mendix credentials';
        row.detail = 'Mendix named credentials are missing.';
        return row;
    }

    private static IntegrationStatus wholesalerStatus(Integer aliasCount) {
        IntegrationStatus row = base('ibnsina-pharmaoverseas');
        if (aliasCount > 0) {
            row.status = 'Partial';
            row.statusTone = 'configured';
            row.metaLabel = 'Aliases';
            row.metaValue = String.valueOf(aliasCount) + ' mapped';
            row.detail =
                'Distributor sell-out aliases exist. Load files from Monthly data pack and review them in Distributors Management.';
            return row;
        }
        row.status = 'Not connected';
        row.statusTone = 'pending';
        row.metaLabel = 'Data status';
        row.metaValue = 'No aliases';
        row.detail = 'No Distributor_Sellout_Alias__c rows yet.';
        return row;
    }

    private static IntegrationStatus planned(String id) {
        IntegrationStatus row = base(id);
        row.status = 'Planned';
        row.statusTone = 'planned';
        row.metaLabel = 'Last sync';
        row.metaValue = '—';
        row.detail = 'Roadmap item — not configured in this org.';
        return row;
    }

    private static IntegrationStatus base(String id) {
        IntegrationStatus row = new IntegrationStatus();
        row.id = id;
        return row;
    }

    private static Set<String> loadNamedCredentialNames() {
        if (namedCredentialOverride != null) {
            return namedCredentialOverride;
        }
        Set<String> names = new Set<String>();
        try {
            for (NamedCredential nc : [
                SELECT DeveloperName
                FROM NamedCredential
                WHERE
                    DeveloperName IN (
                        'Google_Geocoding',
                        'OpenStreetMap_Nominatim',
                        'Mendix_API',
                        'Mendix_Requests'
                    )
            ]) {
                if (String.isNotBlank(nc.DeveloperName)) {
                    names.add(nc.DeveloperName);
                }
            }
        } catch (Exception e) {
            // Setup query can fail for some profiles; treat as unknown credentials.
        }
        return names;
    }
}
