import { makeDualApex } from './_wireAdapter.js';
import getRepPresentations from './getRepPresentations.js';

// Offline stand-in for ClmMetricsController.getAvailablePresentations (@wire in
// clmVisitPresentations). Includes PDF and HTML decks.
export default makeDualApex(() => getRepPresentations());
