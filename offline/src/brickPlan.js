const WORKING_DAYS = new Set([6, 0, 1, 2, 3]);
const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const WEEKDAY_WORDS = [
    { day: 0, names: ['sunday', 'sun'] },
    { day: 1, names: ['monday', 'mon'] },
    { day: 2, names: ['tuesday', 'tue', 'tues'] },
    { day: 3, names: ['wednesday', 'wed'] },
    { day: 4, names: ['thursday', 'thu', 'thur', 'thurs'], off: true },
    { day: 5, names: ['friday', 'fri'], off: true },
    { day: 6, names: ['saturday', 'sat'] }
];

export const SLOT_MINUTES = 60;
export const DAY_START_HOUR = 9;
export const DAY_END_HOUR = 17;
export const DEFAULT_DAILY_CAP = 8;

export function isHighClassification(value) {
    const raw = String(value || '')
        .trim()
        .toUpperCase()
        .replace(/^CLASS\s+/, '');
    return /^A(\d|\+)?$/.test(raw);
}

export function remainingVisitGap(account) {
    const target = Number(account && account.targetVisits);
    if (!Number.isFinite(target) || target <= 0) return 0;
    const actual = Number(account.actualVisits) || 0;
    const planned = Number(account.plannedVisits) || 0;
    return Math.max(0, target - actual - planned);
}

export function isWorkingDay(date) {
    return date instanceof Date && !Number.isNaN(date.getTime()) && WORKING_DAYS.has(date.getDay());
}

export function isoDate(date) {
    const pad = (n) => String(n).padStart(2, '0');
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

export function formatDayChip(date) {
    return `${DAY_LABELS[date.getDay()]} ${date.getDate()}`;
}

function parseDay(value) {
    if (value instanceof Date) return startOfDay(value);
    const match = String(value || '').match(/^(\d{4})-(\d{2})-(\d{2})/);
    if (match) return new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : startOfDay(parsed);
}

function startOfDay(date) {
    const d = new Date(date);
    d.setHours(0, 0, 0, 0);
    return d;
}

function addDays(date, days) {
    const d = new Date(date);
    d.setDate(d.getDate() + days);
    return d;
}

function norm(value) {
    return String(value || '')
        .toLowerCase()
        .replace(/[^\p{L}\p{N}]+/gu, ' ')
        .trim();
}

function brickIdentity(account) {
    if (account.brick702Id) {
        return {
            key: String(account.brick702Id),
            name: account.brick702Name || '702 brick',
            level: '702',
            zoneName: account.brick148Name || ''
        };
    }
    if (account.brick148Id) {
        return {
            key: String(account.brick148Id),
            name: account.brick148Name || 'Zone',
            level: '148',
            zoneName: ''
        };
    }
    if (account.brickId) {
        return {
            key: String(account.brickId),
            name: account.brickName || 'Brick',
            level: 'brick',
            zoneName: ''
        };
    }
    return null;
}

function normalizeAccount(account) {
    return {
        id: String((account && (account.id || account.accountId)) || ''),
        name: (account && (account.name || account.accountName)) || 'Account',
        classification: (account && account.classification) || '',
        targetVisits: Number(account && account.targetVisits) || 0,
        actualVisits: Number(account && account.actualVisits) || 0,
        plannedVisits: Number(account && account.plannedVisits) || 0,
        brick702Id: (account && account.brick702Id) || '',
        brick702Name: (account && account.brick702Name) || '',
        brick148Id: (account && account.brick148Id) || '',
        brick148Name: (account && account.brick148Name) || '',
        brickId: (account && account.brickId) || '',
        brickName: (account && account.brickName) || ''
    };
}

function needsAVisit(account) {
    const gap = remainingVisitGap(account);
    const high = isHighClassification(account.classification);
    if (gap > 0) return true;
    return high && !(Number(account.plannedVisits) > 0);
}

function accountScore(account) {
    if (!needsAVisit(account)) return -1;
    const gap = remainingVisitGap(account);
    const high = isHighClassification(account.classification);
    return gap * 10 + (high ? 50 : 0) + (gap > 0 && high ? 20 : 0);
}

export function brickSummaryLine(brick) {
    const bits = [];
    if (brick.zoneName && brick.zoneName !== brick.name) bits.push(brick.zoneName);
    bits.push(`${brick.targetCount} with target visits`);
    bits.push(`${brick.highCount} class A`);
    if (brick.openVisits) bits.push(`${brick.openVisits} still open`);
    return bits.join(' · ');
}

export function rankBricks(accounts, limit = 3) {
    const groups = new Map();
    (accounts || []).forEach((raw) => {
        const account = normalizeAccount(raw);
        if (!account.id) return;
        const identity = brickIdentity(account);
        if (!identity) return;
        let group = groups.get(identity.key);
        if (!group) {
            group = {
                ...identity,
                accounts: [],
                targetCount: 0,
                highCount: 0,
                openVisits: 0,
                score: 0
            };
            groups.set(identity.key, group);
        }
        group.accounts.push(account);
        if (account.targetVisits > 0) group.targetCount += 1;
        if (isHighClassification(account.classification)) group.highCount += 1;
        const gap = remainingVisitGap(account);
        if (gap > 0) group.openVisits += gap;
        const score = accountScore(account);
        if (score > 0) group.score += score;
    });

    const ranked = [...groups.values()]
        .filter((brick) => brick.targetCount > 0 || brick.highCount > 0)
        .map((brick) => ({
            ...brick,
            accounts: brick.accounts
                .filter((account) => accountScore(account) > 0)
                .sort((a, b) => accountScore(b) - accountScore(a) || a.name.localeCompare(b.name))
        }))
        .sort((a, b) => b.score - a.score || b.openVisits - a.openVisits || a.name.localeCompare(b.name));

    return {
        top: ranked.slice(0, limit),
        all: ranked
    };
}

function holidaySet(holidays) {
    const set = new Set();
    (holidays || []).forEach((value) => {
        const text = String(value || '').slice(0, 10);
        if (/^\d{4}-\d{2}-\d{2}$/.test(text)) set.add(text);
    });
    return set;
}

function fullDayOffSet(timeOff) {
    const set = new Set();
    (timeOff || []).forEach((block) => {
        if (!block) return;
        const full = block.isFullDay === true || /full/i.test(String(block.spanType || ''));
        if (!full || !block.startDateTime) return;
        const start = startOfDay(new Date(block.startDateTime));
        const end = block.endDateTime ? startOfDay(new Date(block.endDateTime)) : start;
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime())) return;
        const cursor = new Date(start);
        const last = end < start ? start : end;
        while (cursor <= last) {
            set.add(isoDate(cursor));
            cursor.setDate(cursor.getDate() + 1);
        }
    });
    return set;
}

export function remainingWorkingDays({ now = new Date(), weekStart, weekEnd, holidays, timeOff } = {}) {
    const start = parseDay(weekStart || now) || startOfDay(now);
    const end = parseDay(weekEnd) || addDays(start, 6);
    const today = startOfDay(now);
    const blocked = holidaySet(holidays);
    fullDayOffSet(timeOff).forEach((day) => blocked.add(day));
    const days = [];
    const cursor = new Date(start);
    while (cursor <= end) {
        const day = new Date(cursor);
        const iso = isoDate(day);
        if (day >= today && isWorkingDay(day) && !blocked.has(iso)) {
            days.push({ date: day, iso, label: formatDayChip(day) });
        }
        cursor.setDate(cursor.getDate() + 1);
    }
    return days;
}

function visitsOnDay(visits, iso) {
    return (visits || []).filter((visit) => {
        if (!visit || /cancel/i.test(String(visit.status || ''))) return false;
        const start = new Date(visit.startDateTime);
        return !Number.isNaN(start.getTime()) && isoDate(start) === iso;
    });
}

function overlaps(start, end, visits) {
    return visits.some((visit) => {
        const visitStart = new Date(visit.startDateTime);
        const visitEnd = visit.endDateTime
            ? new Date(visit.endDateTime)
            : new Date(visitStart.getTime() + SLOT_MINUTES * 60000);
        return start < visitEnd && end > visitStart;
    });
}

function nextFreeSlot(day, visits, now) {
    const taken = visitsOnDay(visits, isoDate(day));
    let cursor = new Date(day);
    cursor.setHours(DAY_START_HOUR, 0, 0, 0);
    if (isoDate(now) === isoDate(day) && now > cursor) {
        cursor = new Date(now);
        cursor.setMinutes(0, 0, 0);
        if (now.getMinutes() > 0 || now.getSeconds() > 0 || now.getMilliseconds() > 0) {
            cursor.setHours(cursor.getHours() + 1);
        }
        if (cursor.getHours() < DAY_START_HOUR) cursor.setHours(DAY_START_HOUR, 0, 0, 0);
    }
    const endLimit = new Date(day);
    endLimit.setHours(DAY_END_HOUR, 0, 0, 0);
    while (cursor < endLimit) {
        const slotEnd = new Date(cursor.getTime() + SLOT_MINUTES * 60000);
        if (slotEnd <= endLimit && !overlaps(cursor, slotEnd, taken)) {
            return { start: new Date(cursor), end: slotEnd };
        }
        cursor = new Date(cursor.getTime() + SLOT_MINUTES * 60000);
    }
    return null;
}

export function buildVisitSlots({ accounts, days, existingVisits, dailyCap = DEFAULT_DAILY_CAP, now = new Date() }) {
    const visits = [...(existingVisits || [])];
    const placed = [];
    const dayList = days || [];
    if (!dayList.length) return placed;
    let dayCursor = 0;
    (accounts || []).forEach((account) => {
        if (!account || !account.id) return;
        if (placed.some((slot) => slot.accountId === account.id)) return;
        for (let attempt = 0; attempt < dayList.length; attempt += 1) {
            const day = dayList[(dayCursor + attempt) % dayList.length];
            const already = visitsOnDay(visits, day.iso).length;
            if (already >= dailyCap) continue;
            if (visitsOnDay(visits, day.iso).some((visit) => String(visit.accountId || '') === account.id)) continue;
            const slot = nextFreeSlot(day.date, visits, now);
            if (!slot) continue;
            const drafted = {
                accountId: account.id,
                accountName: account.name,
                iso: day.iso,
                dayLabel: day.label,
                start: slot.start,
                end: slot.end,
                startDateTime: slot.start.toISOString(),
                endDateTime: slot.end.toISOString(),
                status: 'Draft'
            };
            visits.push(drafted);
            placed.push(drafted);
            dayCursor = (dayList.indexOf(day) + 1) % dayList.length;
            return;
        }
    });
    return placed;
}

function weekdayInWeek(dayIndex, weekStart) {
    const start = parseDay(weekStart) || startOfDay(new Date());
    for (let i = 0; i < 7; i += 1) {
        const date = addDays(start, i);
        if (date.getDay() === dayIndex) return date;
    }
    return null;
}

function matchWeekday(text, weekStart) {
    const found = WEEKDAY_WORDS.find((entry) => entry.names.some((name) => new RegExp(`\\b${name}\\b`, 'i').test(text)));
    if (!found) return null;
    return {
        off: Boolean(found.off),
        label: DAY_LABELS[found.day],
        date: weekdayInWeek(found.day, weekStart)
    };
}

function matchBrick(text, bricks) {
    const haystack = norm(text);
    if (!haystack) return null;
    let best = null;
    (bricks || []).forEach((brick) => {
        [brick.name, brick.zoneName].filter(Boolean).forEach((label) => {
            const needle = norm(label);
            if (needle.length < 3) return;
            if (haystack.includes(needle) && (!best || needle.length > best.length)) {
                best = { brick, length: needle.length };
            }
        });
    });
    return best ? best.brick : null;
}

function isPlanCommand(text) {
    const q = String(text || '').trim().toLowerCase();
    if (/\b(which|what|who|where|recommend|should i)\b/.test(q)) return false;
    return /^(plan|schedule|book)\b/.test(q) || /\b(plan|schedule|book)\b/.test(q);
}

export function parsePlanRequest(text, session) {
    if (!session || !isPlanCommand(text)) return null;
    const q = String(text || '').trim().toLowerCase();
    const bricks = session.bricks || [];
    const top = bricks.slice(0, 3);
    let brick = matchBrick(q, bricks);
    if (!brick && /\btop brick\b/.test(q) && top[0]) brick = top[0];
    const wantsDay = /\b(a day|one day|selected day)\b/.test(q);
    if (!brick) {
        if (!top.length) {
            return { clarify: 'No brick stands out yet. I look for accounts with target visits still open, or class A accounts.' };
        }
        return {
            clarify: wantsDay
                ? `Which brick should I plan for one day? I would start with ${top.map((row) => row.name).join(', ')}.`
                : `Which brick should I plan? I would start with ${top.map((row) => row.name).join(', ')}.`,
            actions: top.map((row) => ({
                label: wantsDay ? row.name : `Plan ${row.name}`,
                command: wantsDay ? `day:${row.key}` : `week:${row.key}`
            }))
        };
    }

    const namedDay = matchWeekday(q, session.weekStart || new Date());
    if (namedDay && namedDay.off) {
        return { clarify: `${namedDay.label} is outside the working week. Visits go on Saturday through Wednesday.` };
    }

    const now = session.now ? new Date(session.now) : new Date();
    let selected = null;
    if (/\btoday\b/.test(q)) selected = startOfDay(now);
    else if (/\btomorrow\b/.test(q)) selected = addDays(startOfDay(now), 1);
    else if (namedDay && namedDay.date) selected = startOfDay(namedDay.date);

    const days = remainingWorkingDays(session);

    if (selected) {
        const iso = isoDate(selected);
        const available = days.find((day) => day.iso === iso);
        if (!available) {
            if (selected < startOfDay(now)) {
                return { clarify: `${formatDayChip(selected)} has already passed. Pick a working day still left this week.` };
            }
            if (!isWorkingDay(selected)) {
                return { clarify: `${formatDayChip(selected)} is not a working day. Visits go on Saturday through Wednesday.` };
            }
            return { clarify: `${formatDayChip(selected)} is blocked by time off or a holiday.` };
        }
        return { brickKey: brick.key, span: 'day', date: available.iso, brickName: brick.name, dayLabel: available.label };
    }

    if (wantsDay) {
        if (!days.length) {
            return { clarify: `${brick.name} has no working days left this week.` };
        }
        return {
            clarify: `Which day should I plan in ${brick.name}?`,
            actions: days.map((day) => ({ label: day.label, command: `date:${brick.key}:${day.iso}` }))
        };
    }

    return { brickKey: brick.key, span: 'week', brickName: brick.name };
}

export function describePlan(brickName, slots) {
    if (!slots.length) {
        return `${brickName} has no open visits left to place. Those accounts are already scheduled, or the remaining working days are full.`;
    }
    const byDay = new Map();
    slots.forEach((slot) => {
        const list = byDay.get(slot.dayLabel) || [];
        list.push(slot.accountName);
        byDay.set(slot.dayLabel, list);
    });
    const lines = [...byDay.entries()].map(([day, names]) => `${day}: ${names.join(', ')}`);
    const span = byDay.size === 1 ? [...byDay.keys()][0] : 'this week';
    return `Planned ${slots.length} draft visit${slots.length === 1 ? '' : 's'} in ${brickName} for ${span}.\n${lines.join('\n')}`;
}
