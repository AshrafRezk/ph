public with sharing class TotTeamCoverageController {
    @AuraEnabled(cacheable=true)
    public static TotTeamCoverageService.TeamCoverageSummary getTeamCoverageFrequency() {
        return TotTeamCoverageService.getTeamCoverageForManager(UserInfo.getUserId(), Date.today());
    }

    @AuraEnabled(cacheable=true)
    public static TotTeamCoverageService.TeamCoverageSummary getTeamCoverageFrequencyForScope(
        String buTerritoryId,
        String lineTerritoryId,
        String districtTerritoryId
    ) {
        return TotTeamCoverageService.getTeamCoverage(
            UserInfo.getUserId(),
            Date.today(),
            buTerritoryId,
            lineTerritoryId,
            districtTerritoryId
        );
    }
}