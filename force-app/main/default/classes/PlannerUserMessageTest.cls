@IsTest
private class PlannerUserMessageTest {
  @IsTest
  static void sanitize_stripsPrefixesAndScriptThrown() {
    System.assertEquals(
      'Something went wrong. Please try again.',
      PlannerUserMessage.sanitize('Script-thrown exception')
    );
    System.assertEquals(
      'End time must be after start time.',
      PlannerUserMessage.sanitize('FIELD_CUSTOM_VALIDATION_EXCEPTION, End time must be after start time.')
    );
  }

  @IsTest
  static void aura_setsReadableMessage() {
    AuraHandledException ahe = PlannerUserMessage.aura('Select an account for the visit.');
    System.assertEquals('Select an account for the visit.', ahe.getMessage());
  }

  @IsTest
  static void fromException_usesDmlMessage() {
    try {
      insert as user new Account();
      System.assert(false, 'Expected DML failure');
    } catch (DmlException dml) {
      String message = PlannerUserMessage.fromException(dml);
      System.assert(String.isNotBlank(message));
      System.assert(!message.equalsIgnoreCase('Script-thrown exception'));
    }
  }
}