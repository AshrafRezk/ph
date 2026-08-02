/**
 * Distributes demo visits across working days with realistic gaps and durations.
 */
public without sharing class DemoVisitTimingHelper {

    public class VisitSlot {
        public Date visitDay;
        public DateTime startDateTime;
        public DateTime endDateTime;
        public Integer slotIndex;
    }

    private static final Integer DEFAULT_VISIT_DURATION_MINUTES = 45;
    private static final Integer GAP_BETWEEN_VISITS_MINUTES = 25;
    private static final Integer WORKDAY_START_MINUTES = (8 * 60) + 30;
    private static final Integer WORKDAY_WINDOW_MINUTES = 9 * 60;

    public static VisitSlot buildSlot(List<Date> workingDays, Integer globalIndex) {
        return buildSlot(workingDays, globalIndex, DEFAULT_VISIT_DURATION_MINUTES);
    }

    public static VisitSlot buildSeedSlot(List<Date> workingDays, Integer globalIndex, Integer callCount) {
        Integer duration = DEFAULT_VISIT_DURATION_MINUTES;
        Integer gap = GAP_BETWEEN_VISITS_MINUTES;
        if (callCount != null && workingDays != null && !workingDays.isEmpty()) {
            Integer capacity = workingDays.size() * maxSlotsPerDay(duration, gap);
            if (callCount > capacity) {
                duration = 30;
                gap = 15;
                capacity = workingDays.size() * maxSlotsPerDay(duration, gap);
            }
            if (callCount > capacity) {
                duration = 25;
                gap = 10;
            }
        }
        return buildSlot(workingDays, globalIndex, duration, gap);
    }

    public static VisitSlot buildSlot(List<Date> workingDays, Integer globalIndex, Integer durationMinutes) {
        return buildSlot(workingDays, globalIndex, durationMinutes, GAP_BETWEEN_VISITS_MINUTES);
    }

    public static VisitSlot buildSlot(
        List<Date> workingDays,
        Integer globalIndex,
        Integer durationMinutes,
        Integer gapMinutes
    ) {
        if (workingDays == null || workingDays.isEmpty() || globalIndex == null || globalIndex < 0) {
            return null;
        }

        Integer dayCount = workingDays.size();
        Integer dayIndex = Math.mod(globalIndex, dayCount);
        Integer visitOnDay = globalIndex / dayCount;
        Integer slotSpacing = durationMinutes + gapMinutes;
        Integer latestStart = WORKDAY_START_MINUTES + WORKDAY_WINDOW_MINUTES - durationMinutes;
        Integer startMinute = WORKDAY_START_MINUTES + (visitOnDay * slotSpacing);

        while (startMinute > latestStart) {
            visitOnDay--;
            if (visitOnDay < 0) {
                dayIndex = Math.mod(dayIndex + 1, dayCount);
                visitOnDay = 0;
            }
            startMinute = WORKDAY_START_MINUTES + (visitOnDay * slotSpacing);
        }

        Integer jitter = Math.mod(globalIndex, 3) * 5;
        if (startMinute + jitter <= latestStart) {
            startMinute += jitter;
        }

        Date visitDay = workingDays[dayIndex];
        Integer hour = startMinute / 60;
        Integer minute = Math.mod(startMinute, 60);
        DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(hour, minute, 0, 0));

        VisitSlot slot = new VisitSlot();
        slot.visitDay = visitDay;
        slot.startDateTime = startDt;
        slot.endDateTime = startDt.addMinutes(durationMinutes);
        slot.slotIndex = globalIndex;
        return slot;
    }

    public static VisitSlot buildSlotOnDay(Date visitDay, Integer visitOnDay, Integer globalIndex) {
        return buildSlotOnDay(visitDay, visitOnDay, globalIndex, DEFAULT_VISIT_DURATION_MINUTES);
    }

    public static VisitSlot buildSlotOnDay(
        Date visitDay,
        Integer visitOnDay,
        Integer globalIndex,
        Integer durationMinutes
    ) {
        if (visitDay == null || visitOnDay == null || visitOnDay < 0) {
            return null;
        }

        Integer slotSpacing = durationMinutes + GAP_BETWEEN_VISITS_MINUTES;
        Integer latestStart = WORKDAY_START_MINUTES + WORKDAY_WINDOW_MINUTES - durationMinutes;
        Integer startMinute = WORKDAY_START_MINUTES + (visitOnDay * slotSpacing);
        if (startMinute > latestStart) {
            startMinute = latestStart;
        }

        Integer hour = startMinute / 60;
        Integer minute = Math.mod(startMinute, 60);
        DateTime startDt = DateTime.newInstance(visitDay, Time.newInstance(hour, minute, 0, 0));

        VisitSlot slot = new VisitSlot();
        slot.visitDay = visitDay;
        slot.startDateTime = startDt;
        slot.endDateTime = startDt.addMinutes(durationMinutes);
        slot.slotIndex = globalIndex == null ? visitOnDay : globalIndex;
        return slot;
    }

    private static Integer maxSlotsPerDay(Integer durationMinutes, Integer gapMinutes) {
        Integer latestStart = WORKDAY_START_MINUTES + WORKDAY_WINDOW_MINUTES - durationMinutes;
        Integer slotSpacing = durationMinutes + gapMinutes;
        if (slotSpacing <= 0) {
            return 1;
        }
        return Integer.valueOf(Math.floor((latestStart - WORKDAY_START_MINUTES) / slotSpacing)) + 1;
    }
}
