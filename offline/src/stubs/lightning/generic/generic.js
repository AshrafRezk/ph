import { LightningElement, api } from 'lwc';

/**
 * Catch-all stand-in for Lightning base components that do not yet have a
 * dedicated offline stub. Renders children via the default slot so layouts
 * (accordion, layout, tabset, …) still show their contents.
 */
export default class Generic extends LightningElement {
    @api label = '';
    @api title = '';
    @api name = '';
    @api value;
    @api variant = '';
    @api disabled = false;
    @api checked = false;
    @api required = false;
    @api iconName = '';
    @api alternativeText = '';
    @api size = '';
    @api type = '';
    @api href = '';
    @api src = '';
    @api columns;
    @api groupName = '';
    @api activeSectionName;
    @api allowMultipleSectionsOpen = false;
    @api selectedTabOnInvalid = false;
}
