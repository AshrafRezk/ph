import { makeDualApex } from './_wireAdapter.js';
import { API_VERSION, currentUserId, esc, mapCurriculumItem, soqlOne } from './learningShared.js';
import { plannerApiFetch } from './restHelper.js';

async function startLesson(params) {
    const instanceId = params && (params.instanceId || params.Id);
    if (!instanceId) {
        return null;
    }
    const userId = currentUserId();
    const inst = await soqlOne(
        'SELECT Id, Status__c, Progress__c, Score__c, Material__c, Material__r.Title__c, ' +
            'Material__r.Material_Type__c, Material__r.Material_URL__c, Material__r.Duration__c, Started_On__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(instanceId)}' AND Learner__c = '${esc(userId)}' LIMIT 1`
    );
    if (!inst) {
        return null;
    }
    const fields = {};
    if (!inst.Started_On__c) {
        fields.Started_On__c = new Date().toISOString();
    }
    if (!inst.Status__c || inst.Status__c === 'Not Started') {
        fields.Status__c = 'In Progress';
        inst.Status__c = 'In Progress';
    }
    if (Object.keys(fields).length) {
        try {
            await plannerApiFetch(
                `/services/data/${API_VERSION}/sobjects/Learning_Material_Instance__c/${inst.Id}`,
                {
                    method: 'PATCH',
                    body: JSON.stringify(fields)
                }
            );
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
