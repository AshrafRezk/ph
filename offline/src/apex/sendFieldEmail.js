import { makeDualApex } from './_wireAdapter.js';
import { apexError } from './learningShared.js';
import { requireUnlockedVisit, createSObject } from './fieldWorkflowShared.js';

export default makeDualApex(async (params = {}) => {
    const visit = await requireUnlockedVisit(params.visitId);
    const toAddress = String(params.toAddress || '').trim();
    const subject = String(params.subject || '').trim();
    const body = String(params.body || '').trim();
    if (!toAddress.includes('@')) {
        throw apexError('Enter a valid email address.');
    }
    if (!subject) {
        throw apexError('Enter a subject.');
    }
    if (!body) {
        throw apexError('Enter a message.');
    }
    await createSObject('Task', {
        Subject: subject,
        Description: `To: ${toAddress}\n\n${body}`,
        Status: 'Completed',
        Priority: 'Normal',
        WhatId: visit.Id,
        ActivityDate: new Date().toISOString().slice(0, 10)
    });
    return { queued: true };
});
