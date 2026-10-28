export function buildPrefillComment(context) {
    const source = context || {};
    const parts = [];
    if (source.accountName) {
        parts.push(`Account: ${source.accountName}`);
    }
    if (source.visitObjective) {
        parts.push(`Visit objective: ${source.visitObjective}`);
    }
    if (source.visitNotes) {
        parts.push(`Visit notes: ${source.visitNotes}`);
    }
    return parts.length ? parts.join('\n') : 'Coaching session.';
}

export function buildCoachingResponses(templateJson, context, prefillFromVisit) {
    const answers = [];
    if (prefillFromVisit === true && templateJson) {
        try {
            const parsed = JSON.parse(templateJson);
            const questions = Array.isArray(parsed?.questions) ? parsed.questions : [];
            const questionId = questions[0] && questions[0].id;
            if (questionId) {
                answers.push({
                    questionId,
                    managerComments: buildPrefillComment(context)
                });
            }
        } catch (_error) {
            /* keep empty answers when the template JSON cannot be parsed */
        }
    }
    const payload = {
        version: '1.0',
        answers
    };
    if (prefillFromVisit === true) {
        payload.prefillSource = 'visit';
        payload.prefilledAt = new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
    }
    return JSON.stringify(payload);
}

export function readCreatedCoachingEventId(result) {
    if (result == null || typeof result !== 'object') {
        return null;
    }
    return result.coachingEventId || result.id || result.Id || null;
}

function questionMaxPoints(question) {
    const points = Array.isArray(question?.scalePoints) ? question.scalePoints : [];
    let maxWeight = 0;
    points.forEach((point) => {
        const weight = Number(point?.weight || 0);
        if (weight > maxWeight) {
            maxWeight = weight;
        }
    });
    if (!maxWeight && question?.points != null) {
        maxWeight = Number(question.points) || 0;
    }
    return maxWeight;
}

function scaleScore(question, response, valueField) {
    if (!response || response[valueField] == null) {
        return 0;
    }
    const selected = Number(response[valueField]);
    const points = Array.isArray(question?.scalePoints) ? question.scalePoints : [];
    const match = points.find((point) => Number(point?.value) === selected);
    return match ? Number(match.weight || 0) : 0;
}

export function computeCoachingScores(templateJson, responsesJson) {
    const result = {
        managerTotalScore: 0,
        employeeTotalScore: 0,
        sectionScoresJson: '{}',
        recommendedActionPlan: ''
    };
    let template = {};
    try {
        template = templateJson ? JSON.parse(templateJson) : {};
    } catch (_error) {
        return result;
    }
    const questions = Array.isArray(template.questions) ? template.questions : [];
    if (!questions.length) {
        return result;
    }
    const responseMap = {};
    try {
        const parsed = responsesJson ? JSON.parse(responsesJson) : {};
        (parsed.answers || []).forEach((answer) => {
            if (answer?.questionId) {
                responseMap[answer.questionId] = answer;
            }
        });
    } catch (_error) {
        /* score against an empty response map */
    }

    let managerEarned = 0;
    let employeeEarned = 0;
    let totalMax = 0;
    questions.forEach((question) => {
        if (question?.type !== 'scale') {
            return;
        }
        const maxPoints = questionMaxPoints(question);
        totalMax += maxPoints;
        const response = responseMap[question.id];
        managerEarned += scaleScore(question, response, 'managerValue');
        employeeEarned += scaleScore(question, response, 'employeeValue');
    });
    if (totalMax > 0) {
        result.managerTotalScore = Math.round((managerEarned / totalMax) * 10000) / 100;
        result.employeeTotalScore = Math.round((employeeEarned / totalMax) * 10000) / 100;
    }
    return result;
}
