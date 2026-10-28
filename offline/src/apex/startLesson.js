import { makeDualApex } from './_wireAdapter.js';
import { mapCurriculumItem, nowIso, patchLearningInstance, requireOwnInstance } from './learningShared.js';

async function startLesson(params) {
    const instanceId = params && (params.instanceId || params.Id);
    if (!instanceId) {
        return null;
    }
    let inst;
    try {
        inst = await requireOwnInstance(instanceId);
    } catch (_err) {
        return null;
    }
    const fields = {};
    if (!inst.Started_On__c) {
        fields.Started_On__c = nowIso();
    }
    if (!inst.Status__c || inst.Status__c === 'Not Started') {
        fields.Status__c = 'In Progress';
        inst.Status__c = 'In Progress';
    }
    if (Object.keys(fields).length) {
        try {
            await patchLearningInstance(inst.Id, fields);
        } catch (_err) {
            /* keep local status so the player can continue offline */
        }
    }
    const material = inst.Material__r || {};
    return mapCurriculumItem(
        {
            Id: inst.Material__c,
            Title__c: material.Title__c,
            Material_Type__c: material.Material_Type__c,
            Material_URL__c: material.Material_URL__c,
            Duration__c: material.Duration__c
        },
        inst,
        0
    );
}

export default makeDualApex(startLesson);
