const ALL_STATUS_OPTIONS = [
    { label: 'Draft', value: 'Draft' },
    { label: 'Scheduled', value: 'Scheduled' },
    { label: 'Completed', value: 'Completed' },
    { label: 'Cancelled', value: 'Cancelled' }
];

function startOfDay(date) {
    const copy = new Date(date);
    copy.setHours(0, 0, 0, 0);
    return copy;
}

export function isFutureVisitStart(startDateTime) {
    if (!startDateTime) {
        return false;
    }
    const visitDay = startOfDay(new Date(startDateTime));
    const today = startOfDay(new Date());
    return visitDay > today;
}

export function getVisitStatusOptions(startDateTime) {
    const future = isFutureVisitStart(startDateTime);
    return ALL_STATUS_OPTIONS.filter((option) => !(future && option.value === 'Completed'));
}

export function validateVisitStatusChange(status, startDateTime, cancellationReason) {
    if (status === 'Cancelled' && !(cancellationReason || '').trim()) {
        return 'Enter a cancellation reason.';
    }
    if (status === 'Completed' && isFutureVisitStart(startDateTime)) {
        return 'A visit cannot be completed before its scheduled date.';
    }
    return null;
}
