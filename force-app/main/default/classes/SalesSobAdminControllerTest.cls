@IsTest
private class SalesSobAdminControllerTest {
    @IsTest
    static void savesModuleAndItemTargets() {
        Product2 product = new Product2(Name = 'SOB Item', ProductCode = 'SOB-1', IsActive = true);
        insert product;

        SalesSobAdminController.EditorState savedDefault = SalesSobAdminController.saveDefaultSob(35);
        System.assertEquals(35, savedDefault.defaultPercent);

        SalesSobAdminController.EditorState savedItem = SalesSobAdminController.saveItemSob(product.Id, 12.5);
        System.assertEquals(1, savedItem.items.size());
        System.assertEquals(product.Id, savedItem.items[0].productId);
        System.assertEquals(12.5, savedItem.items[0].percent);

        SalesSobAdminController.EditorState cleared = SalesSobAdminController.clearItemSob(product.Id);
        System.assertEquals(0, cleared.items.size());
        System.assertEquals(35, cleared.defaultPercent);
    }

    @IsTest
    static void rejectsPercentOutsideRange() {
        Boolean rejected = false;
        try {
            SalesSobAdminController.saveDefaultSob(140);
        } catch (Exception ex) {
            rejected = true;
        }
        System.assertEquals(true, rejected);
    }
}
