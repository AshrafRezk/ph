@IsTest
private class BrandManagerSeatServiceTest {
    @IsTest
    static void diabetesDivisions_mapToDiabLinesOneToFour() {
        System.assertEquals('DIAB-I', BrandManagerSeatService.lineNameForDivision('Diabetes I'));
        System.assertEquals('DIAB-II', BrandManagerSeatService.lineNameForDivision('Diabetes II'));
        System.assertEquals('DIAB-III', BrandManagerSeatService.lineNameForDivision('Diabetes III'));
        System.assertEquals('DIAB-IV', BrandManagerSeatService.lineNameForDivision('Diabetes IV'));
        System.assertEquals('DIAB-IV', BrandManagerSeatService.lineNameForDivision('DIAB IV'));
        System.assertEquals('DIAB-II', BrandManagerSeatService.lineNameForDivision('Diab-II'));
        System.assertEquals('DIAB-I', BrandManagerSeatService.lineNameForDivision('Diabetes'));
    }

    @IsTest
    static void otherDivisions_stillMap() {
        System.assertEquals('GIT-I', BrandManagerSeatService.lineNameForDivision('GIT I'));
        System.assertEquals('CVM-II', BrandManagerSeatService.lineNameForDivision('CVM II'));
        System.assertEquals('NEUROSCIENCE-I', BrandManagerSeatService.lineNameForDivision('CNS'));
        System.assertEquals('PEDIA', BrandManagerSeatService.lineNameForDivision('Pedia/Gyn'));
        System.assertEquals('ORTHO-II', BrandManagerSeatService.lineNameForDivision('Ortho II'));
        System.assertEquals('DERMA', BrandManagerSeatService.lineNameForDivision('Derma'));
        System.assertEquals(null, BrandManagerSeatService.lineNameForDivision(null));
        System.assertEquals(null, BrandManagerSeatService.lineNameForDivision('Unknown Division'));
    }

    @IsTest
    static void seat_runsWithoutOrganogramData() {
        BrandManagerSeatService.SeatResult result = BrandManagerSeatService.seatMarketingOnOrganogram();
        System.assertNotEquals(null, result);
        System.assertNotEquals(null, result.messages);
    }
}
