import { plannerApiFetch } from './restHelper.js';

export const API_VERSION = 'v62.0';

export function apexError(message) {
    const err = new Error(message || 'Unable to complete learning action.');
    err.body = { message: err.message };
    return err;
}

export async function soql(query, options = {}) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path, options.fresh ? { fresh: true } : {});
    return result && Array.isArray(result.records) ? result.records : [];
}

export async function soqlOne(query, options = {}) {
    const rows = await soql(query, options);
    return rows.length ? rows[0] : null;
}

export function currentUserId() {
    try {
        return (localStorage.getItem('zeta.pwa.sfUserId') || '').trim();
    } catch (_err) {
        return '';
    }
}

export function esc(value) {
    return String(value || '').replace(/'/g, "\\'");
}

export function nowIso() {
    return new Date().toISOString();
}

export function asNumber(value, fallback = 0) {
    const n = Number(value);
    return Number.isFinite(n) ? n : fallback;
}

export async function patchLearningInstance(id, fields) {
    if (!id || !fields || !Object.keys(fields).length) {
        return;
    }
    try {
        await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/Learning_Material_Instance__c/${id}`,
            {
                method: 'PATCH',
                body: JSON.stringify(fields)
            }
        );
    } catch (err) {
        throw apexError(err && err.message ? err.message : String(err));
    }
}

export function mapCourseCard(inst) {
    const material = inst.Material__r || {};
    const status = inst.Status__c || 'Not Started';
    const issueCertificate = material.Issue_Certificate__c === true;
    return {
        instanceId: inst.Id,
        materialId: inst.Material__c,
        title: material.Title__c,
        description: material.Description__c,
        status,
        progress: asNumber(inst.Progress__c),
        issueCertificate,
        canShowCertificate: issueCertificate && status === 'Completed'
    };
}

export function mapCurriculumItem(child, inst, sortOrder) {
    const status = (inst && inst.Status__c) || 'Not Started';
    return {
        materialId: child.Id,
        instanceId: inst ? inst.Id : null,
        title: child.Title__c,
        materialType: child.Material_Type__c,
        status,
        progress: inst && inst.Progress__c != null ? asNumber(inst.Progress__c) : 0,
        score: inst ? inst.Score__c : null,
        materialUrl: child.Material_URL__c,
        duration: child.Duration__c,
        completed: status === 'Completed',
        sortOrder
    };
}

export function parseQuizJson(raw) {
    if (raw == null || raw === '') {
        return { questions: [] };
    }
    if (typeof raw === 'object') {
        return raw;
    }
    try {
        const parsed = JSON.parse(raw);
        if (parsed && typeof parsed === 'object') {
            return parsed;
        }
    } catch (_err) {
        throw apexError('Invalid quiz JSON.');
    }
    throw apexError('Invalid quiz JSON.');
}

function optionLabel(value) {
    if (typeof value === 'string') return value;
    if (value && typeof value === 'object') {
        return String(value.label || value.value || '');
    }
    return String(value == null ? '' : value);
}

export function mapQuizQuestion(raw) {
    const q = raw || {};
    const type = q.type || 'single-choice';
    let options = Array.isArray(q.options) ? q.options.map(optionLabel) : [];
    if (type === 'scale' && !options.length) {
        const min = Number.isFinite(Number(q.scaleMin)) ? Number(q.scaleMin) : 1;
        const max = Number.isFinite(Number(q.scaleMax)) ? Number(q.scaleMax) : 5;
        for (let i = min; i <= max; i += 1) {
            let label = String(i);
            if (i === min && q.scaleMinLabel) label += ` — ${q.scaleMinLabel}`;
            if (i === max && q.scaleMaxLabel) label += ` — ${q.scaleMaxLabel}`;
            options.push(label);
        }
    }
    return {
        id: q.id,
        question: q.question,
        type,
        options,
        points: asNumber(q.points, type === 'scale' ? 10 : 1),
        scaleMin: q.scaleMin,
        scaleMax: q.scaleMax,
        scaleMinLabel: q.scaleMinLabel,
        scaleMaxLabel: q.scaleMaxLabel
    };
}

function toInt(value, fallback) {
    const n = Number(value);
    return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

function asIntSet(value) {
    const set = new Set();
    if (Array.isArray(value)) {
        value.forEach((item) => set.add(toInt(item, -2)));
    } else if (value != null && value !== '') {
        set.add(toInt(value, -2));
    }
    return set;
}

function setsEqual(left, right) {
    if (left.size !== right.size) return false;
    for (const value of left) {
        if (!right.has(value)) return false;
    }
    return true;
}

export function isAnswerCorrect(question, given) {
    const type = question && question.type;
    if (type === 'multiple-choice') {
        return setsEqual(asIntSet(question.correctAnswers), asIntSet(given));
    }
    if (type === 'scale') {
        return given != null && given !== '';
    }
    return toInt(question && question.correctAnswer, -1) === toInt(given, -2);
}

export async function requireOwnInstance(instanceId, extraSelect, options = {}) {
    const userId = currentUserId();
    if (!instanceId || !userId) {
        throw apexError('Learning assignment not found.');
    }
    const extra = extraSelect ? `, ${extraSelect}` : '';
    const inst = await soqlOne(
        'SELECT Id, Status__c, Progress__c, Score__c, Started_On__c, Completed_On__c, Attempt_Number__c, ' +
            'Learner__c, Material__c, ' +
            'Material__r.Title__c, Material__r.Material_Type__c, Material__r.Material_URL__c, ' +
            'Material__r.Duration__c, Material__r.Parent_Material__c, Material__r.Issue_Certificate__c' +
            extra +
            ' FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(instanceId)}' AND Learner__c = '${esc(userId)}' LIMIT 1`,
        options
    );
    if (!inst) {
        throw apexError('Learning assignment not found.');
    }
    return inst;
}

export async function findCourseInstanceId(inst) {
    const materialType = inst.Material__r && inst.Material__r.Material_Type__c;
    const courseMaterialId =
        materialType === 'Course'
            ? inst.Material__c
            : inst.Material__r && inst.Material__r.Parent_Material__c;
    if (!courseMaterialId) {
        return inst.Id;
    }
    const learnerId = inst.Learner__c || currentUserId();
    const course = await soqlOne(
        'SELECT Id FROM Learning_Material_Instance__c ' +
            `WHERE Learner__c = '${esc(learnerId)}' AND Material__c = '${esc(courseMaterialId)}' LIMIT 1`
    );
    return (course && course.Id) || inst.Id;
}

async function loadChildInstances(userId, childIds, fresh) {
    if (!childIds.length) {
        return [];
    }
    const idList = childIds.map((id) => `'${esc(id)}'`).join(',');
    return soql(
        'SELECT Id, Material__c, Status__c, Progress__c, Score__c, Material__r.Material_Type__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Learner__c = '${esc(userId)}' AND Material__c IN (${idList})`,
        { fresh }
    );
}

export async function ensureChildInstances(userId, courseMaterialId) {
    const children = await soql(
        'SELECT Id FROM Learning_Material__c ' +
            `WHERE Parent_Material__c = '${esc(courseMaterialId)}' AND Active__c = true`
    );
    if (!children.length) {
        return false;
    }
    const childIds = children.map((row) => row.Id).filter(Boolean);
    const existing = await loadChildInstances(userId, childIds, false);
    const have = new Set(existing.map((row) => row.Material__c));
    const missing = childIds.filter((id) => !have.has(id));
    if (!missing.length) {
        return false;
    }
    await plannerApiFetch(`/services/data/${API_VERSION}/composite/sobjects`, {
        method: 'POST',
        body: JSON.stringify({
            allOrNone: false,
            records: missing.map((materialId) => ({
                attributes: { type: 'Learning_Material_Instance__c' },
                Learner__c: userId,
                Material__c: materialId,
                Status__c: 'Not Started',
                Progress__c: 0,
                Attempt_Number__c: 0
            }))
        })
    });
    return true;
}

export async function rollupCourseProgress(courseInstanceId) {
    if (!courseInstanceId) {
        return 0;
    }
    const courseInst = await soqlOne(
        'SELECT Id, Material__c, Learner__c, Status__c, Progress__c, Started_On__c, Completed_On__c, Score__c, ' +
            'Material__r.Issue_Certificate__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(courseInstanceId)}' LIMIT 1`,
        { fresh: true }
    );
    if (!courseInst) {
        return 0;
    }
    const children = await soql(
        'SELECT Id FROM Learning_Material__c ' +
            `WHERE Parent_Material__c = '${esc(courseInst.Material__c)}' AND Active__c = true`
    );
    if (!children.length) {
        return asNumber(courseInst.Progress__c);
    }
    const instances = await loadChildInstances(courseInst.Learner__c, children.map((row) => row.Id), true);
    let completed = 0;
    let quizScoreSum = 0;
    let quizScoreCount = 0;
    instances.forEach((childInst) => {
        if (childInst.Status__c === 'Completed') {
            completed += 1;
        }
        const childType = childInst.Material__r && childInst.Material__r.Material_Type__c;
        if (childType === 'Quiz' && childInst.Score__c != null) {
            quizScoreSum += asNumber(childInst.Score__c);
            quizScoreCount += 1;
        }
    });
    const progress = Math.round((completed / children.length) * 100);
    const fields = {
        Progress__c: progress
    };
    if (progress >= 100) {
        fields.Status__c = 'Completed';
        if (!courseInst.Completed_On__c) {
            fields.Completed_On__c = nowIso();
        }
    } else if (!courseInst.Status__c || courseInst.Status__c === 'Not Started') {
        fields.Status__c = 'In Progress';
    } else if (courseInst.Status__c === 'Completed' && progress < 100) {
        fields.Status__c = 'In Progress';
        fields.Completed_On__c = null;
    }
    if (quizScoreCount > 0) {
        fields.Score__c = Math.round((quizScoreSum / quizScoreCount) * 10) / 10;
    }
    if (!courseInst.Started_On__c) {
        fields.Started_On__c = nowIso();
    }
    await patchLearningInstance(courseInst.Id, fields);
    return progress;
}

export async function loadCoursePlayer(courseInstanceId, selectedMaterialId, options = {}) {
    const userId = currentUserId();
    if (!courseInstanceId || !userId) {
        return null;
    }
    const fresh = options.fresh === true;
    const courseInst = await soqlOne(
        'SELECT Id, Status__c, Progress__c, Material__c, Material__r.Title__c, ' +
            'Material__r.Description__c, Material__r.Issue_Certificate__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(courseInstanceId)}' AND Learner__c = '${esc(userId)}' LIMIT 1`,
        { fresh }
    );
    if (!courseInst) {
        return null;
    }
    try {
        const created = await ensureChildInstances(userId, courseInst.Material__c);
        if (created) {
            // Newly inserted lesson rows must be queried, not served from cache.
            options = { ...options, fresh: true };
        }
    } catch (_err) {
        /* curriculum still loads for assignments that already exist */
    }
    const queryFresh = options.fresh === true;
    const children = await soql(
        'SELECT Id, Title__c, Material_Type__c, Material_URL__c, Duration__c ' +
            'FROM Learning_Material__c ' +
            `WHERE Parent_Material__c = '${esc(courseInst.Material__c)}' AND Active__c = true ` +
            'ORDER BY CreatedDate ASC, Title__c ASC',
        { fresh: queryFresh }
    );
    const childIds = children.map((row) => row.Id).filter(Boolean);
    const instances = await loadChildInstances(userId, childIds, queryFresh);
    const byMaterial = new Map();
    instances.forEach((row) => {
        if (row.Material__c) byMaterial.set(row.Material__c, row);
    });

    const curriculum = children.map((child, index) =>
        mapCurriculumItem(child, byMaterial.get(child.Id), index)
    );

    let selectedInstanceId = null;
    if (selectedMaterialId) {
        const match = curriculum.find((item) => item.materialId === selectedMaterialId);
        if (match) selectedInstanceId = match.instanceId;
    }
    if (!selectedInstanceId) {
        const next = curriculum.find((item) => !item.completed && item.instanceId);
        selectedInstanceId = (next && next.instanceId) || (curriculum[0] && curriculum[0].instanceId) || null;
    }

    const material = courseInst.Material__r || {};
    const status = courseInst.Status__c || 'Not Started';
    const issueCertificate = material.Issue_Certificate__c === true;
    return {
        courseInstanceId: courseInst.Id,
        courseMaterialId: courseInst.Material__c,
        title: material.Title__c,
        description: material.Description__c,
        status,
        progress: asNumber(courseInst.Progress__c),
        issueCertificate,
        canShowCertificate: issueCertificate && status === 'Completed',
        curriculum,
        selectedInstanceId
    };
}
