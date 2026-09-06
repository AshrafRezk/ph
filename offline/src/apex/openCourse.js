import { makeDualApex } from './_wireAdapter.js';
import { loadCoursePlayer } from './learningShared.js';

async function openCourse(params) {
    const courseInstanceId = params && (params.courseInstanceId || params.Id);
    const selectedMaterialId = params && params.selectedMaterialId;
    return loadCoursePlayer(courseInstanceId, selectedMaterialId);
}

export default makeDualApex(openCourse);
