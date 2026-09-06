import { makeDualApex } from './_wireAdapter.js';
import { API_VERSION, currentUserId, esc, loadCoursePlayer, soqlOne } from './learningShared.js';
import { plannerApiFetch } from './restHelper.js';

async function markLessonComplete(params) {
    const instanceId = params && (params.instanceId || params.Id);
    if (!instanceId) {
        return null;
    }
    const userId = currentUserId();
    const inst = await soqlOne(
        'SELECT Id, Material__c, Material__r.Material_Type__c, Material__r.Parent_Material__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(instanceId)}' AND Learner__c = '${esc(userId)}' LIMIT 1`
    );
    if (!inst) {
        return null;
    }
    const materialType = inst.Material__r && inst.Material__r.Material_Type__c;
    if (materialType === 'Quiz') {
        throw { body: { message: 'Complete quizzes by submitting the exam.' } };
    }
    try {
        await plannerApiFetch(
            `/services/data/${API_VERSION}/sobjects/Learning_Material_Instance__c/${inst.Id}`,
            {
                method: 'PATCH',
                body: JSON.stringify({
                    Status__c: 'Completed',
                    Progress__c: 100,
                    Completed_On__c: new Date().toISOString()
                })
            }
        );
    } catch (_err) {
        /* player still refreshes from last known course payload */
    }
    const parentMaterialId = inst.Material__r && inst.Material__r.Parent_Material__c;
    let courseInstanceId = null;
    if (parentMaterialId) {
        const course = await soqlOne(
            'SELECT Id FROM Learning_Material_Instance__c ' +
                `WHERE Learner__c = '${esc(userId)}' AND Material__c = '${esc(parentMaterialId)}' LIMIT 1`
        );
        courseInstanceId = course && course.Id;
    }
    return loadCoursePlayer(courseInstanceId || instanceId, inst.Material__c);
}

export default makeDualApex(markLessonComplete);
