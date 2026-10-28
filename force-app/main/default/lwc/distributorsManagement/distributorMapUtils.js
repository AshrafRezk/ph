/** Helpers for the sellout map: popup HTML is built from user and file data, so every value is escaped. */

/** Rough bounding box of Egypt: south, west, north, east. */
export const EGYPT_BOUNDS = [
    [21.7, 24.6],
    [31.9, 37.0]
];

export function escapeHtml(value) {
    return String(value == null ? '' : value)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

export function isInEgypt(lat, lng) {
    const la = Number(lat);
    const lo = Number(lng);
    if (lat == null || lng == null || !Number.isFinite(la) || !Number.isFinite(lo)) return false;
    return la >= EGYPT_BOUNDS[0][0] && la <= EGYPT_BOUNDS[1][0] && lo >= EGYPT_BOUNDS[0][1] && lo <= EGYPT_BOUNDS[1][1];
}

/**
 * Bounds the map should fit: the markers that are inside Egypt, or all of Egypt when there are none.
 * A marker with bad coordinates (0,0, another country) never drags the view out of Egypt.
 */
export function fitBoundsFor(points) {
    const inside = (points || []).filter((p) => isInEgypt(p[0], p[1]));
    return inside.length ? inside : EGYPT_BOUNDS;
}

export function popupHtml(row) {
    const title = row.clientName || row.clientCode || '';
    const lines = [
        `<strong>${escapeHtml(title)}</strong>`,
        escapeHtml(row.distributorCode),
        escapeHtml(row.address),
        escapeHtml(row.pharmacyName || row.status)
    ];
    return lines.join('<br/>');
}
