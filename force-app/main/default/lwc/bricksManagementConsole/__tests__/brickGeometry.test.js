/**
 * Geometry helpers of the Bricks map host (static resource brickMapHost/brickGeometry.js).
 */
const G = require('../../../staticresources/brickMapHost/brickGeometry.js');

function square(lat, lng, half) {
    return {
        type: 'Polygon',
        coordinates: [
            [
                [lng - half, lat - half],
                [lng + half, lat - half],
                [lng + half, lat + half],
                [lng - half, lat + half],
                [lng - half, lat - half]
            ]
        ]
    };
}

describe('brickGeometry', () => {
    it('reads GeoJSON into open rings and writes it back closed and rounded', () => {
        const parts = G.partsOf(JSON.stringify(square(30.123456789, 31.3, 0.01)));
        expect(parts).toHaveLength(1);
        expect(parts[0][0]).toHaveLength(4);
        const out = G.toGeometry(parts);
        expect(out.type).toBe('Polygon');
        expect(out.coordinates[0]).toHaveLength(5);
        expect(out.coordinates[0][0]).toEqual(out.coordinates[0][4]);
        expect(out.coordinates[0][0][1]).toBe(30.113457);
    });

    it('reads features, collections and multipolygons, and drops rings that are too small', () => {
        const collection = {
            type: 'FeatureCollection',
            features: [
                { type: 'Feature', geometry: square(30.1, 31.3, 0.01) },
                { type: 'Feature', geometry: { type: 'MultiPolygon', coordinates: [square(30.5, 31.5, 0.01).coordinates] } },
                { type: 'Feature', geometry: { type: 'Polygon', coordinates: [[[31, 30], [31.1, 30.1], [31, 30]]] } }
            ]
        };
        const parts = G.partsOf(collection);
        expect(parts).toHaveLength(2);
        expect(G.toGeometry(parts).type).toBe('MultiPolygon');
        expect(G.toGeometry([])).toBeNull();
        expect(G.partsOf('')).toEqual([]);
    });

    it('measures area in square kilometres and finds the centre', () => {
        const parts = G.partsOf(square(30.1, 31.3, 0.01));
        const area = G.areaKm2(parts);
        expect(area).toBeGreaterThan(4);
        expect(area).toBeLessThan(4.5);
        const c = G.center(parts);
        expect(c[0]).toBeCloseTo(31.3, 6);
        expect(c[1]).toBeCloseTo(30.1, 6);
    });

    it('treats holes as outside', () => {
        const donut = G.partsOf({
            type: 'Polygon',
            coordinates: [square(30.1, 31.3, 0.01).coordinates[0], square(30.1, 31.3, 0.003).coordinates[0]]
        });
        expect(G.contains(donut, [31.3, 30.1])).toBe(false);
        expect(G.contains(donut, [31.306, 30.1])).toBe(true);
        expect(G.areaKm2(donut)).toBeLessThan(G.areaKm2(G.partsOf(square(30.1, 31.3, 0.01))));
    });

    it('spots an outline that crosses itself', () => {
        const bowtie = [[[[31.0, 30.0], [31.1, 30.1], [31.1, 30.0], [31.0, 30.1]]]];
        expect(G.crossesItself(bowtie)).toBe(true);
        expect(G.crossesItself(G.partsOf(square(30.1, 31.3, 0.01)))).toBe(false);
    });

    it('does not call neighbours that share a border an overlap', () => {
        const a = G.partsOf(square(30.1, 31.3, 0.01));
        const touching = G.partsOf(square(30.1, 31.32, 0.01));
        const overlapping = G.partsOf(square(30.1, 31.315, 0.01));
        const inside = G.partsOf(square(30.1, 31.3, 0.002));
        expect(G.overlaps(a, touching)).toBe(false);
        expect(G.overlaps(a, overlapping)).toBe(true);
        expect(G.overlaps(a, inside)).toBe(true);
        expect(G.overlaps(a, G.partsOf(square(30.5, 31.5, 0.01)))).toBe(false);
    });

    it('ignores a snapped point that rounding left a few centimetres inside a neighbour', () => {
        const a = G.partsOf(square(30.1, 31.3, 0.01));
        const b = [[[[31.3100003, 30.095], [31.33, 30.095], [31.33, 30.105], [31.31, 30.105]]]];
        expect(G.overlaps(a, b)).toBe(false);
        const deeper = [[[[31.3095, 30.095], [31.33, 30.095], [31.33, 30.105], [31.31, 30.105]]]];
        expect(G.overlaps(a, deeper)).toBe(true);
    });

    it('counts the same outline as an overlap but not a brick sitting in a hole', () => {
        const a = G.partsOf(square(30.1, 31.3, 0.01));
        expect(G.overlaps(a, G.clone(a))).toBe(true);
        const donut = G.partsOf({
            type: 'Polygon',
            coordinates: [square(30.1, 31.3, 0.02).coordinates[0], square(30.1, 31.3, 0.01).coordinates[0]]
        });
        expect(G.overlaps(donut, a)).toBe(false);
        expect(G.overlaps(donut, G.partsOf(square(30.1, 31.3, 0.012)))).toBe(true);
    });

    it('outlines a 148 brick around its 702 bricks', () => {
        const hull = G.hullOf([G.partsOf(square(30.1, 31.3, 0.01)), G.partsOf(square(30.1, 31.34, 0.01))]);
        expect(hull).toHaveLength(1);
        expect(hull[0][0]).toHaveLength(4);
        const box = G.bbox(hull);
        expect(box.minX).toBeCloseTo(31.29, 6);
        expect(box.maxX).toBeCloseTo(31.35, 6);
        expect(G.hullOf([])).toEqual([]);
    });

    it('simplifies a detailed import until it fits the point limit', () => {
        const ring = [];
        for (let i = 0; i < 720; i++) {
            const t = (i / 720) * 2 * Math.PI;
            ring.push([31.3 + 0.05 * Math.cos(t) + 0.00001 * Math.sin(37 * t), 30.1 + 0.05 * Math.sin(t)]);
        }
        const fit = G.fitPointLimit([[ring]], 100);
        expect(G.vertexCount(fit.parts)).toBeLessThanOrEqual(100);
        expect(G.vertexCount(fit.parts)).toBeGreaterThanOrEqual(3);
        expect(fit.tolerance).toBeGreaterThan(0);
        expect(G.areaKm2(fit.parts)).toBeCloseTo(G.areaKm2([[ring]]), 0);
        expect(G.fitPointLimit([[ring]], 1000).tolerance).toBe(0);
    });

    it('moves a region and builds a starting box', () => {
        const moved = G.translate(G.partsOf(square(30.1, 31.3, 0.01)), 0.1, -0.1);
        expect(G.center(moved)[0]).toBeCloseTo(31.4, 6);
        expect(G.center(moved)[1]).toBeCloseTo(30.0, 6);
        const box = G.rectangle([31.3, 30.1], 0.02, 0.01);
        expect(box).toHaveLength(4);
        expect(G.contains([[box]], [31.3, 30.1])).toBe(true);
    });
});
