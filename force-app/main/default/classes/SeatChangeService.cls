/**
 * Organogram seat changes from Admin Console: promotions / transfers on the Edit User screen and
 * organogram CSV uploads on the Territories tab. Every change is logged on Seat_Change__c.
 * Changes dated today or earlier apply at once; later ones stay Scheduled and SeatChangeJob applies
 * them on the effective date.
 *
 * UserTerritory2Association and User are setup objects, so a transaction that changes seats can't
 * also write Seat_Change__c (MIXED_DML_OPERATION). The log rows are written by SeatChangeLogJob.
 */
public without sharing class SeatChangeService {
    public static final String ACTION_ASSIGN = 'Assign';
    public static final String ACTION_REMOVE = 'Remove';
    public static final String STATUS_SCHEDULED = 'Scheduled';
    public static final String STATUS_APPLIED = 'Applied';
    public static final String STATUS_FAILED = 'Failed';
    public static final String STATUS_CANCELLED = 'Cancelled';
    public static final String SOURCE_PROMOTION = 'Promotion';
    public static final String SOURCE_UPLOAD = 'Organogram Upload';

    /** One seat change in memory, before it is applied or logged. */
    public class Change {
        public Id recordId;
        public Id userId;
        public String userName;
        public String action;
        public String territoryExternalId;
        public String territoryName;
        public String role;
        public String newTitle;
        public Boolean releaseOtherSeats = false;
        public Boolean replaceSameRole = false;
        public Date effectiveDate;
        public String source;
        public String status;
        public String message;
        public String previousSeats;
    }

    public class PromotionRequest {
        @AuraEnabled public Id userId;
        @AuraEnabled public String territoryExternalId;
        @AuraEnabled public String role;
        @AuraEnabled public String newTitle;
        @AuraEnabled public String effectiveDate;
        @AuraEnabled public Boolean releaseOtherSeats;
        @AuraEnabled public Boolean replaceSameRole;
    }

    public class SubmitResult {
        @AuraEnabled public Integer applied = 0;
        @AuraEnabled public Integer scheduled = 0;
        @AuraEnabled public Integer failed = 0;
        @AuraEnabled public Integer unchanged = 0;
        @AuraEnabled public List<String> messages = new List<String>();
    }

    /**
     * One CSV row from the organogram upload, as parsed in the browser. Territory Id / Holder User Id
     * are the Salesforce Ids from the downloaded template; External Id, username, employee code and
     * name are fallbacks. Remove = Y removes the holder on that row, or the whole position when the
     * row has no holder.
     */
    public class UploadRow {
        public Integer rowNumber;
        public String territoryId;
        public String territoryExternalId;
        public String territoryName;
        public String parentExternalId;
        public String level;
        public String title;
        public String holderUserId;
        public String holder;
        public String holderUsername;
        public String employeeCode;
        public String effectiveDate;
        public String remove;
    }

    public class PreviewLine {
        @AuraEnabled public String key;
        @AuraEnabled public String action;
        @AuraEnabled public String territoryName;
        @AuraEnabled public String territoryExternalId;
        @AuraEnabled public String personName;
        @AuraEnabled public String role;
        @AuraEnabled public String effectiveDate;
        @AuraEnabled public String timing;
        @AuraEnabled public String message;
    }

    public class UploadPreview {
        @AuraEnabled public Integer rowCount = 0;
        @AuraEnabled public Integer seatCount = 0;
        @AuraEnabled public Integer assignCount = 0;
        @AuraEnabled public Integer removeCount = 0;
        @AuraEnabled public Integer roleChangeCount = 0;
        @AuraEnabled public Integer unchangedCount = 0;
        @AuraEnabled public Integer scheduledCount = 0;
        @AuraEnabled public Integer errorCount = 0;
        @AuraEnabled public Integer createCount = 0;
        @AuraEnabled public Integer renameCount = 0;
        @AuraEnabled public Integer moveCount = 0;
        @AuraEnabled public Integer deletePositionCount = 0;
        @AuraEnabled public List<PreviewLine> lines = new List<PreviewLine>();
    }

    public class ScheduledRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String action;
        @AuraEnabled public String territoryName;
        @AuraEnabled public String territoryExternalId;
        @AuraEnabled public String role;
        @AuraEnabled public String newTitle;
        @AuraEnabled public Date effectiveDate;
        @AuraEnabled public String source;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
        @AuraEnabled public String requestedBy;
    }

    private class Plan {
        List<Change> changes = new List<Change>();
        List<StructureOp> structure = new List<StructureOp>();
        UploadPreview preview = new UploadPreview();
    }

    /** A position created, renamed, moved or removed by the upload. Applied at once, never scheduled. */
    private class StructureOp {
        String kind;
        String externalId;
        String name;
        String territoryType;
        String parentExternalId;
        Territory2 territory;
    }

    /** What the file asks for one seat, after its rows are checked. */
    private class SeatWork {
        Territory2 territory;
        Boolean isNew = false;
        String territoryType;
        Boolean removeSeat = false;
        Map<Id, String> desired = new Map<Id, String>();
        Map<Id, Date> desiredDate = new Map<Id, Date>();
        Map<Id, Date> removals = new Map<Id, Date>();
    }

    // ---------------------------------------------------------------- promotion / transfer

    @AuraEnabled
    public static SubmitResult promoteUser(String requestJson) {
        requireManageUsers();
        PromotionRequest request = String.isBlank(requestJson)
            ? null
            : (PromotionRequest) JSON.deserialize(requestJson, PromotionRequest.class);
        if (request == null || request.userId == null || String.isBlank(request.territoryExternalId)) {
            throw new AuraHandledException('Pick the person and the new position.');
        }
        Date effective = parseDate(request.effectiveDate);
        if (String.isNotBlank(request.effectiveDate) && effective == null) {
            throw new AuraHandledException('Effective date is not a valid date.');
        }
        List<Territory2> targets = [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE External_ID__c = :request.territoryExternalId.trim()
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (targets.isEmpty()) {
            throw new AuraHandledException('Position ' + request.territoryExternalId + ' was not found.');
        }
        User person = [SELECT Id, Name FROM User WHERE Id = :request.userId WITH SYSTEM_MODE LIMIT 1];

        Change change = new Change();
        change.userId = person.Id;
        change.userName = person.Name;
        change.action = ACTION_ASSIGN;
        change.territoryExternalId = targets[0].External_ID__c;
        change.territoryName = targets[0].Name;
        change.role = String.isBlank(request.role) ? 'Medical Rep' : request.role.trim();
        change.newTitle = String.isBlank(request.newTitle) ? null : request.newTitle.trim();
        change.releaseOtherSeats = request.releaseOtherSeats == true;
        change.replaceSameRole = request.replaceSameRole == true;
        change.effectiveDate = effective == null ? Date.today() : effective;
        change.source = SOURCE_PROMOTION;
        return submit(new List<Change>{ change });
    }

    // ---------------------------------------------------------------- organogram upload

    @AuraEnabled
    public static UploadPreview previewOrganogramUpload(String rowsJson, Boolean releaseOtherSeats) {
        requireManageUsers();
        return buildUploadPlan(parseRows(rowsJson), releaseOtherSeats == true).preview;
    }

    @AuraEnabled
    public static SubmitResult applyOrganogramUpload(String rowsJson, Boolean releaseOtherSeats) {
        requireManageUsers();
        Plan plan = buildUploadPlan(parseRows(rowsJson), releaseOtherSeats == true);
        SubmitResult result = new SubmitResult();

        // New, renamed and moved positions first, so people can be seated in them; removed positions last.
        Set<String> failedCreates = applyStructure(plan.structure, result);
        List<Change> seatChanges = new List<Change>();
        for (Change change : plan.changes) {
            if (change.territoryExternalId != null && failedCreates.contains(change.territoryExternalId.toUpperCase())) {
                result.failed++;
                result.messages.add(change.userName + ' → ' + change.territoryName + ': the new position was not created.');
            } else {
                seatChanges.add(change);
            }
        }
        // Territory2 DML makes this a setup transaction, so the log rows always go through the queue.
        SubmitResult seats = submit(seatChanges, !plan.structure.isEmpty());
        result.applied += seats.applied;
        result.scheduled += seats.scheduled;
        result.failed += seats.failed;
        result.messages.addAll(seats.messages);
        applyRemovedPositions(plan.structure, result);

        result.unchanged = plan.preview.unchangedCount;
        if (plan.preview.errorCount > 0) {
            result.messages.add(plan.preview.errorCount + ' row(s) had errors and were skipped.');
        }
        return result;
    }

    private static List<UploadRow> parseRows(String rowsJson) {
        if (String.isBlank(rowsJson)) {
            throw new AuraHandledException('The file has no rows.');
        }
        List<UploadRow> rows = (List<UploadRow>) JSON.deserialize(rowsJson, List<UploadRow>.class);
        if (rows.size() > 3000) {
            throw new AuraHandledException('Upload at most 3000 rows at a time.');
        }
        return rows;
    }

    /**
     * Reads the file as instructions, not as the full organogram: only listed seats change, and only
     * in the way the rows say. A new holder replaces whoever holds the same title in that seat (not in
     * Head Office). Remove = Y takes a person out, or removes the position when the row has no holder.
     * A seat with any bad row is skipped whole, so a typo never half-applies.
     */
    @TestVisible
    private static Plan buildUploadPlan(List<UploadRow> rows, Boolean releaseOtherSeats) {
        Plan plan = new Plan();
        UploadPreview preview = plan.preview;
        preview.rowCount = rows.size();
        Date today = Date.today();

        Set<Id> territoryIds = new Set<Id>();
        Set<String> externalIds = new Set<String>();
        Set<Id> userIds = new Set<Id>();
        Set<String> logins = new Set<String>();
        Set<String> codes = new Set<String>();
        Set<String> names = new Set<String>();
        for (UploadRow row : rows) {
            row.territoryId = clean(row.territoryId);
            row.territoryExternalId = clean(row.territoryExternalId);
            row.territoryName = clean(row.territoryName);
            row.parentExternalId = clean(row.parentExternalId);
            row.level = clean(row.level);
            row.title = clean(row.title);
            row.holderUserId = clean(row.holderUserId);
            row.holder = clean(row.holder);
            row.holderUsername = clean(row.holderUsername);
            row.employeeCode = clean(row.employeeCode);
            row.remove = clean(row.remove);
            if (row.holder != null && row.holder.equalsIgnoreCase('Vacant')) {
                row.holder = null;
            }
            Id territoryId = toId(row.territoryId, Territory2.SObjectType);
            if (territoryId != null) {
                territoryIds.add(territoryId);
            }
            if (row.territoryExternalId != null) {
                externalIds.add(row.territoryExternalId);
            }
            if (row.parentExternalId != null) {
                externalIds.add(row.parentExternalId);
            }
            Id userId = toId(row.holderUserId, User.SObjectType);
            if (userId != null) {
                userIds.add(userId);
            }
            if (row.holderUsername != null) {
                logins.add(row.holderUsername);
            }
            if (row.employeeCode != null) {
                codes.add(row.employeeCode);
            }
            if (row.holder != null) {
                names.add(row.holder);
            }
        }

        Map<Id, Territory2> territoryById = new Map<Id, Territory2>();
        Map<String, Territory2> territoryByExternal = new Map<String, Territory2>();
        for (Territory2 territory : [
            SELECT Id, Name, DeveloperName, External_ID__c, Territory_Type__c, ParentTerritory2Id,
                ParentTerritory2.External_ID__c
            FROM Territory2
            WHERE Id IN :territoryIds OR External_ID__c IN :externalIds
            WITH SYSTEM_MODE
        ]) {
            territoryById.put(territory.Id, territory);
            if (territory.External_ID__c != null) {
                territoryByExternal.put(territory.External_ID__c.toUpperCase(), territory);
            }
        }

        Map<Id, User> userById = new Map<Id, User>();
        Map<String, User> userByUsername = new Map<String, User>();
        Map<String, User> userByCode = new Map<String, User>();
        Map<String, List<User>> usersByName = new Map<String, List<User>>();
        for (User person : [
            SELECT Id, Name, Username, EmployeeNumber
            FROM User
            WHERE IsActive = TRUE
              AND (Id IN :userIds OR Username IN :logins OR EmployeeNumber IN :codes OR Name IN :names)
            WITH SYSTEM_MODE
        ]) {
            userById.put(person.Id, person);
            userByUsername.put(person.Username.toLowerCase(), person);
            if (person.EmployeeNumber != null) {
                userByCode.put(person.EmployeeNumber.trim(), person);
            }
            String nameKey = person.Name.toLowerCase();
            if (!usersByName.containsKey(nameKey)) {
                usersByName.put(nameKey, new List<User>());
            }
            usersByName.get(nameKey).add(person);
        }

        // Group rows into seats: an existing territory (by Territory Id, then External Id) or a new one.
        Map<String, List<UploadRow>> rowsBySeat = new Map<String, List<UploadRow>>();
        Map<String, Territory2> existingBySeat = new Map<String, Territory2>();
        List<String> seatOrder = new List<String>();
        for (UploadRow row : rows) {
            Territory2 territory = null;
            Id territoryId = toId(row.territoryId, Territory2.SObjectType);
            if (row.territoryId != null && territoryId == null) {
                addError(preview, row, null, 'Territory Id "' + row.territoryId + '" is not a Salesforce territory Id.');
                continue;
            }
            if (territoryId != null) {
                territory = territoryById.get(territoryId);
                if (territory == null) {
                    addError(preview, row, null, 'No territory has this Territory Id. Download the organogram again.');
                    continue;
                }
                if (row.territoryExternalId != null && !row.territoryExternalId.equalsIgnoreCase(territory.External_ID__c)) {
                    addError(preview, row, territory, 'Territory Id and Territory External Id point to different territories.');
                    continue;
                }
            } else if (row.territoryExternalId != null) {
                territory = territoryByExternal.get(row.territoryExternalId.toUpperCase());
            }
            String seatKey;
            if (territory != null) {
                seatKey = territory.Id;
                existingBySeat.put(seatKey, territory);
            } else if (row.territoryExternalId != null && row.territoryName == null && row.level == null) {
                addError(preview, row, null, 'No territory has this External Id. For a new position also fill Territory, Level and Parent External Id.');
                continue;
            } else if (row.territoryExternalId != null) {
                seatKey = 'NEW:' + row.territoryExternalId.toUpperCase();
            } else if (row.territoryName != null && toTerritoryType(row.level) != null) {
                row.territoryExternalId = newExternalId(toTerritoryType(row.level), row.territoryName);
                seatKey = 'NEW:' + row.territoryExternalId.toUpperCase();
            } else {
                if (hasPerson(row) || row.territoryName != null || isYes(row.remove)) {
                    addError(preview, row, null, 'Add the Territory External Id (or, for a new position, the Territory name and Level).');
                }
                continue;
            }
            if (!rowsBySeat.containsKey(seatKey)) {
                rowsBySeat.put(seatKey, new List<UploadRow>());
                seatOrder.add(seatKey);
            }
            rowsBySeat.get(seatKey).add(row);
        }

        // Types of positions created in this file, so a new position can sit under a new district.
        Map<String, String> newTypeByExternal = new Map<String, String>();
        Set<String> newDeveloperNames = new Set<String>();
        Set<Id> removeCandidates = new Set<Id>();
        for (String seatKey : seatOrder) {
            List<UploadRow> seatRows = rowsBySeat.get(seatKey);
            if (seatKey.startsWith('NEW:')) {
                String level = null;
                for (UploadRow row : seatRows) {
                    level = level == null ? row.level : level;
                }
                newTypeByExternal.put(seatKey.removeStart('NEW:'), toTerritoryType(level));
                newDeveloperNames.add(developerNameFor(seatKey.removeStart('NEW:')));
            } else {
                for (UploadRow row : seatRows) {
                    if (isYes(row.remove) && !hasPerson(row)) {
                        removeCandidates.add((Id) seatKey);
                    }
                }
            }
        }
        Set<String> takenDeveloperNames = new Set<String>();
        for (Territory2 territory : [
            SELECT DeveloperName FROM Territory2 WHERE DeveloperName IN :newDeveloperNames WITH SYSTEM_MODE
        ]) {
            takenDeveloperNames.add(territory.DeveloperName.toUpperCase());
        }
        Map<Id, List<Id>> childrenByParent = new Map<Id, List<Id>>();
        for (Territory2 child : [
            SELECT Id, ParentTerritory2Id FROM Territory2 WHERE ParentTerritory2Id IN :removeCandidates WITH SYSTEM_MODE
        ]) {
            if (!childrenByParent.containsKey(child.ParentTerritory2Id)) {
                childrenByParent.put(child.ParentTerritory2Id, new List<Id>());
            }
            childrenByParent.get(child.ParentTerritory2Id).add(child.Id);
        }
        Map<Id, Integer> accountsByTerritory = alignedAccountCounts(removeCandidates);

        // Check each seat and turn its rows into the wanted result.
        List<SeatWork> work = new List<SeatWork>();
        for (String seatKey : seatOrder) {
            List<UploadRow> seatRows = rowsBySeat.get(seatKey);
            UploadRow first = seatRows[0];
            Territory2 existing = existingBySeat.get(seatKey);
            SeatWork seat = new SeatWork();
            seat.isNew = existing == null;

            String name = null;
            String parentExternalId = null;
            String level = null;
            Boolean seatOk = true;
            for (UploadRow row : seatRows) {
                if (row.territoryName != null) {
                    if (name != null && name != row.territoryName) {
                        addError(preview, row, existing, 'Rows for one territory must use the same Territory name.');
                        seatOk = false;
                    }
                    name = row.territoryName;
                }
                if (row.parentExternalId != null) {
                    if (parentExternalId != null && !parentExternalId.equalsIgnoreCase(row.parentExternalId)) {
                        addError(preview, row, existing, 'Rows for one territory must use the same Parent External Id.');
                        seatOk = false;
                    }
                    parentExternalId = row.parentExternalId;
                }
                level = level == null ? row.level : level;
            }
            String externalId = seat.isNew ? first.territoryExternalId : existing.External_ID__c;
            seat.territoryType = seat.isNew ? toTerritoryType(level) : existing.Territory_Type__c;
            seat.territory = seat.isNew
                ? new Territory2(Name = name, External_ID__c = externalId, Territory_Type__c = seat.territoryType)
                : existing;
            Boolean headOffice = externalId == 'TERR_HEAD_OFFICE';
            Boolean structural = STRUCTURE_TYPES.contains(seat.territoryType);

            // People on the rows.
            for (UploadRow row : seatRows) {
                Date rowDate = null;
                if (row.effectiveDate != null) {
                    rowDate = parseDate(row.effectiveDate);
                    if (rowDate == null) {
                        addError(preview, row, seat.territory, 'Effective Date "' + row.effectiveDate + '" is not a date (use YYYY-MM-DD).');
                        seatOk = false;
                        continue;
                    }
                }
                if (!hasPerson(row)) {
                    if (isYes(row.remove)) {
                        seat.removeSeat = true;
                        if (rowDate != null && rowDate > today) {
                            addError(preview, row, seat.territory, 'Positions are removed at once. Clear the Effective Date.');
                            seatOk = false;
                        }
                    }
                    continue;
                }
                User person = null;
                Id userId = toId(row.holderUserId, User.SObjectType);
                if (row.holderUserId != null) {
                    person = userId == null ? null : userById.get(userId);
                    if (person == null) {
                        addError(preview, row, seat.territory, 'No active user has Holder User Id ' + row.holderUserId + '.');
                        seatOk = false;
                        continue;
                    }
                }
                if (person == null && row.holderUsername != null) {
                    person = userByUsername.get(row.holderUsername.toLowerCase());
                }
                if (person == null && row.employeeCode != null) {
                    person = userByCode.get(row.employeeCode);
                }
                if (person == null && row.holder != null && row.holderUsername == null && row.employeeCode == null) {
                    List<User> sameName = usersByName.get(row.holder.toLowerCase());
                    if (sameName != null && sameName.size() > 1) {
                        addError(preview, row, seat.territory, 'More than one active user is called ' + row.holder + '. Add the Holder Username.');
                        seatOk = false;
                        continue;
                    }
                    person = sameName == null ? null : sameName[0];
                }
                if (person == null) {
                    String who = firstNonBlank(row.holderUsername, row.employeeCode, row.holder);
                    addError(preview, row, seat.territory, 'No active user matches ' + who + '.');
                    seatOk = false;
                    continue;
                }
                userNamesCache.put(person.Id, person.Name);
                if (isYes(row.remove)) {
                    seat.removals.put(person.Id, rowDate);
                } else {
                    seat.desired.put(person.Id, row.title == null ? defaultTitle(seat.territoryType) : row.title);
                    seat.desiredDate.put(person.Id, rowDate);
                }
            }

            // The position itself.
            if (seat.removeSeat) {
                String problem = null;
                if (seat.isNew) {
                    problem = 'This position does not exist, so it cannot be removed.';
                } else if (headOffice || !structural) {
                    problem = 'Only positions, districts and marketing seats can be removed here. Remove lines and business units in Setup → Territory Models.';
                } else if (!seat.desired.isEmpty()) {
                    problem = 'One row removes this position while another row seats someone in it.';
                } else if (accountsByTerritory.get(existing.Id) != null) {
                    problem = accountsByTerritory.get(existing.Id) + ' accounts are aligned to this position. Move them to another position first.';
                } else if (childrenByParent.containsKey(existing.Id)) {
                    for (Id childId : childrenByParent.get(existing.Id)) {
                        if (!removingInFile(rowsBySeat, childId)) {
                            problem = 'It still has positions under it. Remove or move those first (they can be in the same file).';
                            break;
                        }
                    }
                }
                if (problem != null) {
                    addError(preview, first, seat.territory, problem);
                    seatOk = false;
                }
            } else if (seat.isNew) {
                String problem = null;
                if (seat.territoryType == null) {
                    problem = 'Add the Level (Position, District or Marketing Seat) for the new position.';
                } else if (!structural) {
                    problem = 'New lines and business units are created in Setup → Territory Models.';
                } else if (name == null) {
                    problem = 'Add the Territory name for the new position.';
                } else if (!externalId.startsWithIgnoreCase('TERR_')) {
                    problem = 'New External Ids start with TERR_ (or leave it empty and one is made from the name).';
                } else if (takenDeveloperNames.contains(developerNameFor(externalId).toUpperCase())) {
                    problem = 'A territory with this code already exists. Use another External Id.';
                } else {
                    problem = parentProblem(seat.territoryType, parentExternalId, territoryByExternal, newTypeByExternal);
                }
                if (problem != null) {
                    addError(preview, first, seat.territory, problem);
                    seatOk = false;
                }
            } else if (headOffice && (name != null && name != existing.Name || parentExternalId != null
                    && !parentExternalId.equalsIgnoreCase(existing.ParentTerritory2?.External_ID__c))) {
                addError(preview, first, seat.territory, 'Head Office cannot be renamed or moved.');
                seatOk = false;
            } else {
                Boolean renamed = name != null && name != existing.Name;
                Boolean moved = parentExternalId != null
                    && !parentExternalId.equalsIgnoreCase(existing.ParentTerritory2?.External_ID__c);
                if ((renamed || moved) && !structural) {
                    addError(preview, first, seat.territory, 'Rename lines and business units with Edit on the Territories tab; move them in Setup.');
                    seatOk = false;
                } else if (moved) {
                    String problem = parentExternalId.equalsIgnoreCase(externalId)
                        ? 'A territory cannot sit under itself.'
                        : parentProblem(seat.territoryType, parentExternalId, territoryByExternal, newTypeByExternal);
                    if (problem != null) {
                        addError(preview, first, seat.territory, problem);
                        seatOk = false;
                    }
                }
            }
            if (!seatOk) {
                continue;
            }

            preview.seatCount++;
            if (seat.removeSeat) {
                plan.structure.add(structureOp('Delete', seat.territory, null));
                preview.deletePositionCount++;
                addStructureLine(preview, 'Remove position', seat.territory, null);
            } else if (seat.isNew) {
                StructureOp op = structureOp('Create', seat.territory, parentExternalId);
                plan.structure.add(op);
                preview.createCount++;
                addStructureLine(preview, 'New position', seat.territory, levelLabel(seat.territoryType) + ' under ' + parentExternalId);
            } else {
                if (name != null && name != existing.Name) {
                    StructureOp op = structureOp('Rename', existing, null);
                    op.name = name;
                    plan.structure.add(op);
                    preview.renameCount++;
                    addStructureLine(preview, 'Rename', existing, 'To "' + name + '"');
                }
                if (parentExternalId != null && !parentExternalId.equalsIgnoreCase(existing.ParentTerritory2?.External_ID__c)) {
                    plan.structure.add(structureOp('Move', existing, parentExternalId));
                    preview.moveCount++;
                    addStructureLine(preview, 'Move', existing, 'Under ' + parentExternalId);
                }
            }
            work.add(seat);
        }

        // Current holders of the listed seats, plus every organogram seat of the people being seated.
        Set<Id> listedSeats = new Set<Id>();
        Set<Id> seatedUsers = new Set<Id>();
        for (SeatWork seat : work) {
            if (!seat.isNew) {
                listedSeats.add(seat.territory.Id);
            }
            seatedUsers.addAll(seat.desired.keySet());
        }
        Map<Id, Map<Id, UserTerritory2Association>> currentBySeat = new Map<Id, Map<Id, UserTerritory2Association>>();
        List<UserTerritory2Association> otherSeatsOfSeated = new List<UserTerritory2Association>();
        for (UserTerritory2Association link : [
            SELECT Id, UserId, User.Name, User.Title, Territory2Id, Territory2.Name, Territory2.External_ID__c,
                Territory2.Territory_Type__c, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE Territory2Id IN :listedSeats OR UserId IN :seatedUsers
            WITH SYSTEM_MODE
        ]) {
            userNamesCache.put(link.UserId, link.User.Name);
            if (listedSeats.contains(link.Territory2Id)) {
                if (!currentBySeat.containsKey(link.Territory2Id)) {
                    currentBySeat.put(link.Territory2Id, new Map<Id, UserTerritory2Association>());
                }
                currentBySeat.get(link.Territory2Id).put(link.UserId, link);
            }
            if (seatedUsers.contains(link.UserId) && isOrganogramSeat(link.Territory2.External_ID__c)) {
                otherSeatsOfSeated.add(link);
            }
        }

        Map<Id, Date> moveDateByUser = new Map<Id, Date>();
        Map<Id, Set<String>> fileSeatsByUser = new Map<Id, Set<String>>();
        for (SeatWork seat : work) {
            Territory2 territory = seat.territory;
            Map<Id, UserTerritory2Association> current = seat.isNew || !currentBySeat.containsKey(territory.Id)
                ? new Map<Id, UserTerritory2Association>()
                : currentBySeat.get(territory.Id);

            if (seat.removeSeat) {
                for (UserTerritory2Association link : current.values()) {
                    Change change = uploadChange(ACTION_REMOVE, link.UserId, userNamesCache.get(link.UserId), territory, link.RoleInTerritory2, null);
                    change.message = 'Position removed.';
                    plan.changes.add(change);
                    preview.removeCount++;
                    addLine(preview, change, 'Remove', today);
                }
                continue;
            }

            Set<Id> replaced = new Set<Id>();
            for (Id userId : seat.desired.keySet()) {
                if (!fileSeatsByUser.containsKey(userId)) {
                    fileSeatsByUser.put(userId, new Set<String>());
                }
                fileSeatsByUser.get(userId).add(territory.External_ID__c.toUpperCase());
                String role = seat.desired.get(userId);
                Date effective = seat.desiredDate.get(userId);
                UserTerritory2Association link = current.get(userId);
                if (link != null && holdsTitle(link, role)) {
                    preview.unchangedCount++;
                    continue;
                }
                Change change = uploadChange(ACTION_ASSIGN, userId, userNamesCache.get(userId), territory, role, effective);
                plan.changes.add(change);
                if (link == null) {
                    preview.assignCount++;
                } else {
                    preview.roleChangeCount++;
                }
                addLine(preview, change, link == null ? 'Assign' : 'Change title', today);
                Date known = moveDateByUser.get(userId);
                if (known == null || (effective != null && effective > known)) {
                    moveDateByUser.put(userId, effective);
                }
                // The new holder takes over from whoever holds the same title here.
                if (territory.External_ID__c == 'TERR_HEAD_OFFICE') {
                    continue;
                }
                for (UserTerritory2Association other : current.values()) {
                    if (other.UserId == userId || seat.desired.containsKey(other.UserId)
                            || seat.removals.containsKey(other.UserId) || replaced.contains(other.UserId)
                            || !holdsTitle(other, role)) {
                        continue;
                    }
                    replaced.add(other.UserId);
                    Change removal = uploadChange(ACTION_REMOVE, other.UserId, userNamesCache.get(other.UserId), territory, other.RoleInTerritory2, effective);
                    removal.message = 'Replaced by ' + userNamesCache.get(userId) + '.';
                    plan.changes.add(removal);
                    preview.removeCount++;
                    addLine(preview, removal, 'Remove', today);
                }
            }
            for (Id userId : seat.removals.keySet()) {
                if (!current.containsKey(userId)) {
                    preview.unchangedCount++;
                    PreviewLine line = new PreviewLine();
                    line.key = String.valueOf(preview.lines.size());
                    line.action = 'No change';
                    line.territoryName = territory.Name;
                    line.territoryExternalId = territory.External_ID__c;
                    line.personName = userNamesCache.get(userId);
                    line.timing = '';
                    line.message = 'Not in this seat, nothing to remove.';
                    preview.lines.add(line);
                    continue;
                }
                UserTerritory2Association link = current.get(userId);
                Change change = uploadChange(ACTION_REMOVE, userId, userNamesCache.get(userId), territory, link.RoleInTerritory2, seat.removals.get(userId));
                plan.changes.add(change);
                preview.removeCount++;
                addLine(preview, change, 'Remove', today);
            }
        }

        if (releaseOtherSeats) {
            for (UserTerritory2Association link : otherSeatsOfSeated) {
                Set<String> fileSeats = fileSeatsByUser.get(link.UserId);
                if (!moveDateByUser.containsKey(link.UserId)
                        || (fileSeats != null && fileSeats.contains(link.Territory2.External_ID__c.toUpperCase()))) {
                    continue;
                }
                Territory2 territory = new Territory2(
                    Id = link.Territory2Id,
                    Name = link.Territory2.Name,
                    External_ID__c = link.Territory2.External_ID__c
                );
                Change change = uploadChange(
                    ACTION_REMOVE, link.UserId, userNamesCache.get(link.UserId), territory, link.RoleInTerritory2,
                    moveDateByUser.get(link.UserId)
                );
                change.message = 'Leaves this seat for the new one.';
                plan.changes.add(change);
                preview.removeCount++;
                addLine(preview, change, 'Remove', today);
            }
        }

        for (Change change : plan.changes) {
            if (change.effectiveDate != null && change.effectiveDate > today) {
                preview.scheduledCount++;
            }
        }
        return plan;
    }

    private static final Set<String> STRUCTURE_TYPES = new Set<String>{ 'Position', 'District', 'Other' };
    private static Map<Id, String> userNamesCache = new Map<Id, String>();

    /** Creates, renames and moves territories. Returns the External Ids of new positions that failed. */
    private static Set<String> applyStructure(List<StructureOp> ops, SubmitResult result) {
        Set<String> failed = new Set<String>();
        List<StructureOp> creates = new List<StructureOp>();
        List<StructureOp> updates = new List<StructureOp>();
        Set<String> parentExternalIds = new Set<String>();
        for (StructureOp op : ops) {
            if (op.kind == 'Create') {
                creates.add(op);
            } else if (op.kind == 'Rename' || op.kind == 'Move') {
                updates.add(op);
            }
            if (op.parentExternalId != null) {
                parentExternalIds.add(op.parentExternalId);
            }
        }
        if (creates.isEmpty() && updates.isEmpty()) {
            return failed;
        }
        Map<String, Territory2> known = new Map<String, Territory2>();
        for (Territory2 parent : [
            SELECT Id, External_ID__c, Territory2ModelId, Territory2TypeId, AccountAccessLevel, CaseAccessLevel,
                OpportunityAccessLevel
            FROM Territory2
            WHERE External_ID__c IN :parentExternalIds
            WITH SYSTEM_MODE
        ]) {
            known.put(parent.External_ID__c.toUpperCase(), parent);
        }

        // Parents before children: each pass creates the positions whose parent now exists.
        List<StructureOp> pending = creates.clone();
        while (!pending.isEmpty()) {
            List<Territory2> batch = new List<Territory2>();
            List<StructureOp> owners = new List<StructureOp>();
            List<StructureOp> waiting = new List<StructureOp>();
            for (StructureOp op : pending) {
                Territory2 parent = known.get(op.parentExternalId.toUpperCase());
                if (parent == null) {
                    waiting.add(op);
                    continue;
                }
                batch.add(new Territory2(
                    Name = op.name,
                    DeveloperName = developerNameFor(op.externalId),
                    External_ID__c = op.externalId,
                    Territory_Type__c = op.territoryType,
                    ParentTerritory2Id = parent.Id,
                    Territory2ModelId = parent.Territory2ModelId,
                    Territory2TypeId = parent.Territory2TypeId,
                    AccountAccessLevel = parent.AccountAccessLevel,
                    CaseAccessLevel = parent.CaseAccessLevel,
                    OpportunityAccessLevel = parent.OpportunityAccessLevel
                ));
                owners.add(op);
            }
            if (batch.isEmpty()) {
                for (StructureOp op : waiting) {
                    failed.add(op.externalId.toUpperCase());
                    result.failed++;
                    result.messages.add('New position ' + op.name + ': its parent ' + op.parentExternalId + ' was not created.');
                }
                break;
            }
            Database.SaveResult[] saved = Database.insert(batch, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saved.size(); i++) {
                StructureOp op = owners[i];
                if (saved[i].isSuccess()) {
                    known.put(op.externalId.toUpperCase(), batch[i]);
                    result.applied++;
                } else {
                    failed.add(op.externalId.toUpperCase());
                    result.failed++;
                    result.messages.add('New position ' + op.name + ': ' + saved[i].getErrors()[0].getMessage());
                }
            }
            pending = waiting;
        }

        Map<Id, Territory2> changedById = new Map<Id, Territory2>();
        Map<Id, List<StructureOp>> opsById = new Map<Id, List<StructureOp>>();
        for (StructureOp op : updates) {
            Id territoryId = op.territory.Id;
            Territory2 row = changedById.containsKey(territoryId) ? changedById.get(territoryId) : new Territory2(Id = territoryId);
            if (op.kind == 'Rename') {
                row.Name = op.name;
            } else {
                Territory2 parent = known.get(op.parentExternalId.toUpperCase());
                if (parent == null) {
                    result.failed++;
                    result.messages.add('Move ' + op.territory.Name + ': ' + op.parentExternalId + ' was not found.');
                    continue;
                }
                row.ParentTerritory2Id = parent.Id;
            }
            changedById.put(territoryId, row);
            if (!opsById.containsKey(territoryId)) {
                opsById.put(territoryId, new List<StructureOp>());
            }
            opsById.get(territoryId).add(op);
        }
        if (!changedById.isEmpty()) {
            List<Territory2> rows = changedById.values();
            Database.SaveResult[] saved = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < saved.size(); i++) {
                Integer count = opsById.get(rows[i].Id).size();
                if (saved[i].isSuccess()) {
                    result.applied += count;
                } else {
                    result.failed += count;
                    result.messages.add(opsById.get(rows[i].Id)[0].territory.Name + ': ' + saved[i].getErrors()[0].getMessage());
                }
            }
        }
        return failed;
    }

    /** Deletes removed positions after their holders are released, children before parents. */
    private static void applyRemovedPositions(List<StructureOp> ops, SubmitResult result) {
        for (String territoryType : new List<String>{ 'Position', 'Other', 'District' }) {
            List<Territory2> rows = new List<Territory2>();
            List<StructureOp> owners = new List<StructureOp>();
            for (StructureOp op : ops) {
                if (op.kind == 'Delete' && op.territoryType == territoryType) {
                    rows.add(new Territory2(Id = op.territory.Id));
                    owners.add(op);
                }
            }
            if (rows.isEmpty()) {
                continue;
            }
            Database.DeleteResult[] deleted = Database.delete(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < deleted.size(); i++) {
                if (deleted[i].isSuccess()) {
                    result.applied++;
                } else {
                    result.failed++;
                    result.messages.add('Remove ' + owners[i].name + ': ' + deleted[i].getErrors()[0].getMessage());
                }
            }
        }
    }

    private static StructureOp structureOp(String kind, Territory2 territory, String parentExternalId) {
        StructureOp op = new StructureOp();
        op.kind = kind;
        op.territory = territory;
        op.externalId = territory.External_ID__c;
        op.name = territory.Name;
        op.territoryType = territory.Territory_Type__c;
        op.parentExternalId = parentExternalId;
        return op;
    }

    private static void addStructureLine(UploadPreview preview, String label, Territory2 territory, String message) {
        PreviewLine line = new PreviewLine();
        line.key = String.valueOf(preview.lines.size());
        line.action = label;
        line.territoryName = territory.Name;
        line.territoryExternalId = territory.External_ID__c;
        line.timing = 'Now';
        line.effectiveDate = '';
        line.message = message;
        preview.lines.add(line);
    }

    /** Why the parent can't take this kind of territory, or null when it can. */
    private static String parentProblem(
        String territoryType, String parentExternalId, Map<String, Territory2> existing, Map<String, String> created
    ) {
        if (parentExternalId == null) {
            return 'Add the Parent External Id (the district, line or business unit it sits under).';
        }
        String key = parentExternalId.toUpperCase();
        String parentType = existing.containsKey(key) ? existing.get(key).Territory_Type__c : created.get(key);
        if (parentType == null && !existing.containsKey(key) && !created.containsKey(key)) {
            return 'No territory has Parent External Id ' + parentExternalId + '.';
        }
        Set<String> allowed = territoryType == 'Position'
            ? new Set<String>{ 'District' }
            : territoryType == 'District' ? new Set<String>{ 'Line' } : new Set<String>{ 'Line', 'Business_Unit' };
        if (!allowed.contains(parentType)) {
            return 'A ' + levelLabel(territoryType) + ' must sit under a '
                + (territoryType == 'Position' ? 'District' : territoryType == 'District' ? 'Line' : 'Line or Business Unit')
                + ', but ' + parentExternalId + ' is a ' + levelLabel(parentType) + '.';
        }
        return null;
    }

    private static Boolean removingInFile(Map<String, List<UploadRow>> rowsBySeat, Id territoryId) {
        List<UploadRow> seatRows = rowsBySeat.get(String.valueOf(territoryId));
        if (seatRows == null) {
            return false;
        }
        for (UploadRow row : seatRows) {
            if (isYes(row.remove) && !hasPerson(row)) {
                return true;
            }
        }
        return false;
    }

    /** Accounts aligned per territory (Account_Territory_Fields__c keeps the 18-character Territory Id). */
    private static Map<Id, Integer> alignedAccountCounts(Set<Id> territoryIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (territoryIds.isEmpty()) {
            return counts;
        }
        Set<String> keys = new Set<String>();
        for (Id territoryId : territoryIds) {
            keys.add(String.valueOf(territoryId));
        }
        for (AggregateResult row : [
            SELECT Territory2_Id__c territoryId, COUNT(Id) total
            FROM Account_Territory_Fields__c
            WHERE Territory2_Id__c IN :keys
            WITH SYSTEM_MODE
            GROUP BY Territory2_Id__c
        ]) {
            Id territoryId = toId((String) row.get('territoryId'), Territory2.SObjectType);
            if (territoryId != null) {
                counts.put(territoryId, (Integer) row.get('total'));
            }
        }
        return counts;
    }

    /** True when the holder already has this title here; an empty seat title counts as their job title. */
    private static Boolean holdsTitle(UserTerritory2Association link, String title) {
        if (equalsText(link.RoleInTerritory2, title)) {
            return true;
        }
        return String.isBlank(link.RoleInTerritory2)
            && (equalsText(link.User?.Title, title) || equalsText(defaultTitle(link.Territory2?.Territory_Type__c), title));
    }

    private static Boolean hasPerson(UploadRow row) {
        return row.holderUserId != null || row.holderUsername != null || row.employeeCode != null || row.holder != null;
    }

    private static Boolean isYes(String value) {
        return value != null && YES_VALUES.contains(value.trim().toLowerCase());
    }

    private static final Set<String> YES_VALUES = new Set<String>{ 'y', 'yes', 'true', '1', 'x', 'remove', 'delete' };

    /** Level column (as downloaded, or the picklist value) to Territory_Type__c. */
    @TestVisible
    private static String toTerritoryType(String level) {
        String value = level == null ? '' : level.trim().toLowerCase().replaceAll('[^a-z]', '');
        Map<String, String> types = new Map<String, String>{
            'position' => 'Position',
            'mr' => 'Position',
            'medicalrep' => 'Position',
            'district' => 'District',
            'marketingseat' => 'Other',
            'other' => 'Other',
            'line' => 'Line',
            'businessunit' => 'Business_Unit',
            'headoffice' => 'Head_Office'
        };
        return types.get(value);
    }

    private static String levelLabel(String territoryType) {
        return territoryType == 'Other' ? 'Marketing Seat'
            : territoryType == 'Business_Unit' ? 'Business Unit'
            : territoryType == 'Head_Office' ? 'Head Office'
            : territoryType;
    }

    /** TERR_POS_SALES_NEW_CAIRO style code, the same shape the organogram loader uses. */
    @TestVisible
    private static String newExternalId(String territoryType, String name) {
        String prefix = territoryType == 'District' ? 'DM' : territoryType == 'Other' ? 'BM' : 'POS';
        String slug = name.toUpperCase().replaceAll('[^A-Z0-9]+', '_').replaceAll('^_+|_+$', '');
        return ('TERR_' + prefix + '_' + slug).left(75).removeEnd('_');
    }

    /** DeveloperName is the External Id without TERR_: letters, digits and single underscores. */
    @TestVisible
    private static String developerNameFor(String externalId) {
        String value = externalId.toUpperCase().removeStart('TERR_').replaceAll('[^A-Z0-9_]', '_').replaceAll('_+', '_');
        value = value.replaceAll('^_+|_+$', '');
        if (String.isBlank(value) || !value.left(1).isAlpha()) {
            value = 'T_' + value;
        }
        return value.left(80).removeEnd('_');
    }

    private static Id toId(String value, Schema.SObjectType expected) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(value.trim());
            return parsed.getSObjectType() == expected ? parsed : null;
        } catch (Exception ex) {
            return null;
        }
    }

    private static Change uploadChange(String action, Id userId, String userName, Territory2 territory, String role, Date effective) {
        Change change = new Change();
        change.action = action;
        change.userId = userId;
        change.userName = userName;
        change.territoryExternalId = territory.External_ID__c;
        change.territoryName = territory.Name;
        change.role = role;
        change.effectiveDate = effective;
        change.source = SOURCE_UPLOAD;
        return change;
    }

    private static void addLine(UploadPreview preview, Change change, String label, Date today) {
        PreviewLine line = new PreviewLine();
        line.key = String.valueOf(preview.lines.size());
        line.action = label;
        line.territoryName = change.territoryName;
        line.territoryExternalId = change.territoryExternalId;
        line.personName = change.userName;
        line.role = change.role;
        line.effectiveDate = change.effectiveDate == null ? '' : String.valueOf(change.effectiveDate);
        line.timing = change.effectiveDate != null && change.effectiveDate > today ? 'Scheduled' : 'Now';
        line.message = change.message;
        preview.lines.add(line);
    }

    private static void addError(UploadPreview preview, UploadRow row, Territory2 territory, String message) {
        preview.errorCount++;
        PreviewLine line = new PreviewLine();
        line.key = String.valueOf(preview.lines.size());
        line.action = 'Error';
        line.territoryName = territory == null ? null : territory.Name;
        line.territoryExternalId = row.territoryExternalId;
        line.personName = firstNonBlank(row.holder, row.holderUsername, row.employeeCode);
        line.role = row.title;
        line.effectiveDate = row.effectiveDate;
        line.timing = '';
        line.message = (row.rowNumber == null ? '' : 'Row ' + row.rowNumber + ': ') + message;
        preview.lines.add(line);
    }

    // ---------------------------------------------------------------- scheduled changes

    @AuraEnabled
    public static List<ScheduledRow> getScheduledChanges(Id userId) {
        List<ScheduledRow> rows = new List<ScheduledRow>();
        String status = STATUS_SCHEDULED;
        String soql =
            'SELECT Id, Name, User__c, User__r.Name, Action__c, Territory_Name__c, Territory_External_Id__c,'
            + ' Role__c, New_Title__c, Effective_Date__c, Source__c, Status__c, Message__c, Requested_By__r.Name'
            + ' FROM Seat_Change__c WHERE Status__c = :status'
            + (userId == null ? '' : ' AND User__c = :userId')
            + ' WITH SYSTEM_MODE ORDER BY Effective_Date__c ASC, Name ASC LIMIT 500';
        for (Seat_Change__c record : Database.query(soql)) {
            rows.add(toScheduledRow(record));
        }
        return rows;
    }

    @AuraEnabled
    public static List<ScheduledRow> getSeatHistory(Id userId) {
        List<ScheduledRow> rows = new List<ScheduledRow>();
        if (userId == null) {
            return rows;
        }
        for (Seat_Change__c record : [
            SELECT Id, Name, User__c, User__r.Name, Action__c, Territory_Name__c, Territory_External_Id__c,
                Role__c, New_Title__c, Effective_Date__c, Source__c, Status__c, Message__c, Requested_By__r.Name
            FROM Seat_Change__c
            WHERE User__c = :userId AND Status__c IN ('Applied', 'Failed')
            WITH SYSTEM_MODE
            ORDER BY Effective_Date__c DESC, Name DESC
            LIMIT 10
        ]) {
            rows.add(toScheduledRow(record));
        }
        return rows;
    }

    @AuraEnabled
    public static void cancelScheduledChange(Id changeId) {
        requireManageUsers();
        List<Seat_Change__c> records = [
            SELECT Id, Status__c
            FROM Seat_Change__c
            WHERE Id = :changeId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        if (records.isEmpty() || records[0].Status__c != STATUS_SCHEDULED) {
            throw new AuraHandledException('Only a scheduled change can be cancelled.');
        }
        records[0].Status__c = STATUS_CANCELLED;
        records[0].Message__c = 'Cancelled by ' + UserInfo.getName();
        update as system records;
    }

    /** Applies every Scheduled change whose date has come. Runs from SeatChangeJob. */
    public static Integer applyDueChanges() {
        List<Seat_Change__c> due = [
            SELECT Id, User__c, User__r.Name, Action__c, Territory_External_Id__c, Territory_Name__c, Role__c,
                New_Title__c, Release_Other_Seats__c, Replace_Same_Role__c, Effective_Date__c, Source__c
            FROM Seat_Change__c
            WHERE Status__c = :STATUS_SCHEDULED AND Effective_Date__c <= :Date.today()
            WITH SYSTEM_MODE
            ORDER BY Effective_Date__c ASC, Name ASC
            LIMIT 2000
        ];
        if (due.isEmpty()) {
            return 0;
        }
        List<Change> changes = new List<Change>();
        for (Seat_Change__c record : due) {
            Change change = new Change();
            change.recordId = record.Id;
            change.userId = record.User__c;
            change.userName = record.User__r?.Name;
            change.action = record.Action__c;
            change.territoryExternalId = record.Territory_External_Id__c;
            change.territoryName = record.Territory_Name__c;
            change.role = record.Role__c;
            change.newTitle = record.New_Title__c;
            change.releaseOtherSeats = record.Release_Other_Seats__c;
            change.replaceSameRole = record.Replace_Same_Role__c;
            change.effectiveDate = record.Effective_Date__c;
            change.source = record.Source__c;
            changes.add(change);
        }
        applyNow(changes);
        logLater(toRecords(changes));
        return changes.size();
    }

    // ---------------------------------------------------------------- engine

    @TestVisible
    private static SubmitResult submit(List<Change> changes) {
        return submit(changes, false);
    }

    /** queueLog: write the log rows from a queueable even when nothing is due (setup DML already ran). */
    private static SubmitResult submit(List<Change> changes, Boolean queueLog) {
        SubmitResult result = new SubmitResult();
        Date today = Date.today();
        List<Change> due = new List<Change>();
        for (Change change : changes) {
            if (change.effectiveDate == null || change.effectiveDate <= today) {
                due.add(change);
            } else {
                change.status = STATUS_SCHEDULED;
                result.scheduled++;
            }
        }
        applyNow(due);
        for (Change change : due) {
            if (change.status == STATUS_APPLIED) {
                result.applied++;
            } else {
                result.failed++;
                result.messages.add(change.userName + ' → ' + change.territoryName + ': ' + change.message);
            }
        }
        List<Seat_Change__c> records = toRecords(changes);
        if (due.isEmpty() && !queueLog) {
            insert as system records;
        } else {
            logLater(records);
        }
        return result;
    }

    private static void logLater(List<Seat_Change__c> records) {
        if (records.isEmpty()) {
            return;
        }
        if (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
            System.enqueueJob(new SeatChangeLogJob(records));
        }
    }

    /**
     * Changes seats and job titles now. Setup-object DML only. Sets status and message on each change.
     */
    @TestVisible
    private static void applyNow(List<Change> changes) {
        if (changes.isEmpty()) {
            return;
        }
        Set<Id> userIds = new Set<Id>();
        Set<String> externalIds = new Set<String>();
        for (Change change : changes) {
            if (change.userId != null) {
                userIds.add(change.userId);
            }
            if (String.isNotBlank(change.territoryExternalId)) {
                externalIds.add(change.territoryExternalId);
            }
        }
        Map<String, Territory2> territoryByExternal = new Map<String, Territory2>();
        for (Territory2 territory : [
            SELECT Id, Name, External_ID__c
            FROM Territory2
            WHERE External_ID__c IN :externalIds
            WITH SYSTEM_MODE
        ]) {
            territoryByExternal.put(territory.External_ID__c.toUpperCase(), territory);
        }
        Set<Id> territoryIds = new Set<Id>();
        for (Territory2 territory : territoryByExternal.values()) {
            territoryIds.add(territory.Id);
        }

        Map<String, UserTerritory2Association> linkByKey = new Map<String, UserTerritory2Association>();
        Map<Id, List<UserTerritory2Association>> linksByUser = new Map<Id, List<UserTerritory2Association>>();
        Map<Id, List<UserTerritory2Association>> linksBySeat = new Map<Id, List<UserTerritory2Association>>();
        for (UserTerritory2Association link : [
            SELECT Id, UserId, Territory2Id, Territory2.Name, Territory2.External_ID__c, RoleInTerritory2
            FROM UserTerritory2Association
            WHERE UserId IN :userIds OR Territory2Id IN :territoryIds
            WITH SYSTEM_MODE
        ]) {
            linkByKey.put(key(link.UserId, link.Territory2Id), link);
            if (!linksByUser.containsKey(link.UserId)) {
                linksByUser.put(link.UserId, new List<UserTerritory2Association>());
            }
            linksByUser.get(link.UserId).add(link);
            if (!linksBySeat.containsKey(link.Territory2Id)) {
                linksBySeat.put(link.Territory2Id, new List<UserTerritory2Association>());
            }
            linksBySeat.get(link.Territory2Id).add(link);
        }

        Map<Id, UserTerritory2Association> toDelete = new Map<Id, UserTerritory2Association>();
        Map<Id, UserTerritory2Association> toUpdate = new Map<Id, UserTerritory2Association>();
        Map<String, UserTerritory2Association> toInsert = new Map<String, UserTerritory2Association>();
        Map<Id, User> userUpdates = new Map<Id, User>();
        Map<String, List<Change>> ownersByDmlKey = new Map<String, List<Change>>();

        for (Change change : changes) {
            change.status = STATUS_APPLIED;
            change.previousSeats = describeSeats(linksByUser.get(change.userId));
            Territory2 territory = change.territoryExternalId == null
                ? null
                : territoryByExternal.get(change.territoryExternalId.toUpperCase());
            if (change.userId == null || territory == null) {
                change.status = STATUS_FAILED;
                change.message = territory == null ? 'Territory ' + change.territoryExternalId + ' no longer exists.' : 'Person is missing.';
                continue;
            }
            change.territoryName = territory.Name;
            String pair = key(change.userId, territory.Id);

            if (change.action == ACTION_REMOVE) {
                UserTerritory2Association link = linkByKey.get(pair);
                toInsert.remove(pair);
                if (link == null) {
                    change.message = appendMessage(change.message, 'Was not in this seat.');
                    continue;
                }
                toUpdate.remove(link.Id);
                toDelete.put(link.Id, link);
                own(ownersByDmlKey, 'd' + link.Id, change);
                continue;
            }

            List<String> replaced = new List<String>();
            if (change.replaceSameRole == true && linksBySeat.containsKey(territory.Id)) {
                for (UserTerritory2Association link : linksBySeat.get(territory.Id)) {
                    if (link.UserId != change.userId && equalsText(link.RoleInTerritory2, change.role)) {
                        toDelete.put(link.Id, link);
                        own(ownersByDmlKey, 'd' + link.Id, change);
                        replaced.add(link.UserId);
                    }
                }
            }
            if (change.releaseOtherSeats == true && linksByUser.containsKey(change.userId)) {
                for (UserTerritory2Association link : linksByUser.get(change.userId)) {
                    if (link.Territory2Id != territory.Id && isOrganogramSeat(link.Territory2.External_ID__c)) {
                        toDelete.put(link.Id, link);
                        own(ownersByDmlKey, 'd' + link.Id, change);
                    }
                }
            }
            UserTerritory2Association current = linkByKey.get(pair);
            if (current != null) {
                toDelete.remove(current.Id);
                if (!equalsText(current.RoleInTerritory2, change.role)) {
                    toUpdate.put(current.Id, new UserTerritory2Association(Id = current.Id, RoleInTerritory2 = change.role));
                    own(ownersByDmlKey, 'u' + current.Id, change);
                } else if (String.isBlank(change.newTitle) && replaced.isEmpty()) {
                    change.message = appendMessage(change.message, 'Already in this seat.');
                }
            } else {
                toInsert.put(
                    pair,
                    new UserTerritory2Association(UserId = change.userId, Territory2Id = territory.Id, RoleInTerritory2 = change.role)
                );
                own(ownersByDmlKey, 'i' + pair, change);
            }
            if (!replaced.isEmpty()) {
                change.message = appendMessage(change.message, 'Replaced ' + replaced.size() + ' holder(s) of ' + change.role + '.');
            }
            if (String.isNotBlank(change.newTitle)) {
                userUpdates.put(change.userId, new User(Id = change.userId, Title = change.newTitle));
                own(ownersByDmlKey, 't' + change.userId, change);
            }
        }

        if (!toDelete.isEmpty()) {
            List<UserTerritory2Association> rows = toDelete.values();
            Database.DeleteResult[] results = Database.delete(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    fail(ownersByDmlKey.get('d' + rows[i].Id), results[i].getErrors()[0].getMessage());
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            List<UserTerritory2Association> rows = toUpdate.values();
            Database.SaveResult[] results = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    fail(ownersByDmlKey.get('u' + rows[i].Id), results[i].getErrors()[0].getMessage());
                }
            }
        }
        if (!toInsert.isEmpty()) {
            List<String> keys = new List<String>(toInsert.keySet());
            List<UserTerritory2Association> rows = new List<UserTerritory2Association>();
            for (String pairKey : keys) {
                rows.add(toInsert.get(pairKey));
            }
            Database.SaveResult[] results = Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    fail(ownersByDmlKey.get('i' + keys[i]), results[i].getErrors()[0].getMessage());
                }
            }
        }
        if (!userUpdates.isEmpty()) {
            List<User> rows = userUpdates.values();
            Database.SaveResult[] results = Database.update(rows, false, AccessLevel.SYSTEM_MODE);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    fail(ownersByDmlKey.get('t' + rows[i].Id), 'Title not updated: ' + results[i].getErrors()[0].getMessage());
                }
            }
        }
    }

    private static void own(Map<String, List<Change>> owners, String dmlKey, Change change) {
        if (!owners.containsKey(dmlKey)) {
            owners.put(dmlKey, new List<Change>());
        }
        owners.get(dmlKey).add(change);
    }

    private static void fail(List<Change> owners, String message) {
        if (owners == null) {
            return;
        }
        for (Change change : owners) {
            change.status = STATUS_FAILED;
            change.message = appendMessage(change.message, message);
        }
    }

    private static List<Seat_Change__c> toRecords(List<Change> changes) {
        List<Seat_Change__c> records = new List<Seat_Change__c>();
        Datetime now = Datetime.now();
        for (Change change : changes) {
            Seat_Change__c record = new Seat_Change__c(Id = change.recordId);
            if (change.recordId == null) {
                record.User__c = change.userId;
                record.Action__c = change.action;
                record.Territory_External_Id__c = change.territoryExternalId;
                record.Role__c = truncate(change.role, 80);
                record.New_Title__c = truncate(change.newTitle, 80);
                record.Release_Other_Seats__c = change.releaseOtherSeats == true;
                record.Replace_Same_Role__c = change.replaceSameRole == true;
                record.Effective_Date__c = change.effectiveDate == null ? Date.today() : change.effectiveDate;
                record.Source__c = change.source;
                record.Requested_By__c = UserInfo.getUserId();
            }
            record.Territory_Name__c = truncate(change.territoryName, 255);
            record.Status__c = change.status;
            record.Message__c = truncate(change.message, 255);
            if (change.status == STATUS_APPLIED || change.status == STATUS_FAILED) {
                record.Applied_On__c = now;
                record.Previous_Seats__c = truncate(change.previousSeats, 4000);
            }
            records.add(record);
        }
        return records;
    }

    private static ScheduledRow toScheduledRow(Seat_Change__c record) {
        ScheduledRow row = new ScheduledRow();
        row.id = record.Id;
        row.name = record.Name;
        row.userId = record.User__c;
        row.userName = record.User__r?.Name;
        row.action = record.Action__c;
        row.territoryName = record.Territory_Name__c;
        row.territoryExternalId = record.Territory_External_Id__c;
        row.role = record.Role__c;
        row.newTitle = record.New_Title__c;
        row.effectiveDate = record.Effective_Date__c;
        row.source = record.Source__c;
        row.status = record.Status__c;
        row.message = record.Message__c;
        row.requestedBy = record.Requested_By__r?.Name;
        return row;
    }

    // ---------------------------------------------------------------- helpers

    /** Same rule as the Users tab: changing logins, titles and seats needs Manage Users. */
    public static void requireManageUsers() {
        List<PermissionSetAssignment> grants = [
            SELECT Id
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
              AND PermissionSet.PermissionsManageUsers = true
            LIMIT 1
        ];
        if (grants.isEmpty()) {
            throw new AuraHandledException('You need the Manage Users permission to change seats and titles.');
        }
    }

    public static Boolean isOrganogramSeat(String externalId) {
        return String.isNotBlank(externalId) && externalId.startsWith('TERR_') && !externalId.contains('TRAINING');
    }

    /** Title used for a seat when the file or the form leaves it empty. */
    public static String defaultTitle(String territoryType) {
        if (territoryType == 'Business_Unit') {
            return 'Business Unit Manager';
        }
        if (territoryType == 'Line') {
            return 'National Sales Manager';
        }
        if (territoryType == 'District') {
            return 'District Manager';
        }
        return 'Medical Rep';
    }

    @TestVisible
    private static Date parseDate(String raw) {
        String value = clean(raw);
        if (value == null) {
            return null;
        }
        try {
            if (Pattern.matches('\\d{4}-\\d{1,2}-\\d{1,2}.*', value)) {
                List<String> parts = value.substring(0, Math.min(10, value.length())).split('-');
                return safeDate(Integer.valueOf(parts[0]), Integer.valueOf(parts[1]), Integer.valueOf(parts[2].left(2)));
            }
            if (Pattern.matches('\\d{1,2}[/.-]\\d{1,2}[/.-]\\d{4}', value)) {
                // Egypt writes day first: 01/11/2026 is 1 November.
                List<String> parts = value.split('[/.-]');
                return safeDate(Integer.valueOf(parts[2]), Integer.valueOf(parts[1]), Integer.valueOf(parts[0]));
            }
        } catch (Exception ex) {
            return null;
        }
        return null;
    }

    private static Date safeDate(Integer year, Integer month, Integer day) {
        if (month < 1 || month > 12 || day < 1 || day > Date.daysInMonth(year, month)) {
            return null;
        }
        return Date.newInstance(year, month, day);
    }

    private static String describeSeats(List<UserTerritory2Association> links) {
        if (links == null || links.isEmpty()) {
            return 'No seat';
        }
        List<String> parts = new List<String>();
        for (UserTerritory2Association link : links) {
            parts.add(link.Territory2.Name + (String.isBlank(link.RoleInTerritory2) ? '' : ' (' + link.RoleInTerritory2 + ')'));
        }
        return String.join(parts, '; ');
    }

    private static String clean(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static String firstNonBlank(String a, String b, String c) {
        return String.isNotBlank(a) ? a : String.isNotBlank(b) ? b : c;
    }

    private static Boolean equalsText(String left, String right) {
        return (String.isBlank(left) ? '' : left.trim().toLowerCase()) == (String.isBlank(right) ? '' : right.trim().toLowerCase());
    }

    private static String appendMessage(String current, String extra) {
        return String.isBlank(current) ? extra : current + ' ' + extra;
    }

    private static String truncate(String value, Integer size) {
        return value == null || value.length() <= size ? value : value.left(size);
    }

    private static String key(Id userId, Id territoryId) {
        return String.valueOf(userId) + ':' + String.valueOf(territoryId);
    }
}
