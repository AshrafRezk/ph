/*
 * Bricks map host. Runs in an iframe inside the Bricks Manager (Admin Console) and talks to it with postMessage.
 *
 * From the console: HOST_INIT, HOST_UPDATE, HOST_SELECT, HOST_EDIT, HOST_EDIT_END, HOST_EDIT_ERROR,
 *                   HOST_LOCATE, HOST_LOCATE_RESULT, HOST_POINTS, HOST_HEAT, HOST_DESTROY
 * To the console:   HOST_READY, HOST_ERROR, HOST_BRICK_SELECT, HOST_REGION_SAVE, HOST_EDIT_CANCEL,
 *                   HOST_LOCATE_POINT, HOST_LOCATE_TOGGLED, HOST_POINTS_TOGGLED
 */
(function () {
    'use strict';
    var G = window.BrickGeometry;
    var trustedOrigin = null;
    var map = null;
    var L = null;

    var EGYPT = [26.9, 30.9];
    var PALETTE = ['#0176d3', '#2e844a', '#dd7a01', '#8a49d0', '#c23934', '#0b827c', '#b35c00', '#3a49da', '#7f8c0d', '#d4357a'];
    var PLACEMENT_COLORS = {
        'In region': '#2e844a',
        'Nearest region': '#0b827c',
        'Approximate location': '#dd7a01',
        'Outside regions': '#c23934',
        'No location': '#939393'
    };
    // Sales shading: light to dark blue on a square-root scale, so a few big bricks do not wash out the rest.
    var HEAT_RAMP = ['#e3f3ff', '#aacbff', '#78b0fd', '#1b96ff', '#0176d3', '#014486'];
    var HEAT_EMPTY = '#c9c9c9';
    var LABEL_ZOOM = { '702': 12, '148': 9 };
    var MAX_LABELS = 250;
    var MAX_HANDLES = 400;
    var SNAP_PX = 12;

    var state = { level: '702', bricks: [], parents: [], children: [], points: [], selectedId: null, canEdit: false, showPoints: true, heat: null };
    var index = { bricks: {}, parents: {}, children: {} };
    var layers = {};
    var renderers = {};
    var regionLayers = {};
    var edit = null;
    var locate = { on: false, marker: null, seq: 0 };

    function post(payload) { if (trustedOrigin) window.parent.postMessage(payload, trustedOrigin); }
    function esc(s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); }
    function $(id) { return document.getElementById(id); }

    function toast(text) {
        var el = $('toast');
        el.textContent = text;
        el.classList.add('show');
        clearTimeout(toast._t);
        toast._t = setTimeout(function () { el.classList.remove('show'); }, 2600);
    }

    function loadLeaflet(base, cb) {
        if (window.L) { cb(); return; }
        var css = document.createElement('link'); css.rel = 'stylesheet'; css.href = base + '/leaflet.css'; document.head.appendChild(css);
        var s = document.createElement('script'); s.src = base + '/leaflet.js';
        s.onload = cb;
        s.onerror = function () { post({ type: 'HOST_ERROR', message: 'Leaflet failed to load.' }); };
        document.head.appendChild(s);
    }

    /* ---------- data ---------- */
    function colorOf(id) {
        var h = 0, s = String(id || '');
        for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
        return PALETTE[Math.abs(h) % PALETTE.length];
    }
    function indexOf(list) {
        var out = {};
        (list || []).forEach(function (b) {
            var parts = [];
            try { parts = b.geometry ? G.partsOf(b.geometry) : []; } catch (e) { parts = []; }
            out[b.id] = { b: b, parts: parts, box: G.bbox(parts), center: parts.length ? G.center(parts) : null };
        });
        return out;
    }
    function entryOf(id) { return index.bricks[id] || index.parents[id] || index.children[id] || null; }
    function nameOf(id) { var e = entryOf(id); return e ? e.b.name : null; }
    function toLatLngs(parts) {
        return parts.map(function (rings) { return rings.map(function (r) { return r.map(function (p) { return [p[1], p[0]]; }); }); });
    }
    function boundsOf(box) { return box ? L.latLngBounds([box.minY, box.minX], [box.maxY, box.maxX]) : null; }
    function fmtArea(km2) { return km2 >= 100 ? Math.round(km2).toLocaleString() : km2 >= 10 ? km2.toFixed(1) : km2.toFixed(2); }

    function applyData(d, fit) {
        var levelChanged = !!d.level && d.level !== state.level;
        ['level', 'bricks', 'parents', 'children', 'points', 'canEdit', 'selectedId'].forEach(function (k) { if (d[k] !== undefined) state[k] = d[k]; });
        if (d.showPoints !== undefined) state.showPoints = !!d.showPoints;
        if (d.heat !== undefined) state.heat = d.heat;
        index.bricks = indexOf(state.bricks);
        index.parents = indexOf(state.parents);
        index.children = indexOf(state.children);
        if (edit && !index.bricks[edit.id]) stopEdit();
        renderContext();
        renderRegions();
        renderPoints();
        renderLabels();
        renderLegend();
        setBtn('points', state.showPoints);
        if (fit || levelChanged) {
            if (state.selectedId && index.bricks[state.selectedId] && index.bricks[state.selectedId].parts.length) select(state.selectedId, true);
            else flyHome();
        }
    }

    /* ---------- rendering ---------- */
    function heatOf(id) {
        var v = state.heat && state.heat.values ? state.heat.values[id] : null;
        return v ? Number(v[state.heat.metric] || 0) : 0;
    }
    function heatMax() {
        var max = 0, values = (state.heat && state.heat.values) || {};
        Object.keys(values).forEach(function (id) { if (index.bricks[id]) max = Math.max(max, heatOf(id)); });
        return max;
    }
    function heatColor(v, max) {
        if (!(v > 0) || !(max > 0)) return HEAT_EMPTY;
        var t = Math.sqrt(v / max);
        return HEAT_RAMP[Math.min(HEAT_RAMP.length - 1, Math.floor(t * HEAT_RAMP.length))];
    }
    function fmtCompact(n) { return Number(n || 0).toLocaleString(undefined, { notation: 'compact', maximumFractionDigits: 1 }); }
    function heatTip(id) {
        if (!state.heat) return '';
        if (state.heat.pending) return '<br>Adding up sales…';
        var v = state.heat.values ? state.heat.values[id] : null;
        var by = state.heat.sources && state.heat.sources[id] ? '<br>' + esc(state.heat.sources[id]) : '';
        if (!v) return '<br>No sales' + by;
        return '<br>EGP ' + fmtCompact(v.revenue) + ' · ' + fmtCompact(v.quantity) + ' units · ' + Number(v.lines || 0).toLocaleString() + ' lines' + by;
    }

    function regionStyle(e, selected) {
        if (state.heat) {
            var v = heatOf(e.b.id), fill = state.heat.pending ? HEAT_EMPTY : heatColor(v, regionStyle.max);
            return {
                color: selected ? '#032d60' : '#ffffff',
                weight: selected ? 3 : 0.8,
                opacity: 0.95,
                fillColor: fill,
                fillOpacity: selected ? 0.9 : v > 0 ? 0.78 : 0.2,
                dashArray: null
            };
        }
        var inactive = e.b.isActive === false, color = inactive ? '#939393' : colorOf(e.b.id);
        return {
            color: selected ? '#032d60' : color,
            weight: selected ? 3 : 1.4,
            opacity: 0.95,
            fillColor: color,
            fillOpacity: selected ? 0.42 : state.level === '702' ? 0.24 : 0.17,
            dashArray: inactive ? '5,5' : null
        };
    }

    function renderContext() {
        layers.context.clearLayers();
        var source = state.level === '702' ? index.parents : index.children;
        var style = state.level === '702'
            ? { color: '#032d60', weight: 2, opacity: 0.65, dashArray: '8,6', fill: false }
            : { color: '#3e3e3c', weight: 0.8, opacity: 0.55, fill: false };
        Object.keys(source).forEach(function (id) {
            var e = source[id];
            if (!e.parts.length) return;
            L.polygon(toLatLngs(e.parts), Object.assign({ renderer: renderers.context, interactive: false }, style)).addTo(layers.context);
        });
    }

    function renderRegions() {
        layers.regions.clearLayers();
        regionLayers = {};
        regionStyle.max = state.heat ? heatMax() : 0;
        Object.keys(index.bricks).forEach(function (id) {
            var e = index.bricks[id];
            if (!e.parts.length || (edit && edit.id === id)) return;
            var layer = L.polygon(toLatLngs(e.parts), Object.assign({ renderer: renderers.regions }, regionStyle(e, id === state.selectedId)));
            layer.bindTooltip(
                '<b>' + esc(e.b.name) + '</b>' + (e.b.areaKm2 != null ? '<br>' + fmtArea(Number(e.b.areaKm2)) + ' km²' : '') +
                    (state.heat ? heatTip(id) : e.b.clientCount ? '<br>' + e.b.clientCount + ' distributor clients' : ''),
                { sticky: true, className: 'brick-tip', direction: 'top', offset: [0, -8] }
            );
            layer.on('click', function (ev) {
                if (edit || locate.on) return;
                L.DomEvent.stopPropagation(ev);
                select(id, false);
                post({ type: 'HOST_BRICK_SELECT', id: id });
            });
            layer.addTo(layers.regions);
            regionLayers[id] = layer;
        });
        if (regionLayers[state.selectedId]) regionLayers[state.selectedId].bringToFront();
    }

    function renderLabels() {
        if (!map) return;
        layers.labels.clearLayers();
        var z = map.getZoom(), view = map.getBounds().pad(0.15), count = 0;
        var showAll = z >= (LABEL_ZOOM[state.level] || 12);
        Object.keys(index.bricks).forEach(function (id) {
            var e = index.bricks[id];
            if (!e.center || (edit && edit.id === id) || count >= MAX_LABELS) return;
            var on = id === state.selectedId;
            if (!on && !showAll) return;
            var at = [e.center[1], e.center[0]];
            if (!view.contains(at)) return;
            count++;
            L.marker(at, {
                interactive: false, keyboard: false, zIndexOffset: on ? 500 : 0,
                icon: L.divIcon({ className: 'brick-label' + (on ? ' is-on' : ''), html: '<span>' + esc(e.b.name) + '</span>', iconSize: [0, 0] })
            }).addTo(layers.labels);
        });
        if (state.level === '702' && z >= 8 && z < 12) {
            Object.keys(index.parents).forEach(function (id) {
                var e = index.parents[id];
                if (!e.center || count >= MAX_LABELS || !view.contains([e.center[1], e.center[0]])) return;
                count++;
                L.marker([e.center[1], e.center[0]], {
                    interactive: false, keyboard: false,
                    icon: L.divIcon({ className: 'brick-label is-context', html: '<span>' + esc(e.b.name) + '</span>', iconSize: [0, 0] })
                }).addTo(layers.labels);
            });
        }
    }

    function pointPopup(p) {
        var b702 = nameOf(p.brick702Id), b148 = nameOf(p.brick148Id);
        var rows = [
            p.distributor ? esc(p.distributor) + (p.pharmacyName ? ' · ' + esc(p.pharmacyName) : '') : esc(p.pharmacyName || ''),
            esc(p.address || ''),
            esc(p.governorate || '')
        ].filter(Boolean);
        return '<div class="pop">' +
            '<div class="t">' + esc(p.name || 'Distributor client') + '</div>' +
            rows.map(function (r) { return '<div class="r">' + r + '</div>'; }).join('') +
            '<div class="s" style="background:' + (PLACEMENT_COLORS[p.placement] || '#939393') + '">' + esc(p.placement || 'Not placed') + '</div>' +
            (p.precision ? '<div class="r">Location: ' + esc(p.precision) + ' level</div>' : '') +
            (b702 || b148 ? '<div class="r">' + [b702 ? '702 ' + esc(b702) : null, b148 ? '148 ' + esc(b148) : null].filter(Boolean).join(' · ') + '</div>' : '') +
            '</div>';
    }

    function renderPoints() {
        layers.points.clearLayers();
        if (!state.showPoints) return;
        (state.points || []).forEach(function (p) {
            if (p.lat == null || p.lng == null) return;
            var mine = !!state.selectedId && (p.brick702Id === state.selectedId || p.brick148Id === state.selectedId);
            L.circleMarker([p.lat, p.lng], {
                renderer: renderers.points, radius: mine ? 6 : 4.5, weight: mine ? 2 : 1.2, color: mine ? '#032d60' : '#ffffff',
                fillColor: PLACEMENT_COLORS[p.placement] || '#939393', fillOpacity: 0.95, bubblingMouseEvents: false, interactive: !edit
            })
                .bindPopup(function () { return pointPopup(p); }, { className: 'brick-pop', maxWidth: 280 })
                .addTo(layers.points);
        });
    }

    function renderLegend() {
        var el = $('legend'), html = [];
        if (state.heat) {
            html.push('<span>' + (state.heat.metric === 'quantity' ? 'Units' : 'EGP') + ' low</span>');
            html.push('<span>' + HEAT_RAMP.map(function (c) { return '<i class="ramp" style="background:' + c + '"></i>'; }).join('') + '</span>');
            html.push('<span>high</span>');
            html.push('<span><i class="ramp" style="background:' + HEAT_EMPTY + ';opacity:.5"></i>No sales</span>');
        }
        if (state.showPoints) {
            Object.keys(PLACEMENT_COLORS).forEach(function (k) {
                if (k === 'No location') return;
                html.push('<span><i class="dot" style="background:' + PLACEMENT_COLORS[k] + '"></i>' + esc(k) + '</span>');
            });
        }
        html.push(state.level === '702'
            ? '<span><i class="line dash"></i>148 brick</span>'
            : '<span><i class="line thin"></i>702 brick</span>');
        html.push('<span><i class="sw"></i>Inactive</span>');
        el.innerHTML = html.join('');
    }

    function select(id, fly) {
        var prev = state.selectedId;
        state.selectedId = id || null;
        [prev, state.selectedId].forEach(function (key) {
            if (key && regionLayers[key] && index.bricks[key]) regionLayers[key].setStyle(regionStyle(index.bricks[key], key === state.selectedId));
        });
        if (regionLayers[state.selectedId]) regionLayers[state.selectedId].bringToFront();
        renderLabels();
        if (state.showPoints) renderPoints();
        var e = index.bricks[state.selectedId];
        if (fly && e && e.parts.length) map.flyToBounds(boundsOf(e.box), { paddingTopLeft: [60, 70], paddingBottomRight: [60, 70], maxZoom: 15, duration: 0.8 });
    }

    function flyHome() {
        var b = null;
        [index.bricks, index.parents].forEach(function (group) {
            if (b) return;
            Object.keys(group).forEach(function (id) {
                var box = group[id].box;
                if (!box) return;
                var bb = boundsOf(box);
                b = b ? b.extend(bb) : bb;
            });
        });
        if (b) map.flyToBounds(b, { padding: [40, 40], maxZoom: 13, duration: 0.8 });
        else map.flyTo(EGYPT, 6, { duration: 0.8 });
    }

    /* ---------- find brick (locate) ---------- */
    function setLocate(on) {
        if (locate.on === !!on) return;
        locate.on = !!on;
        $('stage').classList.toggle('is-locating', locate.on);
        setBtn('locate', locate.on);
        if (!locate.on && locate.marker) { map.removeLayer(locate.marker); locate.marker = null; }
        if (locate.on) toast('Click the map to see which 702 and 148 brick a place is in.');
        post({ type: 'HOST_LOCATE_TOGGLED', on: locate.on });
    }

    function locateAt(latlng) {
        locate.seq++;
        if (locate.marker) map.removeLayer(locate.marker);
        locate.marker = L.marker(latlng, {
            keyboard: false, zIndexOffset: 3000,
            icon: L.divIcon({ className: 'locate-pin', html: '<span></span>', iconSize: [0, 0] })
        }).addTo(map);
        locate.marker.bindPopup('<div class="pop"><div class="r">Finding the bricks…</div></div>', { className: 'brick-pop', closeButton: false, autoClose: false }).openPopup();
        post({ type: 'HOST_LOCATE_POINT', seq: locate.seq, lat: Math.round(latlng.lat * 1e7) / 1e7, lng: Math.round(latlng.lng * 1e7) / 1e7 });
    }

    function locateResult(d) {
        if (!locate.marker || d.seq !== locate.seq) return;
        var html = d.message
            ? '<div class="r">' + esc(d.message) + '</div>'
            : '<div class="t">' + esc(d.brick702Name || 'No 702 brick here') + '</div>' +
              '<div class="r">148: ' + esc(d.brick148Name || 'none') + '</div>' +
              '<div class="s" style="background:' + (PLACEMENT_COLORS[d.status] || '#939393') + '">' + esc(d.status || '') + '</div>';
        locate.marker.setPopupContent('<div class="pop">' + html + '</div>');
        locate.marker.openPopup();
    }

    function setPoints(on) {
        if (state.showPoints === !!on) return;
        state.showPoints = !!on;
        setBtn('points', state.showPoints);
        renderPoints();
        renderLegend();
        post({ type: 'HOST_POINTS_TOGGLED', on: state.showPoints });
    }

    /* ---------- zone editor ---------- */
    var HANDLE_ICONS = {
        move: '<svg viewBox="0 0 16 16"><path d="M8 0 5.5 2.5h1.75v4.75H2.5V5.5L0 8l2.5 2.5V8.75h4.75v4.75H5.5L8 16l2.5-2.5H8.75V8.75h4.75v1.75L16 8l-2.5-2.5v1.75H8.75V2.5h1.75L8 0Z"/></svg>',
        turn: '<svg viewBox="0 0 16 16"><path d="M8 2a6 6 0 1 0 5.66 8h-2.17A4 4 0 1 1 8 4c1.1 0 2.1.45 2.83 1.17L8.5 7.5H15V1l-2.76 2.76A5.98 5.98 0 0 0 8 2Z"/></svg>'
    };

    function handle(kind, latlng, layer) {
        return L.marker(latlng, {
            draggable: true, keyboard: false, zIndexOffset: kind === 'move' || kind === 'turn' ? 2500 : kind === 'mid' ? 1800 : 2000,
            icon: L.divIcon({ className: 'zone-handle zone-handle_' + kind, html: '<span>' + (HANDLE_ICONS[kind] || '') + '</span>', iconSize: [0, 0] })
        }).addTo(layer || map);
    }

    function pushHistory() {
        if (!edit) return;
        edit.history.push({ parts: G.clone(edit.parts), draw: edit.draw.map(function (p) { return p.slice(); }), mode: edit.mode });
        if (edit.history.length > 60) edit.history.shift();
        edit.error = null;
    }

    function undo() {
        if (!edit || !edit.history.length || edit.saving) return;
        var last = edit.history.pop();
        edit.parts = last.parts;
        edit.draw = last.draw;
        edit.mode = last.mode;
        syncEditor(true);
    }

    function collectSnapTargets() {
        var pts = [], segs = [], view = map.getBounds().pad(0.3);
        function add(e) {
            if (!e.parts.length || !view.intersects(boundsOf(e.box))) return;
            e.parts.forEach(function (rings) {
                rings.forEach(function (r) {
                    var prev = null;
                    r.concat([r[0]]).forEach(function (p) {
                        var cp = map.latLngToContainerPoint([p[1], p[0]]);
                        if (prev) segs.push([prev, cp]);
                        else pts.push(cp);
                        if (prev) pts.push(cp);
                        prev = cp;
                    });
                });
            });
        }
        Object.keys(index.bricks).forEach(function (id) { if (!edit || id !== edit.id) add(index.bricks[id]); });
        Object.keys(state.level === '702' ? index.parents : index.children).forEach(function (id) {
            add((state.level === '702' ? index.parents : index.children)[id]);
        });
        return { pts: pts, segs: segs };
    }

    function snapLatLng(latlng) {
        if (!edit || !edit.snap || !edit.targets) return latlng;
        var p = map.latLngToContainerPoint(latlng), best = null, bestD = SNAP_PX;
        edit.targets.pts.forEach(function (t) {
            var d = Math.hypot(t.x - p.x, t.y - p.y);
            if (d < bestD) { bestD = d; best = t; }
        });
        if (!best) {
            bestD = SNAP_PX * 0.75;
            edit.targets.segs.forEach(function (s) {
                var a = s[0], b = s[1], dx = b.x - a.x, dy = b.y - a.y, len2 = dx * dx + dy * dy;
                if (!len2) return;
                var t = Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2));
                var q = L.point(a.x + t * dx, a.y + t * dy), d = Math.hypot(q.x - p.x, q.y - p.y);
                if (d < bestD) { bestD = d; best = q; }
            });
        }
        return best ? map.containerPointToLatLng(best) : latlng;
    }

    function startEdit(d) {
        var e = index.bricks[d.id];
        if (!e) return;
        if (!state.canEdit) { toast('You can view bricks but not change their regions.'); return; }
        if (edit) stopEdit();
        setLocate(false);
        var parts, source = 'Drawn';
        if (d.mode === 'children') {
            var kids = Object.keys(index.children).map(function (k) { return index.children[k]; }).filter(function (c) {
                return c.b.parentId === d.id && c.parts.length;
            });
            parts = G.hullOf(kids.map(function (c) { return c.parts; }));
            if (!parts.length) {
                toast('None of its 702 bricks has a region yet.');
                post({ type: 'HOST_EDIT_CANCEL', id: d.id });
                return;
            }
            source = 'Child bricks';
        } else if (d.geometry) {
            try { parts = G.partsOf(d.geometry); } catch (err) { parts = []; }
            if (!parts.length) {
                toast('That GeoJSON has no polygon.');
                post({ type: 'HOST_EDIT_CANCEL', id: d.id });
                return;
            }
            var fit = G.fitPointLimit(parts, G.MAX_POINTS);
            if (fit.tolerance) {
                parts = fit.parts;
                toast('Simplified to ' + G.vertexCount(parts).toLocaleString() + ' points (' + fit.tolerance + ' m detail).');
            }
            source = d.source || 'Imported';
        } else {
            parts = G.clone(e.parts);
            if (d.mode === 'draw' && parts.length) parts = [];
        }
        edit = {
            id: d.id, name: e.b.name, parts: parts, draw: [], mode: parts.length ? 'edit' : 'draw', source: source,
            hadRegion: e.parts.length > 0, history: [], snap: true, saving: false, removeArmed: false, error: null, overlaps: [], targets: null
        };
        edit.shape = L.polygon([], { renderer: renderers.edit, color: '#032d60', weight: 2.5, fillColor: '#0176d3', fillOpacity: 0.2, interactive: false }).addTo(map);
        edit.drawLine = L.polyline([], { renderer: renderers.edit, color: '#0176d3', weight: 2, dashArray: '6,5', interactive: false }).addTo(map);
        edit.handleLayer = L.layerGroup().addTo(map);
        edit.move = handle('move', map.getCenter());
        edit.turn = handle('turn', map.getCenter());
        bindMoveTurn();
        map.doubleClickZoom.disable();
        $('stage').classList.add('is-editing');
        $('snap').checked = true;
        renderRegions();
        renderLabels();
        renderPoints();
        syncEditor(true);
        $('zoneBar').hidden = false;
        if (parts.length) map.flyToBounds(boundsOf(G.bbox(parts)), { paddingTopLeft: [60, 70], paddingBottomRight: [60, 170], maxZoom: 16, duration: 0.8 });
        else {
            var parent = index.parents[e.b.parentId];
            if (parent && parent.parts.length) map.flyToBounds(boundsOf(parent.box), { padding: [40, 40], maxZoom: 15, duration: 0.8 });
        }
    }

    function stopEdit() {
        if (!edit) return;
        var session = edit;
        edit = null;
        [session.shape, session.drawLine, session.handleLayer, session.move, session.turn].forEach(function (l) { if (l) map.removeLayer(l); });
        map.doubleClickZoom.enable();
        $('zoneBar').hidden = true;
        $('stage').classList.remove('is-editing');
        renderRegions();
        renderLabels();
        renderPoints();
    }

    function bindMoveTurn() {
        var start = null;
        edit.move.on('dragstart', function (ev) {
            pushHistory();
            start = { ll: ev.target.getLatLng(), parts: G.clone(edit.parts) };
            map.removeLayer(edit.handleLayer);
        });
        edit.move.on('drag', function (ev) {
            var ll = ev.target.getLatLng();
            edit.parts = G.translate(start.parts, ll.lng - start.ll.lng, ll.lat - start.ll.lat);
            syncShape();
            placeTurn();
        });
        edit.move.on('dragend', function () { edit.handleLayer.addTo(map); syncEditor(true); });

        edit.turn.on('dragstart', function () {
            pushHistory();
            var c = G.center(edit.parts);
            start = { parts: G.clone(edit.parts), mid: map.project([c[1], c[0]], 20), from: map.project(edit.turn.getLatLng(), 20) };
            map.removeLayer(edit.handleLayer);
        });
        edit.turn.on('drag', function (ev) {
            // Turn and resize around the centre so the outline keeps its shape.
            var v0 = start.from.subtract(start.mid), v1 = map.project(ev.target.getLatLng(), 20).subtract(start.mid);
            var k = Math.hypot(v1.x, v1.y) / (Math.hypot(v0.x, v0.y) || 1);
            var t = Math.atan2(v1.y, v1.x) - Math.atan2(v0.y, v0.x), cs = Math.cos(t) * k, sn = Math.sin(t) * k, mid = start.mid;
            edit.parts = start.parts.map(function (rings) {
                return rings.map(function (r) {
                    return r.map(function (p) {
                        var q = map.project([p[1], p[0]], 20).subtract(mid);
                        var ll = map.unproject(L.point(mid.x + q.x * cs - q.y * sn, mid.y + q.x * sn + q.y * cs), 20);
                        return [ll.lng, ll.lat];
                    });
                });
            });
            syncShape();
            placeMove();
        });
        edit.turn.on('dragend', function () { edit.handleLayer.addTo(map); syncEditor(true); });
    }

    function placeMove() {
        var c = edit.parts.length ? G.center(edit.parts) : null;
        if (c) edit.move.setLatLng([c[1], c[0]]);
    }
    function placeTurn() {
        var box = G.bbox(edit.parts);
        if (!box) return;
        var c = G.center(edit.parts);
        var east = map.latLngToContainerPoint([c[1], box.maxX]).add([30, 0]);
        edit.turn.setLatLng(map.containerPointToLatLng(east));
    }

    function syncShape() {
        edit.shape.setLatLngs(toLatLngs(edit.parts));
        updateStats();
    }

    function syncEditor(rebuild) {
        if (!edit) return;
        edit.shape.setLatLngs(toLatLngs(edit.parts));
        edit.drawLine.setLatLngs(edit.draw.map(function (p) { return [p[1], p[0]]; }));
        var showTransform = edit.mode === 'edit' && edit.parts.length > 0;
        [edit.move, edit.turn].forEach(function (m) {
            if (showTransform && !map.hasLayer(m)) m.addTo(map);
            if (!showTransform && map.hasLayer(m)) map.removeLayer(m);
        });
        if (showTransform) { placeMove(); placeTurn(); }
        if (rebuild) {
            rebuildHandles();
            edit.overlaps = findOverlaps();
        }
        updateBar();
    }

    function rebuildHandles() {
        var layer = edit.handleLayer;
        layer.clearLayers();
        edit.tooMany = false;
        if (edit.mode === 'draw') {
            edit.draw.forEach(function (p, i) {
                var m = L.marker([p[1], p[0]], {
                    keyboard: false, zIndexOffset: 2200,
                    icon: L.divIcon({ className: 'zone-handle zone-handle_draw' + (i === 0 && edit.draw.length >= 3 ? ' is-close' : ''), html: '<span></span>', iconSize: [0, 0] })
                }).addTo(layer);
                if (i === 0) m.on('click', function (ev) { L.DomEvent.stopPropagation(ev); finishDraw(); });
            });
            return;
        }
        var view = map.getBounds().pad(0.1), wanted = [];
        edit.parts.forEach(function (rings, pi) {
            rings.forEach(function (r, ri) {
                r.forEach(function (p, vi) { if (view.contains([p[1], p[0]])) wanted.push([pi, ri, vi]); });
            });
        });
        if (wanted.length > MAX_HANDLES) { edit.tooMany = true; return; }
        wanted.forEach(function (w) {
            vertexHandle(w[0], w[1], w[2]);
            midHandle(w[0], w[1], w[2]);
        });
    }

    function vertexHandle(pi, ri, vi) {
        var p = edit.parts[pi][ri][vi];
        var m = handle(ri > 0 ? 'hole' : 'vertex', [p[1], p[0]], edit.handleLayer);
        m.on('dragstart', function () { pushHistory(); edit.targets = collectSnapTargets(); });
        m.on('drag', function (ev) {
            var ll = snapLatLng(ev.target.getLatLng());
            if (!ll.equals(ev.target.getLatLng())) ev.target.setLatLng(ll);
            edit.parts[pi][ri][vi] = [ll.lng, ll.lat];
            syncShape();
        });
        m.on('dragend', function () { edit.targets = null; syncEditor(true); });
        m.on('contextmenu', function (ev) {
            if (ev.originalEvent) L.DomEvent.preventDefault(ev.originalEvent);
            deleteVertex(pi, ri, vi);
        });
        m.on('dblclick', function (ev) { L.DomEvent.stopPropagation(ev); deleteVertex(pi, ri, vi); });
    }

    function midHandle(pi, ri, vi) {
        var ring = edit.parts[pi][ri], a = ring[vi], b = ring[(vi + 1) % ring.length];
        var m = handle('mid', [(a[1] + b[1]) / 2, (a[0] + b[0]) / 2], edit.handleLayer);
        var at = vi + 1;
        m.on('dragstart', function (ev) {
            pushHistory();
            var ll = ev.target.getLatLng();
            ring.splice(at, 0, [ll.lng, ll.lat]);
            edit.targets = collectSnapTargets();
        });
        m.on('drag', function (ev) {
            var ll = snapLatLng(ev.target.getLatLng());
            if (!ll.equals(ev.target.getLatLng())) ev.target.setLatLng(ll);
            ring[at] = [ll.lng, ll.lat];
            syncShape();
        });
        m.on('dragend', function () { edit.targets = null; syncEditor(true); });
    }

    function deleteVertex(pi, ri, vi) {
        if (!edit || edit.saving) return;
        var rings = edit.parts[pi], ring = rings[ri];
        pushHistory();
        if (ring.length > 3) ring.splice(vi, 1);
        else if (ri > 0) rings.splice(ri, 1);
        else if (edit.parts.length > 1) edit.parts.splice(pi, 1);
        else {
            edit.history.pop();
            toast('An outline needs at least 3 points. Use Remove region to clear it.');
            return;
        }
        syncEditor(true);
    }

    function addDrawPoint(latlng) {
        var last = edit.draw[edit.draw.length - 1];
        if (last && map.latLngToContainerPoint([last[1], last[0]]).distanceTo(map.latLngToContainerPoint(latlng)) < 4) return;
        pushHistory();
        edit.targets = collectSnapTargets();
        var ll = snapLatLng(latlng);
        edit.targets = null;
        edit.draw.push([ll.lng, ll.lat]);
        syncEditor(true);
    }

    function finishDraw() {
        if (!edit || edit.mode !== 'draw') return;
        if (edit.draw.length < 3) { toast('Add at least 3 points to close the outline.'); return; }
        pushHistory();
        edit.parts.push([edit.draw]);
        edit.draw = [];
        edit.mode = 'edit';
        syncEditor(true);
    }

    function startBox() {
        if (!edit) return;
        pushHistory();
        var b = map.getBounds(), c = map.getCenter();
        var ring = G.rectangle([c.lng, c.lat], (b.getEast() - b.getWest()) * 0.16, (b.getNorth() - b.getSouth()) * 0.16);
        edit.parts.push([ring]);
        edit.draw = [];
        edit.mode = 'edit';
        syncEditor(true);
    }

    function startPart() {
        if (!edit || edit.mode === 'draw') return;
        pushHistory();
        edit.mode = 'draw';
        edit.draw = [];
        syncEditor(true);
        toast('Click the map to draw another part of this brick.');
    }

    function findOverlaps() {
        if (!edit.parts.length) return [];
        var names = [], box = G.bbox(edit.parts);
        Object.keys(index.bricks).forEach(function (id) {
            var e = index.bricks[id];
            if (id === edit.id || !e.parts.length || e.b.isActive === false || !G.boxesOverlap(box, e.box)) return;
            if (G.overlaps(edit.parts, e.parts)) names.push(e.b.name);
        });
        return names;
    }

    function problems() {
        var out = [];
        if (G.crossesItself(edit.parts)) out.push('The outline crosses itself. Move the points so the lines do not cross.');
        if (G.vertexCount(edit.parts) > G.MAX_POINTS) out.push('More than ' + G.MAX_POINTS.toLocaleString() + ' points. Remove some points.');
        return out;
    }

    function updateStats() {
        var n = G.vertexCount(edit.parts) + edit.draw.length, area = G.areaKm2(edit.parts);
        $('zoneStats').textContent = (edit.parts.length ? fmtArea(area) + ' km² · ' : '') + n + ' points' +
            (edit.parts.length > 1 ? ' · ' + edit.parts.length + ' parts' : '');
    }

    function updateBar() {
        $('zoneTitle').textContent = (edit.mode === 'draw' ? 'Draw the region of ' : 'Edit the region of ') + edit.name;
        $('zoneHint').textContent = edit.mode === 'draw'
            ? 'Click the map to add points. Click the first point, double-click, or press Enter to close the outline.'
            : edit.tooMany
                ? 'Zoom in to move single points.'
                : 'Drag a point to move it, drag a small dot to add one, right-click a point to delete it. Use the arrows to move the region and the round handle to turn or resize it.';
        updateStats();
        var issues = problems(), warn = issues.slice();
        if (edit.overlaps.length) warn.push('Overlaps ' + edit.overlaps.slice(0, 3).join(', ') + (edit.overlaps.length > 3 ? ' and ' + (edit.overlaps.length - 3) + ' more' : '') + '. Clients in shared areas go to the smaller brick.');
        if (edit.error) warn.unshift(edit.error);
        var w = $('zoneWarn');
        w.textContent = warn.join(' ');
        w.hidden = !warn.length;
        w.classList.toggle('is-block', issues.length > 0 || !!edit.error);
        $('zoneFinish').hidden = edit.mode !== 'draw';
        $('zoneFinish').disabled = edit.draw.length < 3;
        $('zoneBox').hidden = edit.mode !== 'draw' || edit.draw.length > 0;
        $('zonePart').hidden = edit.mode !== 'edit' || !edit.parts.length;
        $('zoneUndo').disabled = !edit.history.length || edit.saving;
        $('zoneRemove').hidden = !edit.hadRegion;
        $('zoneRemove').textContent = edit.removeArmed ? 'Click again to remove' : 'Remove region';
        $('zoneSave').disabled = edit.saving || edit.mode === 'draw' || !edit.parts.length || issues.length > 0;
        $('zoneSave').textContent = edit.saving ? 'Saving…' : 'Save region';
        $('zoneCancel').disabled = edit.saving;
    }

    function saveEdit() {
        if (!edit || edit.saving || $('zoneSave').disabled) return;
        edit.saving = true;
        edit.error = null;
        updateBar();
        post({ type: 'HOST_REGION_SAVE', id: edit.id, geometry: G.toGeometry(edit.parts), source: edit.source });
    }

    function removeRegion() {
        if (!edit || edit.saving) return;
        if (!edit.removeArmed) {
            edit.removeArmed = true;
            updateBar();
            clearTimeout(removeRegion._t);
            removeRegion._t = setTimeout(function () { if (edit) { edit.removeArmed = false; updateBar(); } }, 3500);
            return;
        }
        edit.saving = true;
        updateBar();
        post({ type: 'HOST_REGION_SAVE', id: edit.id, geometry: null, source: null });
    }

    function cancelEdit() {
        if (!edit || edit.saving) return;
        var id = edit.id;
        stopEdit();
        post({ type: 'HOST_EDIT_CANCEL', id: id });
    }

    function editError(message) {
        if (!edit) { toast(message || 'The region could not be saved.'); return; }
        edit.saving = false;
        edit.removeArmed = false;
        edit.error = message || 'The region could not be saved.';
        updateBar();
    }

    /* ---------- controls ---------- */
    function setBtn(act, on) {
        var el = document.querySelector('[data-act="' + act + '"]');
        if (!el) return;
        el.classList.toggle('is-on', !!on);
        el.setAttribute('aria-pressed', on ? 'true' : 'false');
    }

    function setBaseMap(kind) {
        var sat = kind === 'satellite';
        if (sat === map.hasLayer(layers.satellite)) return;
        if (sat) { map.addLayer(layers.satellite); map.removeLayer(layers.streets); }
        else { map.addLayer(layers.streets); map.removeLayer(layers.satellite); }
        setBtn('streets', !sat);
        setBtn('satellite', sat);
        $('stage').classList.toggle('is-sat', sat);
    }

    function bindControls() {
        document.querySelectorAll('[data-act]').forEach(function (el) {
            el.addEventListener('click', function () {
                var act = el.getAttribute('data-act');
                if (act === 'in') map.zoomIn();
                if (act === 'out') map.zoomOut();
                if (act === 'home') flyHome();
                if (act === 'streets' || act === 'satellite') setBaseMap(act);
                if (act === 'points') setPoints(!state.showPoints);
                if (act === 'locate') { if (!edit) setLocate(!locate.on); }
            });
        });
        $('zoneSave').addEventListener('click', saveEdit);
        $('zoneCancel').addEventListener('click', cancelEdit);
        $('zoneRemove').addEventListener('click', removeRegion);
        $('zoneUndo').addEventListener('click', undo);
        $('zoneFinish').addEventListener('click', finishDraw);
        $('zoneBox').addEventListener('click', startBox);
        $('zonePart').addEventListener('click', startPart);
        $('snap').addEventListener('change', function (e) { if (edit) edit.snap = e.target.checked; });
        document.addEventListener('keydown', function (e) {
            var mod = e.metaKey || e.ctrlKey;
            if (edit && mod && (e.key === 'z' || e.key === 'Z')) { e.preventDefault(); undo(); return; }
            if (edit && edit.mode === 'draw' && e.key === 'Enter') { e.preventDefault(); finishDraw(); return; }
            if (edit && edit.mode === 'draw' && (e.key === 'Backspace' || e.key === 'Delete') && edit.draw.length) { e.preventDefault(); undo(); return; }
            if (e.key === 'Escape') {
                if (locate.on) { setLocate(false); return; }
                if (edit && edit.mode === 'draw' && edit.parts.length) { edit.draw = []; edit.mode = 'edit'; syncEditor(true); return; }
                if (edit) cancelEdit();
            }
        });
    }

    function onMapClick(e) {
        if (edit) {
            if (edit.mode === 'draw' && !edit.saving) addDrawPoint(e.latlng);
            return;
        }
        if (locate.on) locateAt(e.latlng);
    }

    function onMapMove(e) {
        if (!edit || edit.mode !== 'draw' || !edit.draw.length) return;
        var pts = edit.draw.map(function (p) { return [p[1], p[0]]; });
        pts.push(e.latlng);
        edit.drawLine.setLatLngs(pts);
    }

    // Leaflet's wheel zoom jumps between snapped levels; this eases toward the target zoom every frame instead.
    var WHEEL_ZOOM_PER_PX = 0.0055, WHEEL_EASE = 0.22, WHEEL_IDLE_MS = 500;
    function bindSmoothWheel(m) {
        var w = null;
        function frame() {
            if (!w) return;
            var z = m.getZoom();
            if (!m.getCenter().equals(w.center) || z !== w.zoom) { w.raf = null; return; }
            var next = Math.abs(w.goal - z) < 0.004 ? w.goal : z + (w.goal - z) * WHEEL_EASE;
            var offset = w.mouse.subtract(m.getSize()._divideBy(2));
            var center = m.unproject(m.project(w.anchor, next).subtract(offset), next);
            if (!w.moved) { m._moveStart(true, false); w.moved = true; }
            m._move(center, next);
            w.center = m.getCenter(); w.zoom = m.getZoom();
            w.raf = next === w.goal ? null : requestAnimationFrame(frame);
        }
        function end() {
            if (!w) return;
            if (w.raf) { w.timer = setTimeout(end, 100); return; }
            var moved = w.moved;
            w = null;
            if (moved) m._moveEnd(true);
        }
        L.DomEvent.on(m.getContainer(), 'wheel', function (e) {
            L.DomEvent.preventDefault(e);
            L.DomEvent.stopPropagation(e);
            var dy = e.deltaY * (e.deltaMode === 1 ? 40 : e.deltaMode === 2 ? 800 : 1);
            dy = Math.max(-160, Math.min(160, dy));
            if (!w) {
                m._stop();
                w = { goal: m.getZoom(), center: m.getCenter(), zoom: m.getZoom(), moved: false, raf: null };
            }
            w.mouse = m.mouseEventToContainerPoint(e);
            w.anchor = m.containerPointToLatLng(w.mouse);
            w.goal = Math.max(m.getMinZoom(), Math.min(m.getMaxZoom(), w.goal - dy * WHEEL_ZOOM_PER_PX));
            if (!w.raf) w.raf = requestAnimationFrame(frame);
            clearTimeout(w.timer);
            w.timer = setTimeout(end, WHEEL_IDLE_MS);
        });
    }

    function init(d) {
        L = window.L;
        map = L.map('map', {
            zoomControl: false, attributionControl: false, zoomSnap: 0.25, zoomDelta: 1,
            scrollWheelZoom: false, minZoom: 5, maxZoom: 19, inertia: true
        }).setView(EGYPT, 6);
        bindSmoothWheel(map);
        layers.streets = L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, maxNativeZoom: 19, keepBuffer: 3 }).addTo(map);
        layers.satellite = L.tileLayer('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', {
            maxZoom: 19, maxNativeZoom: 18, keepBuffer: 3
        });
        map.createPane('brickContext').style.zIndex = 395;
        map.createPane('brickRegions').style.zIndex = 400;
        map.createPane('brickEdit').style.zIndex = 440;
        map.createPane('brickPoints').style.zIndex = 450;
        renderers.context = L.canvas({ pane: 'brickContext', padding: 0.4 });
        renderers.regions = L.canvas({ pane: 'brickRegions', padding: 0.4, tolerance: 2 });
        renderers.points = L.canvas({ pane: 'brickPoints', padding: 0.4, tolerance: 3 });
        renderers.edit = L.svg({ pane: 'brickEdit', padding: 0.4 });
        layers.context = L.featureGroup().addTo(map);
        layers.regions = L.featureGroup().addTo(map);
        layers.points = L.featureGroup().addTo(map);
        layers.labels = L.layerGroup().addTo(map);

        map.on('click', onMapClick);
        map.on('mousemove', onMapMove);
        map.on('dblclick', function () { if (edit && edit.mode === 'draw') finishDraw(); });
        map.on('zoomend moveend', function () {
            renderLabels();
            if (edit && edit.mode === 'edit') { rebuildHandles(); if (edit.parts.length) placeTurn(); updateBar(); }
        });
        window.addEventListener('resize', function () { map.invalidateSize(); });

        bindControls();
        applyData(d, false);
        post({ type: 'HOST_READY' });
        setTimeout(function () {
            if (state.selectedId && index.bricks[state.selectedId] && index.bricks[state.selectedId].parts.length) select(state.selectedId, true);
            else flyHome();
        }, 300);
    }

    window.addEventListener('message', function (e) {
        var d = e.data;
        if (!d || typeof d !== 'object') return;
        if (d.type === 'HOST_INIT') {
            if (e.source !== window.parent) return;
            if (map) { if (e.origin === trustedOrigin) { applyData(d, false); post({ type: 'HOST_READY' }); } return; }
            trustedOrigin = e.origin;
            loadLeaflet(d.leafletBase, function () {
                try { init(d); } catch (err) { post({ type: 'HOST_ERROR', message: err && err.message ? err.message : String(err) }); }
            });
            return;
        }
        if (!trustedOrigin || e.origin !== trustedOrigin || e.source !== window.parent || !map) return;
        if (d.type === 'HOST_UPDATE') applyData(d, !!d.fit);
        if (d.type === 'HOST_SELECT') select(d.id, d.fly !== false);
        if (d.type === 'HOST_EDIT') startEdit(d);
        if (d.type === 'HOST_EDIT_END') { stopEdit(); if (d.message) toast(d.message); }
        if (d.type === 'HOST_EDIT_ERROR') editError(d.message);
        if (d.type === 'HOST_LOCATE') setLocate(!!d.on);
        if (d.type === 'HOST_LOCATE_RESULT') locateResult(d);
        if (d.type === 'HOST_POINTS') setPoints(!!d.on);
        if (d.type === 'HOST_HEAT') { state.heat = d.heat || null; renderRegions(); renderLegend(); }
        if (d.type === 'HOST_DESTROY') { stopEdit(); map.remove(); map = null; }
    });
})();
