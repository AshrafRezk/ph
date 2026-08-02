@IsTest
private class HomeOfficeMessageControllerTest {

    @IsTest
    static void publishAndRetrieve_allBusinessUnits() {
        Test.startTest();
        HomeOfficeMessageController.PublishResult published = HomeOfficeMessageController.publishMessage(
            'Test broadcast',
            'Hello all BUs',
            'All Business Units',
            null,
            null,
            null,
            'High'
        );
        List<HomeOfficeMessageController.HomeOfficeMessageRow> rows =
            HomeOfficeMessageController.getActiveMessages(5);
        Test.stopTest();

        System.assertNotEquals(null, published.recordId);
        System.assert(!rows.isEmpty(), 'Expected at least one active message');
        System.assertEquals('Test broadcast', rows[0].subject);
    }
}
