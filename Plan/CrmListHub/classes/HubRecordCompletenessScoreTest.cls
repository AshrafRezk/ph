/**
 * @description Tests for HubRecordCompletenessScore.
 */
@IsTest
private class HubRecordCompletenessScoreTest {
  @IsTest
  static void testScorePrefersRicherContact() {
    Contact sparse = new Contact(LastName = 'Sparse');
    insert sparse;
    Contact rich = new Contact(
      LastName = 'Rich',
      FirstName = 'Ada',
      Email = 'ada.rich@example.com',
      Phone = '555-0100',
      Title = 'Engineer'
    );
    insert rich;

    Contact sparseQ = [
      SELECT Id, Name, Email, Phone, Title, FirstName, LastName, AccountId
      FROM Contact
      WHERE Id = :sparse.Id
    ];
    Contact richQ = [
      SELECT Id, Name, Email, Phone, Title, FirstName, LastName, AccountId
      FROM Contact
      WHERE Id = :rich.Id
    ];

    HubRecordCompletenessScore.Result sparseScore = HubRecordCompletenessScore.scoreRecord(sparseQ, 'Contact');
    HubRecordCompletenessScore.Result richScore = HubRecordCompletenessScore.scoreRecord(richQ, 'Contact');
    System.assert(richScore.score >= sparseScore.score, 'Richer contact should score >= sparse');
    System.assertNotEquals(null, richScore.band);
    System.assert(richScore.toMap().containsKey('completenessScore'));
  }

  @IsTest
  static void testNullRecordSafe() {
    HubRecordCompletenessScore.Result res = HubRecordCompletenessScore.scoreRecord(null, 'Account');
    System.assertEquals(0, res.score);
  }

  @IsTest
  static void testAccountAndLeadScoring() {
    Account acc = new Account(Name = 'Score Acc', Phone = '555', Website = 'https://example.com', Industry = 'Technology');
    insert acc;
    acc = [SELECT Id, Name, Phone, Website, Industry, BillingStreet, BillingCity FROM Account WHERE Id = :acc.Id];
    HubRecordCompletenessScore.Result accScore = HubRecordCompletenessScore.scoreRecord(acc, 'Account');
    System.assert(accScore.score > 0);

    Lead ld = new Lead(LastName = 'ScoreLead', Company = 'Score Co', Email = 'lead@example.com');
    insert ld;
    ld = [SELECT Id, Name, Company, Email, Phone, Title FROM Lead WHERE Id = :ld.Id];
    HubRecordCompletenessScore.Result leadScore = HubRecordCompletenessScore.scoreRecord(ld, 'Lead');
    System.assertNotEquals(null, leadScore.band);
  }
}
