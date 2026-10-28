/**
 * Writes Seat_Change__c rows after their seat changes. Runs as its own transaction because the
 * transaction that changed UserTerritory2Association / User (setup objects) can't also write them.
 */
public without sharing class SeatChangeLogJob implements Queueable {
    private List<Seat_Change__c> records;

    public SeatChangeLogJob(List<Seat_Change__c> records) {
        this.records = records;
    }

    public void execute(QueueableContext context) {
        if (records == null || records.isEmpty()) {
            return;
        }
        Database.upsert(records, false, AccessLevel.SYSTEM_MODE);
    }
}
