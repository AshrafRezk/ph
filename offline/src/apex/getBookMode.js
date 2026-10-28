import { plannerApiFetch } from './restHelper.js';

export default async function getBookMode() {
    return plannerApiFetch('/services/apexrest/planner/v1/book-mode');
}
