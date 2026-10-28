import { makeDualApex } from './_wireAdapter.js';
import {
    apexError,
    findCourseInstanceId,
    loadCoursePlayer,
    nowIso,
    patchLearningInstance,
    requireOwnInstance,
    rollupCourseProgress
} from './learningShared.js';

async function markLessonComplete(params) {
    const instanceId = params && (params.instanceId || params.Id);
    const inst = await requireOwnInstance(instanceId);
    const materialType = inst.Material__r && inst.Material__r.Material_Type__c;
    if (materialType === 'Quiz') {
        throw apexError('Complete quizzes by submitting the exam.');
    }
    const fields = {
        Status__c: 'Completed',
        Progress__c: 100,
        Completed_On__c: nowIso()
    };
    if (!inst.Started_On__c) {
        fields.Started_On__c = nowIso();
    }
    await patchLearningInstance(inst.Id, fields);
    const courseInstanceId = await findCourseInstanceId(inst);
    await rollupCourseProgress(courseInstanceId);
    const player = await loadCoursePlayer(courseInstanceId || instanceId, inst.Material__c, {
        fresh: true
    });
    if (!player) {
        throw apexError('Unable to refresh the course after completing this lesson.');
    }
    return player;
}

export default makeDualApex(markLessonComplete);
