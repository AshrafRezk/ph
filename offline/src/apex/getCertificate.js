import { makeDualApex } from './_wireAdapter.js';
import { currentUserId, esc, soqlOne } from './learningShared.js';

async function getCertificate(params) {
    const courseInstanceId = params && (params.courseInstanceId || params.Id);
    const userId = currentUserId();
    if (!courseInstanceId || !userId) {
        throw { body: { message: 'Certificate is not available yet.' } };
    }
    const courseInst = await soqlOne(
        'SELECT Id, Status__c, Score__c, Completed_On__c, Learner__r.Name, ' +
            'Material__r.Title__c, Material__r.Issue_Certificate__c, ' +
            'Material__r.Certificate_Logo_URL__c, Material__r.Certificate_Template__c ' +
            'FROM Learning_Material_Instance__c ' +
            `WHERE Id = '${esc(courseInstanceId)}' AND Learner__c = '${esc(userId)}' LIMIT 1`
    );
    if (
        !courseInst ||
        courseInst.Status__c !== 'Completed' ||
        !(courseInst.Material__r && courseInst.Material__r.Issue_Certificate__c === true)
    ) {
        throw { body: { message: 'Certificate is not available yet.' } };
    }
    const material = courseInst.Material__r || {};
    const learner = courseInst.Learner__r || {};
    const completedOn = courseInst.Completed_On__c
        ? new Date(courseInst.Completed_On__c).toLocaleDateString()
        : '';
    const learnerName = learner.Name || '';
    const courseTitle = material.Title__c || '';
    const score = courseInst.Score__c;
    const renderedHtml =
        `<div style="padding:2rem;text-align:center;font-family:Georgia,serif">` +
        `<h1>Certificate of Completion</h1>` +
        `<p>${learnerName}</p>` +
        `<p>has completed</p>` +
        `<h2>${courseTitle}</h2>` +
        `<p>${completedOn}</p>` +
        (score != null ? `<p>Score: ${score}</p>` : '') +
        `</div>`;
    return {
        learnerName,
        courseTitle,
        completedOn,
        score,
        logoUrl: material.Certificate_Logo_URL__c,
        templateHtml: material.Certificate_Template__c,
        renderedHtml
    };
}

export default makeDualApex(getCertificate);
