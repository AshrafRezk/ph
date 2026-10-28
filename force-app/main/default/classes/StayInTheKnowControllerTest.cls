@IsTest
private class StayInTheKnowControllerTest {
    private class RssMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            System.assert(
                req.getEndpoint().contains('rss-feeds'),
                'Expected rss-feeds endpoint'
            );
            HttpResponse res = new HttpResponse();
            res.setStatusCode(200);
            res.setHeader('Content-Type', 'application/json');
            res.setBody(
                '{"articles":[' +
                    '{"id":"a1","category":"Egypt","title":"Egypt pharma headline","summary":"Summary one",' +
                    '"source":"Google News","publishedAt":"2026-09-09T12:00:00.000Z","url":"https://example.com/1",' +
                    '"faviconUrl":"https://www.google.com/s2/favicons?domain=example.com&sz=64","domain":"example.com"},' +
                    '{"id":"a2","category":"Specialty","title":"SF headline","summary":"Summary two",' +
                    '"source":"Salesforce Blog","publishedAt":"2026-09-08T12:00:00.000Z","url":"https://news.example.com/2",' +
                    '"faviconUrl":null,"domain":"news.example.com"},' +
                    '{"id":"bad","category":"Zeta","title":"","summary":"Missing","source":"X","publishedAt":null,"url":""}' +
                    '],"categories":["Egypt","Specialty"],"fetchedAt":"2026-09-09T12:00:00.000Z"}'
            );
            return res;
        }
    }

    private class FailMock implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setStatusCode(503);
            res.setBody('{"error":"unavailable"}');
            return res;
        }
    }

    @IsTest
    static void getStayInTheKnowArticles_parsesPayload() {
        Test.setMock(HttpCalloutMock.class, new RssMock());
        Test.startTest();
        List<StayInTheKnowController.StayInTheKnowArticle> rows =
            StayInTheKnowController.getStayInTheKnowArticles(10);
        Test.stopTest();
        System.assertEquals(2, rows.size(), 'Blank title/url items must be skipped');
        System.assertEquals('Egypt pharma headline', rows[0].title);
        System.assertEquals('Egypt', rows[0].category);
        System.assertEquals('https://example.com/1', rows[0].url);
        System.assert(String.isNotBlank(rows[0].faviconUrl), 'favicon expected');
        System.assertEquals('SF headline', rows[1].title);
        System.assert(String.isNotBlank(rows[1].faviconUrl), 'favicon fallback expected');
    }

    @IsTest
    static void getStayInTheKnowArticles_respectsLimit() {
        Test.setMock(HttpCalloutMock.class, new RssMock());
        Test.startTest();
        List<StayInTheKnowController.StayInTheKnowArticle> rows =
            StayInTheKnowController.getStayInTheKnowArticles(1);
        Test.stopTest();
        System.assertEquals(1, rows.size());
    }

    @IsTest
    static void getStayInTheKnowArticles_calloutFailureReturnsEmpty() {
        Test.setMock(HttpCalloutMock.class, new FailMock());
        Test.startTest();
        List<StayInTheKnowController.StayInTheKnowArticle> rows =
            StayInTheKnowController.getStayInTheKnowArticles(null);
        Test.stopTest();
        System.assertEquals(0, rows.size());
    }

    @IsTest
    static void buildEndpoint_encodesTopics() {
        String endpoint = StayInTheKnowController.buildEndpoint(
            new List<String>{ 'Cardiology', 'Diabetes' },
            new List<String>{ 'Brand X' }
        );
        System.assert(endpoint.contains('specialties='), endpoint);
        System.assert(endpoint.contains('products='), endpoint);
    }
}