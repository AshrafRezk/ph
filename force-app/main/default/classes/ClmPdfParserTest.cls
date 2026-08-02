@IsTest
private class ClmPdfParserTest {

    @IsTest
    static void getPageCount_detectsMultiplePages() {
        String pdfBody = '%PDF-1.4\n' +
            '1 0 obj<</Type /Page /Parent 2 0 R>>endobj\n' +
            '2 0 obj<</Type /Page /Parent 2 0 R>>endobj\n' +
            '3 0 obj<</Type /Pages /Count 2 /Kids[1 0 R 2 0 R]>>endobj\n';
        Blob pdfBlob = Blob.valueOf(pdfBody);

        Test.startTest();
        Integer count = ClmPdfParser.getPageCount(pdfBlob);
        Test.stopTest();

        System.assertEquals(2, count);
    }

    @IsTest
    static void getPageCount_defaultsToOne() {
        Test.startTest();
        Integer count = ClmPdfParser.getPageCount(Blob.valueOf('not-a-pdf'));
        Test.stopTest();

        System.assertEquals(1, count);
    }
}
