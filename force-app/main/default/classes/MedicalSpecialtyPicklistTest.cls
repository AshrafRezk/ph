@IsTest
private class MedicalSpecialtyPicklistTest {
  @IsTest
  static void getLabel_returnsPicklistLabelForApiValue() {
    Test.startTest();
    String label = MedicalSpecialtyPicklist.getLabel('Paediatric_Oncology');
    Test.stopTest();

    System.assertEquals('Paediatric Oncology', label);
  }

  @IsTest
  static void getLabel_humanizesUnknownValues() {
    Test.startTest();
    String label = MedicalSpecialtyPicklist.getLabel('Unknown_Specialty_Value');
    Test.stopTest();

    System.assertEquals('Unknown Specialty Value', label);
  }

  @IsTest
  static void resolveApiValue_mapsLabelBackToApiValue() {
    Test.startTest();
    String apiValue = MedicalSpecialtyPicklist.resolveApiValue('Paediatric Oncology');
    Test.stopTest();

    System.assertEquals('Paediatric_Oncology', apiValue);
  }

  @IsTest
  static void resolveApiValue_preservesApiValue() {
    Test.startTest();
    String apiValue = MedicalSpecialtyPicklist.resolveApiValue('Cardiology');
    Test.stopTest();

    System.assertEquals('Cardiology', apiValue);
  }

  @IsTest
  static void getSearchTokens_includesLabelAndApiValue() {
    Test.startTest();
    List<String> tokens = MedicalSpecialtyPicklist.getSearchTokens('Pain_Management');
    Test.stopTest();

    System.assertEquals(2, tokens.size());
    System.assertEquals('pain_management', tokens[0]);
    System.assertEquals('pain management', tokens[1]);
  }
}
