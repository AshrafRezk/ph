@IsTest
private class SalesDigestionExampleServiceTest {
    @IsTest
    static void getExample_whenEmpty_doesNotWrite() {
        Integer dmlBefore = Limits.getDmlStatements();
        SalesDigestionExampleService.DigestionExample example = SalesDigestionExampleService.getExample();
        System.assertEquals(dmlBefore, Limits.getDmlStatements(), 'Reads must not seed');
        System.assertEquals(false, example.seeded);
        System.assertNotEquals(null, example.message);
    }
}
