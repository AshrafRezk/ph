/**
 * Aura-enabled export API for pace dashboard monthly performance CSV.
 */
public with sharing class EmployeeTimeCardPaceExportController {

  @AuraEnabled(cacheable=false)
  public static String getMonthlyPerformanceCsv(Integer year, Integer month) {
    if (!EmployeeTimeCardPaceController.canViewTeam()) {
      throw new AuraHandledException('You do not have permission to export team performance.');
    }
    validateYearMonth(year, month);
    List<EmployeeTimeCardPaceExportService.PaceExportRow> rows =
      EmployeeTimeCardPaceExportService.loadExportRows(year, month);
    return EmployeeTimeCardPaceExportService.buildCsv(rows);
  }

  private static void validateYearMonth(Integer year, Integer month) {
    if (year == null || month == null || month < 1 || month > 12) {
      throw new AuraHandledException('Valid year and month are required.');
    }
  }
}
