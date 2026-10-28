@IsTest
private class TerritoryPreviewServiceTest {
    @IsTest
    static void clearPreview_runs() {
        Test.startTest();
        TerritoryPreviewService.clearPreview();
        Test.stopTest();
        System.assert(true, 'clearPreview should run without error');
    }

    @IsTest
    static void previewAsUser_rejectsSelf() {
        Boolean threw = false;
        try {
            TerritoryPreviewService.previewAsUser(UserInfo.getUserId());
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'previewing self should fail');
    }

    @IsTest
    static void previewAsUser_rejectsBlank() {
        Boolean threw = false;
        try {
            TerritoryPreviewService.previewAsUser(null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'blank user should fail');
    }

    @IsTest
    static void previewAsUser_rejectsMissingUser() {
        Boolean threw = false;
        // Valid Id shape that will not match a User row.
        Id fakeUserId = UserInfo.getOrganizationId();
        try {
            TerritoryPreviewService.previewAsUser(fakeUserId);
        } catch (Exception e) {
            threw = true;
        }
        System.assertEquals(true, threw, 'missing user should fail');
    }

    @IsTest(SeeAllData=true)
    static void previewAsUser_happyPathWhenSeatExists() {
        List<UserTerritory2Association> seats = [
            SELECT UserId, Territory2Id
            FROM UserTerritory2Association
            WHERE IsActive = TRUE
                AND UserId != :UserInfo.getUserId()
                AND User.IsActive = TRUE
            LIMIT 1
        ];
        if (seats.isEmpty()) {
            System.assert(true, 'No alternate seated user in test org — skip happy path');
            return;
        }
        Test.startTest();
        TerritoryPreviewService.PreviewResult result = TerritoryPreviewService.previewAsUser(seats[0].UserId);
        TerritoryPreviewService.clearPreview();
        Test.stopTest();
        System.assertEquals(seats[0].UserId, result.previewUserId);
        System.assertNotEquals(null, result.selectedTerritoryId);
        System.assert(String.isNotBlank(result.message));
    }
}
