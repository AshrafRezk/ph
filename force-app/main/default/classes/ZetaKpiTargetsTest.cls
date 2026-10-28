@IsTest
private class ZetaKpiTargetsTest {
    @IsTest
    static void resolvesRoleTargets() {
        System.assertEquals('DSM', ZetaKpiTargets.resolveManagerRoleKey('District Manager'));
        System.assertEquals('NSM', ZetaKpiTargets.resolveManagerRoleKey('Region Manager'));
        System.assertEquals(100, ZetaKpiTargets.coverageTargetForRole('DSM'));
        System.assertEquals(80, ZetaKpiTargets.coverageTargetForRole('ASM'));
    }
}