@IsTest
private class UserSeatLabelServiceTest {
    @IsTest
    static void getSeatLabels_readsAssignedTerritory() {
        Assert.areEqual(0, UserSeatLabelService.getSeatLabels(new List<Id>()).size());

        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        if (territories.isEmpty()) {
            List<UserSeatLabelService.SeatLabel> blank = UserSeatLabelService.getSeatLabels(
                new List<Id>{ UserInfo.getUserId() }
            );
            Assert.areEqual(1, blank.size());
            Assert.areEqual('', blank[0].territoryName);
            return;
        }

        insert new UserTerritory2Association(
            UserId = UserInfo.getUserId(),
            Territory2Id = territories[0].Id,
            RoleInTerritory2 = 'Medical Rep'
        );

        Test.startTest();
        List<UserSeatLabelService.SeatLabel> labels = UserSeatLabelService.getSeatLabels(
            new List<Id>{ UserInfo.getUserId() }
        );
        Test.stopTest();

        Assert.areEqual(1, labels.size());
        Assert.isTrue(String.isNotBlank(labels[0].territoryName));
    }
}
