import { makeDualApex } from './_wireAdapter.js';

export default makeDualApex(async () => {
    throw { body: { message: 'Quiz submission is available in Salesforce while online.' } };
});
