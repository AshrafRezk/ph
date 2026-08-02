// Seed planner data for Amr Salah (Diabetes MR)
// Org TODAY = 2026-06-21 (Sun); planner week Sun Jun 21 – Sat Jun 27
Id repId = '005Hu00000V6HOyIAN';

Date weekStart = Date.newInstance(2026, 6, 21);
Date weekEnd = Date.newInstance(2026, 6, 27);

// Guard: skip if data already exists
Integer existingVisits = [
    SELECT COUNT()
    FROM Visit__c
    WHERE Assigned_To__c = :repId
      AND Start_Date__c >= :DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0))
      AND Start_Date__c < :DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0))
];
Integer existingTots = [
    SELECT COUNT()
    FROM Time_Off_Request__c
    WHERE (OwnerId = :repId OR CreatedById = :repId)
      AND Start_Date_Time__c >= :DateTime.newInstance(weekStart, Time.newInstance(0, 0, 0, 0))
      AND Start_Date_Time__c < :DateTime.newInstance(weekEnd.addDays(1), Time.newInstance(0, 0, 0, 0))
];
if (existingVisits > 0 || existingTots > 0) {
    System.debug('SKIP: Found ' + existingVisits + ' visits and ' + existingTots + ' TOTs for this week.');
    return;
}

Map<String, Id> acctByName = new Map<String, Id>();
for (Account a : [
    SELECT Id, Name FROM Account
    WHERE Id IN (
        SELECT ObjectId FROM ObjectTerritory2Association
        WHERE Territory2Id = '0MIHu000000pqWQOAY'
    )
    ORDER BY Name
]) {
    acctByName.put(a.Name, a.Id);
}

List<Visit__c> visits = new List<Visit__c>();

Visit__c makeVisit(Date d, Integer h, Integer m, Id acctId, String status, String notes) {
    DateTime startDt = DateTime.newInstance(d, Time.newInstance(h, m, 0, 0));
    Visit__c v = new Visit__c(
        Account__c = acctId,
        Assigned_To__c = repId,
        Visit_Date__c = startDt,
        Start_Date__c = startDt,
        End_Date__c = startDt.addMinutes(45),
        Status__c = status,
        Visit_Type__c = 'Planned (Automatically)',
        Visit_Objective__c = 'Territory call — discuss aligned diabetes products.',
        Visit_Notes__c = notes,
        Next_Visit_Date__c = d.addDays(14)
    );
    return v;
}

// Sunday Jun 21 (org today) — executed / completed visits
visits.add(makeVisit(weekStart, 8, 0, acctByName.get('Yasmine Farouk'), 'Completed', 'Visit completed successfully.'));
visits.add(makeVisit(weekStart, 10, 0, acctByName.get('Tarek Nasser'), 'Completed', 'Visit completed successfully.'));
visits.add(makeVisit(weekStart, 14, 0, acctByName.get('Rania Mansour'), 'Completed', 'Visit completed successfully.'));

// Monday Jun 22 — scheduled
Date mon = weekStart.addDays(1);
visits.add(makeVisit(mon, 9, 0, acctByName.get('Khaled Saad'), 'Scheduled', null));
visits.add(makeVisit(mon, 11, 0, acctByName.get('Dina Khalil'), 'Scheduled', null));
visits.add(makeVisit(mon, 14, 30, acctByName.get('Omar Fahmy'), 'Scheduled', null));

// Tuesday Jun 23 — scheduled
Date tue = weekStart.addDays(2);
visits.add(makeVisit(tue, 9, 0, acctByName.get('Mahmoud Bekheet'), 'Scheduled', null));
visits.add(makeVisit(tue, 10, 30, acctByName.get('Salma Rizk'), 'Scheduled', null));
visits.add(makeVisit(tue, 15, 0, acctByName.get('Yasmine Farouk'), 'Scheduled', null));

// Thursday Jun 25 — scheduled (Wed is training TOT full day)
Date thu = weekStart.addDays(4);
visits.add(makeVisit(thu, 8, 30, acctByName.get('Khaled Saad'), 'Scheduled', null));
visits.add(makeVisit(thu, 11, 0, acctByName.get('Tarek Nasser'), 'Scheduled', null));

// Friday Jun 26 — scheduled
Date fri = weekStart.addDays(5);
visits.add(makeVisit(fri, 9, 0, acctByName.get('Rania Mansour'), 'Scheduled', null));
visits.add(makeVisit(fri, 10, 30, acctByName.get('Dina Khalil'), 'Scheduled', null));
visits.add(makeVisit(fri, 14, 0, acctByName.get('Omar Fahmy'), 'Scheduled', null));

// Saturday Jun 27 — scheduled
Date sat = weekStart.addDays(6);
visits.add(makeVisit(sat, 10, 0, acctByName.get('Mahmoud Bekheet'), 'Scheduled', null));
visits.add(makeVisit(sat, 11, 30, acctByName.get('Salma Rizk'), 'Draft', null));

insert visits;
System.debug('Inserted ' + visits.size() + ' visits for Amr Salah.');

List<Time_Off_Request__c> tots = new List<Time_Off_Request__c>();

// TOTs created as Draft with OwnerId = Amr (planner shows Draft/Approved stages).
// Times chosen to avoid overlap with admin-created TOTs (overlap checks CreatedById).
DateTime sunTotStart = DateTime.newInstance(weekStart, Time.newInstance(16, 0, 0, 0));
tots.add(new Time_Off_Request__c(
    OwnerId = repId,
    Type__c = 'Training',
    Span_Type__c = 'Hours',
    Span_Duration_Select__c = '2',
    Span_Duration__c = 2,
    Start_Date_Time__c = sunTotStart,
    End_Date_Time__c = sunTotStart.addHours(2),
    Comments__c = 'Product update webinar — Empacoza deck refresh.',
    Stage__c = 'Draft'
));

DateTime tueTotStart = DateTime.newInstance(tue, Time.newInstance(13, 0, 0, 0));
tots.add(new Time_Off_Request__c(
    OwnerId = repId,
    Type__c = 'Sick Leave',
    Span_Type__c = 'Hours',
    Span_Duration_Select__c = '3',
    Span_Duration__c = 3,
    Start_Date_Time__c = tueTotStart,
    End_Date_Time__c = tueTotStart.addHours(3),
    Comments__c = 'Medical appointment — afternoon off.',
    Stage__c = 'Draft'
));

DateTime friTotStart = DateTime.newInstance(fri, Time.newInstance(9, 0, 0, 0));
tots.add(new Time_Off_Request__c(
    OwnerId = repId,
    Type__c = 'Training',
    Span_Type__c = 'Hours',
    Span_Duration_Select__c = '3',
    Span_Duration__c = 3,
    Start_Date_Time__c = friTotStart,
    End_Date_Time__c = friTotStart.addHours(3),
    Comments__c = 'Diabetes therapy area training session.',
    Stage__c = 'Draft'
));

DateTime satTotStart = DateTime.newInstance(sat, Time.newInstance(14, 0, 0, 0));
tots.add(new Time_Off_Request__c(
    OwnerId = repId,
    Type__c = 'Event',
    Span_Type__c = 'Hours',
    Span_Duration_Select__c = '3',
    Span_Duration__c = 3,
    Start_Date_Time__c = satTotStart,
    End_Date_Time__c = satTotStart.addHours(3),
    Comments__c = 'Regional diabetes congress — booth duty.',
    Stage__c = 'Draft'
));

insert tots;
System.debug('Inserted ' + tots.size() + ' TOT blocks for Amr Salah.');

// Log created visit names
for (Visit__c v : [
    SELECT Name, Status__c, Start_Date__c, Account__r.Name
    FROM Visit__c WHERE Id IN :visits ORDER BY Start_Date__c
]) {
    System.debug('VISIT|' + v.Name + '|' + v.Start_Date__c.format('yyyy-MM-dd HH:mm') + '|' + v.Status__c + '|' + v.Account__r.Name);
}
for (Time_Off_Request__c t : [
    SELECT Name, Type__c, Stage__c, Span_Type__c, Start_Date_Time__c, End_Date_Time__c
    FROM Time_Off_Request__c WHERE Id IN :tots ORDER BY Start_Date_Time__c
]) {
    System.debug('TOT|' + t.Name + '|' + t.Start_Date_Time__c.format('yyyy-MM-dd HH:mm') + '|' + t.Type__c + '|' + t.Stage__c + '|' + t.Span_Type__c);
}
