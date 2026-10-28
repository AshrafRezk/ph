import { plannerApiFetch } from './restHelper.js';

export default async function getMeetingRecordTypes() {
    return plannerApiFetch('/services/apexrest/planner/v1/meetings/record-types');
}
