@IsTest
private class CommercialLineAssignmentServiceTest {
    @IsTest
    static void apply_movesListedPackOntoOctoberLine() {
        Product2 product = new Product2(
            Name = 'Duxnorzet 60 test',
            ProductCode = 'DU60',
            IsActive = true,
            Sales_Line__c = 'NEUROSCIENCE'
        );
        insert product;

        Test.startTest();
        CommercialLineAssignmentService.Result result = CommercialLineAssignmentService.applyRealignedSalesLines();
        Test.stopTest();

        Product2 updated = [SELECT Sales_Line__c FROM Product2 WHERE Id = :product.Id];
        Assert.areEqual('NEUROSCIENCE-I', updated.Sales_Line__c);
        Assert.isTrue(result.productsUpdated >= 1);
        Assert.isTrue(result.message.contains('Updated'));
    }
}
