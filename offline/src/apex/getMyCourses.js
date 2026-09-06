import { makeDualApex } from './_wireAdapter.js';
import { currentUserId, esc, mapCourseCard, soql } from './learningShared.js';

async function loadMyCourses() {
    const userId = currentUserId();
    if (!userId) {
        return [];
    }
    const rows = await soql(
        'SELECT Id, Status__c, Progress__c, Material__c, Material__r.Title__c, ' +
            'Material__r.Description__c, Material__r.Issue_Certificate__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Learner__c = '${esc(userId)}' AND Material__r.Material_Type__c = 'Course' ` +
            'ORDER BY Material__r.Title__c'
    );
    return rows.map(mapCourseCard);
}

export default makeDualApex(loadMyCourses);
