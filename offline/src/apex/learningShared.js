import { plannerApiFetch } from './restHelper.js';

export const API_VERSION = 'v62.0';

export async function soql(query) {
    const path = `/services/data/${API_VERSION}/query?q=${encodeURIComponent(query)}`;
    const result = await plannerApiFetch(path);
    return result && Array.isArray(result.records) ? result.records : [];
}

export async function soqlOne(query) {
    const rows = await soql(query);
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

function asNumber(value) {
    const n = Number(value);
    return Number.isFinite(n) ? n : 0;
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

export async function loadCoursePlayer(courseInstanceId, selectedMaterialId) {
    const userId = currentUserId();
    if (!courseInstanceId || !userId) {
        return null;
    }
    const courseInst = await soqlOne(
        'SELECT Id, Status__c, Progress__c, Material__c, Material__r.Title__c, ' +
            'Material__r.Description__c, Material__r.Issue_Certificate__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(courseInstanceId)}' AND Learner__c = '${esc(userId)}' LIMIT 1`
    );
    if (!courseInst) {
        return null;
    }
    const children = await soql(
        'SELECT Id, Title__c, Material_Type__c, Material_URL__c, Duration__c ' +
            'FROM Learning_Material__c ' +
            `WHERE Parent_Material__c = '${esc(courseInst.Material__c)}' AND Active__c = true ` +
            'ORDER BY CreatedDate ASC, Title__c ASC'
    );
    const childIds = children.map((row) => row.Id).filter(Boolean);
    let instances = [];
    if (childIds.length) {
        const idList = childIds.map((id) => `'${esc(id)}'`).join(',');
        instances = await soql(
            'SELECT Id, Material__c, Status__c, Progress__c, Score__c ' +
                'FROM Learning_Material_Instance__c ' +
                `WHERE Learner__c = '${esc(userId)}' AND Material__c IN (${idList})`
        );
    }
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
