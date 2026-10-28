/**
 * SFE territory preview: scopes the caller's switcher context to another user's
 * seats without setting their password. Full impersonation is Salesforce Login As.
 */
public with sharing class TerritoryPreviewService {
    public class PreviewResult {
        @AuraEnabled public Id previewUserId;
        @AuraEnabled public String previewUserName;
        @AuraEnabled public Id selectedTerritoryId;
        @AuraEnabled public String message;
    }

    @AuraEnabled
    public static PreviewResult previewAsUser(Id userId) {
        if (userId == null) {
            throw new AuraHandledException('User is required.');
        }
        if (userId == UserInfo.getUserId()) {
            throw new AuraHandledException('Already acting as yourself.');
        }
        List<User> targets = [
            SELECT Id, Name, IsActive
            FROM User
            WHERE Id = :userId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (targets.isEmpty()) {
            throw new AuraHandledException('User not found.');
        }
        if (targets[0].IsActive != true) {
            throw new AuraHandledException('Cannot preview an inactive user.');
        }

        List<UserTerritory2Association> seats = [
            SELECT Territory2Id, RoleInTerritory2, Territory2.Name
            FROM UserTerritory2Association
            WHERE UserId = :userId AND IsActive = TRUE
            WITH SYSTEM_MODE
            ORDER BY Territory2.Name ASC
        ];
        if (seats.isEmpty()) {
            throw new AuraHandledException(
                targets[0].Name + ' has no territory seat, so there is nothing to preview.'
            );
        }

        // Preview switches the caller's own territory context, so it has to be a seat the caller's
        // own seat covers. Pick the first one that is, instead of failing on the first seat by name.
        Set<Id> switchable = TerritoryContextService.getSwitchableTerritoryIds(UserInfo.getUserId());
        UserTerritory2Association seat = null;
        for (UserTerritory2Association candidate : seats) {
            if (switchable.contains(candidate.Territory2Id)) {
                seat = candidate;
                break;
            }
        }
        if (seat == null) {
            throw new AuraHandledException(
                'Your own territory seat does not cover ' + targets[0].Name + ' (' + seats[0].Territory2.Name
                + '). Use "Open field app as user" to see the app as this person.'
            );
        }

        Id territoryId = seat.Territory2Id;
        TerritoryContextService.setSelectedTerritory(territoryId);

        System.debug(
            LoggingLevel.INFO,
            'TerritoryPreview audit actor='
                + UserInfo.getUserId()
                + ' previewUser='
                + userId
                + ' territory='
                + territoryId
        );

        PreviewResult result = new PreviewResult();
        result.previewUserId = userId;
        result.previewUserName = targets[0].Name;
        result.selectedTerritoryId = territoryId;
        result.message =
            'Previewing territory of '
            + targets[0].Name
            + ' ('
            + seat.Territory2.Name
            + '). Use Salesforce Login As for full session impersonation. OTP Password only resets passwords.';
        return result;
    }

    @AuraEnabled
    public static void clearPreview() {
        TerritoryContextService.setSelectedTerritory(null);
    }
}
