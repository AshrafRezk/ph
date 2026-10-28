/*
 * Geometry helpers for the Bricks map host. Positions are [lng, lat] like GeoJSON.
 * A region is held as "parts": a list of polygons, each a list of rings (outline first, then holes),
 * each ring a list of positions without the closing point.
 */
(function (root, factory) {
    var api = factory();
    if (typeof module === 'object' && module.exports) module.exports = api;
    else root.BrickGeometry = api;
})(typeof self !== 'undefined' ? self : this, function () {
    var M_PER_DEG_LAT = 110574;
    var M_PER_DEG_LNG = 111320;
    var MAX_POINTS = 5000;

    function round6(v) { return Math.round(v * 1e6) / 1e6; }

    function samePos(a, b) { return a[0] === b[0] && a[1] === b[1]; }

    function cleanRing(ring) {
        var out = [];
        (ring || []).forEach(function (p) {
            if (!Array.isArray(p) || p.length < 2) return;
            var x = Number(p[0]), y = Number(p[1]);
            if (!isFinite(x) || !isFinite(y)) return;
            var pos = [x, y];
            if (!out.length || !samePos(out[out.length - 1], pos)) out.push(pos);
        });
        if (out.length > 1 && samePos(out[0], out[out.length - 1])) out.pop();
        return out;
    }

    /** GeoJSON (Polygon, MultiPolygon, Feature, FeatureCollection, or its JSON text) to parts. */
    function partsOf(input) {
        var g = input;
        if (typeof g === 'string') {
            if (!g.trim()) return [];
            g = JSON.parse(g);
        }
        if (!g || typeof g !== 'object') return [];
        if (g.type === 'Feature') return partsOf(g.geometry);
        if (g.type === 'FeatureCollection') {
            var all = [];
            (g.features || []).forEach(function (f) { all = all.concat(partsOf(f)); });
            return all;
        }
        var polys = g.type === 'Polygon' ? [g.coordinates] : g.type === 'MultiPolygon' ? g.coordinates : [];
        var parts = [];
        (polys || []).forEach(function (poly) {
            var rings = (poly || []).map(cleanRing).filter(function (r) { return r.length >= 3; });
            if (rings.length) parts.push(rings);
        });
        return parts;
    }

    /** Parts to a GeoJSON Polygon or MultiPolygon with closed, rounded rings; null when empty. */
    function toGeometry(parts) {
        var polys = (parts || [])
            .map(function (rings) {
                return rings
                    .filter(function (r) { return r.length >= 3; })
                    .map(function (r) {
                        var closed = r.map(function (p) { return [round6(p[0]), round6(p[1])]; });
                        closed.push(closed[0].slice());
                        return closed;
                    });
            })
            .filter(function (rings) { return rings.length; });
        if (!polys.length) return null;
        return polys.length === 1 ? { type: 'Polygon', coordinates: polys[0] } : { type: 'MultiPolygon', coordinates: polys };
    }

    function clone(parts) {
        return (parts || []).map(function (rings) {
            return rings.map(function (r) { return r.map(function (p) { return [p[0], p[1]]; }); });
        });
    }

    function vertexCount(parts) {
        var n = 0;
        (parts || []).forEach(function (rings) { rings.forEach(function (r) { n += r.length; }); });
        return n;
    }

    function bbox(parts) {
        var b = null;
        (parts || []).forEach(function (rings) {
            rings.forEach(function (r) {
                r.forEach(function (p) {
                    if (!b) b = { minX: p[0], minY: p[1], maxX: p[0], maxY: p[1] };
                    else {
                        if (p[0] < b.minX) b.minX = p[0];
                        if (p[0] > b.maxX) b.maxX = p[0];
                        if (p[1] < b.minY) b.minY = p[1];
                        if (p[1] > b.maxY) b.maxY = p[1];
                    }
                });
            });
        });
        return b;
    }

    function boxesOverlap(a, b) {
        return !!a && !!b && a.minX <= b.maxX && b.minX <= a.maxX && a.minY <= b.maxY && b.minY <= a.maxY;
    }

    /** Signed ring area in square metres (flat-earth around the ring's latitude). */
    function ringAreaM2(ring) {
        if (!ring || ring.length < 3) return 0;
        var lat0 = 0;
        ring.forEach(function (p) { lat0 += p[1]; });
        lat0 /= ring.length;
        var kx = M_PER_DEG_LNG * Math.cos((lat0 * Math.PI) / 180), ky = M_PER_DEG_LAT, sum = 0;
        for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
            sum += ring[j][0] * kx * (ring[i][1] * ky) - ring[i][0] * kx * (ring[j][1] * ky);
        }
        return sum / 2;
    }

    function areaKm2(parts) {
        var m2 = 0;
        (parts || []).forEach(function (rings) {
            rings.forEach(function (r, i) { m2 += (i === 0 ? 1 : -1) * Math.abs(ringAreaM2(r)); });
        });
        return Math.max(0, m2 / 1e6);
    }

    /** Area-weighted centre of the largest outline, as [lng, lat]. */
    function center(parts) {
        var best = null, bestArea = -1;
        (parts || []).forEach(function (rings) {
            var a = Math.abs(ringAreaM2(rings[0]));
            if (a > bestArea) { bestArea = a; best = rings[0]; }
        });
        if (!best) return null;
        var x = 0, y = 0, f, a2 = 0;
        for (var i = 0, j = best.length - 1; i < best.length; j = i++) {
            f = best[j][0] * best[i][1] - best[i][0] * best[j][1];
            x += (best[j][0] + best[i][0]) * f;
            y += (best[j][1] + best[i][1]) * f;
            a2 += f;
        }
        if (Math.abs(a2) < 1e-14) {
            var b = bbox([[best]]);
            return [(b.minX + b.maxX) / 2, (b.minY + b.maxY) / 2];
        }
        return [x / (3 * a2), y / (3 * a2)];
    }

    function pointInRing(pt, ring) {
        var x = pt[0], y = pt[1], inside = false;
        for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
            var xi = ring[i][0], yi = ring[i][1], xj = ring[j][0], yj = ring[j][1];
            if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
        }
        return inside;
    }

    function contains(parts, pt) {
        return (parts || []).some(function (rings) {
            if (!pointInRing(pt, rings[0])) return false;
            for (var h = 1; h < rings.length; h++) if (pointInRing(pt, rings[h])) return false;
            return true;
        });
    }

    function orient(a, b, c) {
        var v = (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]);
        return v > 0 ? 1 : v < 0 ? -1 : 0;
    }

    function onSegment(a, b, p) {
        return Math.min(a[0], b[0]) <= p[0] && p[0] <= Math.max(a[0], b[0]) && Math.min(a[1], b[1]) <= p[1] && p[1] <= Math.max(a[1], b[1]);
    }

    function segmentsCross(a, b, c, d) {
        var o1 = orient(a, b, c), o2 = orient(a, b, d), o3 = orient(c, d, a), o4 = orient(c, d, b);
        if (o1 !== o2 && o3 !== o4) return true;
        if (o1 === 0 && onSegment(a, b, c)) return true;
        if (o2 === 0 && onSegment(a, b, d)) return true;
        if (o3 === 0 && onSegment(c, d, a)) return true;
        if (o4 === 0 && onSegment(c, d, b)) return true;
        return false;
    }

    /** True when two non-neighbouring edges of the ring touch or cross. */
    function ringCrossesItself(ring) {
        var n = ring.length;
        if (n < 4) return false;
        for (var i = 0; i < n; i++) {
            var a = ring[i], b = ring[(i + 1) % n];
            for (var j = i + 1; j < n; j++) {
                if (j === i || (j + 1) % n === i || (i + 1) % n === j) continue;
                if (segmentsCross(a, b, ring[j], ring[(j + 1) % n])) return true;
            }
        }
        return false;
    }

    function crossesItself(parts) {
        return (parts || []).some(function (rings) { return rings.some(ringCrossesItself); });
    }

    function edgesCross(ringA, ringB) {
        for (var i = 0; i < ringA.length; i++) {
            var a = ringA[i], b = ringA[(i + 1) % ringA.length];
            for (var j = 0; j < ringB.length; j++) {
                if (segmentsCross(a, b, ringB[j], ringB[(j + 1) % ringB.length])) return true;
            }
        }
        return false;
    }

    /** Saved points are rounded to 6 decimals, so a point snapped onto a neighbour's edge can sit ~0.1 m off it. */
    var EDGE_TOLERANCE = 1e-6;

    function strictlyInside(parts, p) {
        return contains(parts, p) && !onAnyEdge(parts, p);
    }

    /**
     * True when the two regions share area. Shared borders (snapped vertices and edges) do not count:
     * a point only counts when it is inside the other region and not on its edge.
     */
    function overlaps(partsA, partsB) {
        if (!boxesOverlap(bbox(partsA), bbox(partsB))) return false;
        function vertexInside(rings, other) {
            return rings[0].some(function (p) { return strictlyInside(other, p); });
        }
        if (partsA.some(function (r) { return vertexInside(r, partsB); })) return true;
        if (partsB.some(function (r) { return vertexInside(r, partsA); })) return true;
        var ca = center(partsA), cb = center(partsB);
        if (ca && strictlyInside(partsA, ca) && strictlyInside(partsB, ca)) return true;
        if (cb && strictlyInside(partsB, cb) && strictlyInside(partsA, cb)) return true;
        return boundaryEnters(partsA, partsB) || boundaryEnters(partsB, partsA);
    }

    function onAnyEdge(parts, p) {
        return parts.some(function (rings) {
            return rings.some(function (r) {
                for (var i = 0; i < r.length; i++) {
                    if (distanceToSegment(p, r[i], r[(i + 1) % r.length]) <= EDGE_TOLERANCE) return true;
                }
                return false;
            });
        });
    }

    function distanceToSegment(p, a, b) {
        var dx = b[0] - a[0], dy = b[1] - a[1], len2 = dx * dx + dy * dy;
        var t = len2 ? ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / len2 : 0;
        t = t < 0 ? 0 : t > 1 ? 1 : t;
        var x = a[0] + t * dx - p[0], y = a[1] + t * dy - p[1];
        return Math.sqrt(x * x + y * y);
    }

    /**
     * True when some stretch of an outline of `parts` runs inside `other`. Each edge is cut where it meets
     * the other region's edges, and the middle of every piece is tested; a vertex test alone misses
     * regions whose corners all sit on each other's borders.
     */
    function boundaryEnters(parts, other) {
        var otherEdges = [];
        other.forEach(function (rings) {
            rings.forEach(function (r) {
                for (var i = 0; i < r.length; i++) otherEdges.push([r[i], r[(i + 1) % r.length]]);
            });
        });
        return parts.some(function (rings) {
            return rings.some(function (ring) {
                for (var i = 0; i < ring.length; i++) {
                    var a = ring[i], b = ring[(i + 1) % ring.length], cuts = [0, 1];
                    otherEdges.forEach(function (e) { cutPoints(a, b, e[0], e[1], cuts); });
                    cuts.sort(function (x, y) { return x - y; });
                    for (var k = 0; k + 1 < cuts.length; k++) {
                        if (cuts[k + 1] - cuts[k] < 1e-9) continue;
                        var t = (cuts[k] + cuts[k + 1]) / 2;
                        if (strictlyInside(other, [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t])) return true;
                    }
                }
                return false;
            });
        });
    }

    /** Adds to `cuts` the positions (0..1 along a→b) where segment c→d meets it. */
    function cutPoints(a, b, c, d, cuts) {
        var rx = b[0] - a[0], ry = b[1] - a[1], sx = d[0] - c[0], sy = d[1] - c[1];
        var denom = rx * sy - ry * sx, len2 = rx * rx + ry * ry;
        if (!len2) return;
        if (Math.abs(denom) < 1e-18) {
            [c, d].forEach(function (p) {
                var t = ((p[0] - a[0]) * rx + (p[1] - a[1]) * ry) / len2;
                if (t > 0 && t < 1) cuts.push(t);
            });
            return;
        }
        var qx = c[0] - a[0], qy = c[1] - a[1];
        var t = (qx * sy - qy * sx) / denom, u = (qx * ry - qy * rx) / denom;
        if (t > 0 && t < 1 && u >= -1e-9 && u <= 1 + 1e-9) cuts.push(t);
    }

    /** Convex hull (monotone chain) of positions. */
    function convexHull(points) {
        var pts = (points || [])
            .map(function (p) { return [p[0], p[1]]; })
            .sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
        if (pts.length < 3) return pts;
        function cross(o, a, b) { return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0]); }
        var lower = [], upper = [], i;
        for (i = 0; i < pts.length; i++) {
            while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], pts[i]) <= 0) lower.pop();
            lower.push(pts[i]);
        }
        for (i = pts.length - 1; i >= 0; i--) {
            while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], pts[i]) <= 0) upper.pop();
            upper.push(pts[i]);
        }
        upper.pop();
        lower.pop();
        return lower.concat(upper);
    }

    /** One outline around all the given regions (their convex hull). */
    function hullOf(regions) {
        var pts = [];
        (regions || []).forEach(function (parts) {
            parts.forEach(function (rings) { pts = pts.concat(rings[0]); });
        });
        var hull = convexHull(pts);
        return hull.length >= 3 ? [[hull]] : [];
    }

    function rectangle(centerPos, halfLng, halfLat) {
        var x = centerPos[0], y = centerPos[1];
        return [[x - halfLng, y - halfLat], [x + halfLng, y - halfLat], [x + halfLng, y + halfLat], [x - halfLng, y + halfLat]];
    }

    function translate(parts, dLng, dLat) {
        return clone(parts).map(function (rings) {
            return rings.map(function (r) { return r.map(function (p) { return [p[0] + dLng, p[1] + dLat]; }); });
        });
    }

    function perpendicularMeters(p, a, b, kx, ky) {
        var x = (p[0] - a[0]) * kx, y = (p[1] - a[1]) * ky, dx = (b[0] - a[0]) * kx, dy = (b[1] - a[1]) * ky;
        var len2 = dx * dx + dy * dy;
        var t = len2 ? Math.max(0, Math.min(1, (x * dx + y * dy) / len2)) : 0;
        var ex = x - t * dx, ey = y - t * dy;
        return Math.sqrt(ex * ex + ey * ey);
    }

    /** Douglas-Peucker on a closed ring, tolerance in metres. Keeps at least 3 points. */
    function simplifyRing(ring, toleranceM) {
        if (ring.length <= 4) return ring.slice();
        var kx = M_PER_DEG_LNG * Math.cos((ring[0][1] * Math.PI) / 180), ky = M_PER_DEG_LAT;
        var far = 0, farD = -1;
        ring.forEach(function (p, i) {
            var d = Math.abs(p[0] - ring[0][0]) * kx + Math.abs(p[1] - ring[0][1]) * ky;
            if (d > farD) { farD = d; far = i; }
        });
        function dp(pts) {
            if (pts.length < 3) return pts;
            var max = 0, idx = 0;
            for (var i = 1; i < pts.length - 1; i++) {
                var d = perpendicularMeters(pts[i], pts[0], pts[pts.length - 1], kx, ky);
                if (d > max) { max = d; idx = i; }
            }
            if (max <= toleranceM) return [pts[0], pts[pts.length - 1]];
            var left = dp(pts.slice(0, idx + 1)), right = dp(pts.slice(idx));
            return left.slice(0, -1).concat(right);
        }
        var first = dp(ring.slice(0, far + 1)), second = dp(ring.slice(far).concat([ring[0]]));
        var out = first.slice(0, -1).concat(second.slice(0, -1));
        return out.length >= 3 ? out : ring.slice(0, 3);
    }

    /** Simplifies until the region fits the point limit; returns { parts, tolerance }. */
    function fitPointLimit(parts, limit) {
        var max = limit || MAX_POINTS, tol = 0, out = clone(parts);
        while (vertexCount(out) > max && tol < 5000) {
            tol = tol ? tol * 2 : 5;
            out = parts.map(function (rings) {
                return rings.map(function (r) { return simplifyRing(r, tol); });
            });
        }
        return { parts: out, tolerance: tol };
    }

    return {
        MAX_POINTS: MAX_POINTS,
        partsOf: partsOf,
        toGeometry: toGeometry,
        clone: clone,
        vertexCount: vertexCount,
        bbox: bbox,
        boxesOverlap: boxesOverlap,
        areaKm2: areaKm2,
        center: center,
        contains: contains,
        pointInRing: pointInRing,
        segmentsCross: segmentsCross,
        ringCrossesItself: ringCrossesItself,
        crossesItself: crossesItself,
        edgesCross: edgesCross,
        overlaps: overlaps,
        convexHull: convexHull,
        hullOf: hullOf,
        rectangle: rectangle,
        translate: translate,
        simplifyRing: simplifyRing,
        fitPointLimit: fitPointLimit
    };
});
