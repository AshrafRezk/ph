import { createApexInvoker } from '@osr/platform';
import { LightningElement, api } from 'lwc';

/** Spike: trivial LWC for iframe engine. */
export default class HelloOsr extends LightningElement {
  @api name = 'Offline LWC Engine';
}
