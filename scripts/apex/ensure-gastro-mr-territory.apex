// Setup-object DML only — run in its own transaction before planner visit seed.
Id gastroMrId;
for (User u : [
    SELECT Id FROM User WHERE Username = 'gastro.mr@pharma.demo' AND IsActive = TRUE LIMIT 1
]) {
    gastroMrId = u.Id;
}
Id gastroTerrId;
for (Territory2 t : [
    SELECT Id FROM Territory2 WHERE External_ID__c = 'TERR_GASTRO_DM_1_MR_1' LIMIT 1
]) {
    gastroTerrId = t.Id;
}
if (gastroMrId == null || gastroTerrId == null) {
    System.debug('Skip: gastro.mr or TERR_GASTRO_DM_1_MR_1 not found.');
} else {
    Integer existing = [
        SELECT COUNT()
        FROM UserTerritory2Association
        WHERE UserId = :gastroMrId AND Territory2Id = :gastroTerrId
    ];
    if (existing == 0) {
        insert new UserTerritory2Association(
            UserId = gastroMrId,
            Territory2Id = gastroTerrId,
            RoleInTerritory2 = 'Medical Rep'
        );
        System.debug('Assigned gastro.mr to TERR_GASTRO_DM_1_MR_1.');
    } else {
        System.debug('gastro.mr already assigned to TERR_GASTRO_DM_1_MR_1.');
    }
}
