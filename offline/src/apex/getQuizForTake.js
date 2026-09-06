import { makeDualApex } from './_wireAdapter.js';

export default makeDualApex(async () => {
    throw { body: { message: 'Quizzes can be taken in Salesforce while online.' } };
});
