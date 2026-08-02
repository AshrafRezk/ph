Date weekStart = Date.today().toStartOfWeek();
Date weekEnd = weekStart.addDays(13);
List<Visit__c> visits = [
  SELECT Assigned_To__r.Username, Products_Discussed__c, Status__c, Start_Date__c, End_Date__c,
    (SELECT Product2__r.Name, Product2__r.External_ID__c FROM Visit_Product_Details__r)
  FROM Visit__c
  WHERE Assigned_To__r.Username LIKE '%@pharma.demo'
    AND Visit_Date__c >= :weekStart AND Visit_Date__c < :weekEnd.addDays(1)
];
Map<String, Integer> byUser = new Map<String, Integer>();
Map<Id, List<Visit__c>> byRep = new Map<Id, List<Visit__c>>();
Integer overlaps = 0; Integer mismatch = 0; Integer chem = 0;
for (Visit__c v : visits) {
  String u = v.Assigned_To__r.Username;
  byUser.put(u, byUser.containsKey(u) ? byUser.get(u) + 1 : 1);
  if (!byRep.containsKey(v.Assigned_To__c)) byRep.put(v.Assigned_To__c, new List<Visit__c>());
  byRep.get(v.Assigned_To__c).add(v);
  if (v.Visit_Product_Details__r != null) {
    for (Visit_Product_Detail__c d : v.Visit_Product_Details__r) {
      String ext = d.Product2__r.External_ID__c;
      if (ext != null && (ext.startsWith('CPI_') || ext.startsWith('SOUL_'))) chem++;
      if (v.Products_Discussed__c != null && !v.Products_Discussed__c.contains(d.Product2__r.Name)) {
        mismatch++;
      }
    }
  }
}
for (Id repId : byRep.keySet()) {
  List<Visit__c> listV = byRep.get(repId);
  for (Integer i = 0; i < listV.size(); i++) {
    for (Integer j = i + 1; j < listV.size(); j++) {
      Visit__c a = listV[i]; Visit__c b = listV[j];
      if (a.Start_Date__c != null && a.End_Date__c != null && b.Start_Date__c != null && b.End_Date__c != null
          && a.Start_Date__c < b.End_Date__c && b.Start_Date__c < a.End_Date__c) overlaps++;
    }
  }
}
for (String u : byUser.keySet()) System.debug(u + '=' + byUser.get(u));
System.debug('TOTAL=' + visits.size() + ' OVERLAPS=' + overlaps + ' CHEM_DETAIL_ROWS=' + chem + ' NAME_MISMATCHES=' + mismatch);
Set<String> seen = new Set<String>();
for (Visit__c v : visits) {
  if (seen.contains(v.Assigned_To__r.Username)) continue;
  if (v.Visit_Product_Details__r == null || v.Visit_Product_Details__r.isEmpty()) continue;
  seen.add(v.Assigned_To__r.Username);
  System.debug('SAMPLE ' + v.Assigned_To__r.Username + ' discussed=' + v.Products_Discussed__c + ' detail=' + v.Visit_Product_Details__r[0].Product2__r.Name);
}
