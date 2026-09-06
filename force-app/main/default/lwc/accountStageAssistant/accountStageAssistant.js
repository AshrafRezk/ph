import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import getStage from "@salesforce/apex/AccountStageService.getStage";
import advance from "@salesforce/apex/AccountStageService.advance";
import sendBack from "@salesforce/apex/AccountStageService.sendBack";
import markInactive from "@salesforce/apex/AccountStageService.markInactive";
import markDuplicate from "@salesforce/apex/AccountStageService.markDuplicate";

export default class AccountStageAssistant extends LightningElement {
  @api recordId;

  @track view;
  @track errorMessage;
  @track isLoading = true;
  @track isSaving = false;
  @track showSendBack = false;
  @track showInactive = false;
  @track showDuplicate = false;
  @track sendBackMessage = "";
  @track inactiveReason = "";
  @track duplicateOfId;

  connectedCallback() {
    this.load();
  }

  get duplicateFilter() {
    if (!this.recordId) {
      return undefined;
    }
    return {
      criteria: [
        {
          fieldPath: "Id",
          operator: "ne",
          value: this.recordId
        }
      ]
    };
  }

  get steps() {
    return (this.view?.steps || []).map((step) => {
      const classes = ["slds-path__item"];
      if (step.current && step.terminal) {
        classes.push("slds-is-current", "slds-is-active", "path-terminal");
      } else if (step.current) {
        classes.push("slds-is-current", "slds-is-active");
      } else if (step.complete) {
        classes.push("slds-is-complete");
      } else {
        classes.push("slds-is-incomplete");
      }
      return { ...step, itemClass: classes.join(" ") };
    });
  }

  get lastMessage() {
    return this.view?.lastMessage;
  }

  get historyLines() {
    const history = this.view?.history;
    if (!history) {
      return [];
    }
    return history
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line)
      .reverse()
      .slice(0, 6)
      .map((line, index) => ({ key: String(index), line }));
  }

  get hasHistory() {
    return this.historyLines.length > 0;
  }

  get advanceDisabled() {
    return !this.view?.canAdvance || this.isSaving;
  }

  get sendBackActionDisabled() {
    return !this.view?.canSendBack || this.isSaving;
  }

  get advanceLabel() {
    return this.view?.nextLabel ? `Advance to ${this.view.nextLabel}` : "Advance";
  }

  get sendBackLabel() {
    return this.view?.previousLabel ? `Send back to ${this.view.previousLabel}` : "Send back";
  }

  get inactiveOptions() {
    return (this.view?.inactiveReasons || []).map((option) => ({
      label: option.label,
      value: option.apiName
    }));
  }

  get duplicateHint() {
    return this.view?.duplicateOfName
      ? `Currently linked to ${this.view.duplicateOfName}`
      : "";
  }

  get markInactiveDisabled() {
    return this.isSaving || this.view?.currentApi === "Inactive";
  }

  get markDuplicateDisabled() {
    return this.isSaving || this.view?.currentApi === "Duplicate";
  }

  get sendBackDisabled() {
    return this.isSaving || !this.sendBackMessage?.trim();
  }

  get inactiveDisabled() {
    return this.isSaving || !this.inactiveReason;
  }

  get duplicateDisabled() {
    return this.isSaving || !this.duplicateOfId;
  }

  async load() {
    this.isLoading = true;
    this.errorMessage = undefined;
    try {
      this.view = await getStage({ accountId: this.recordId });
    } catch (error) {
      this.errorMessage = this.readError(error);
    } finally {
      this.isLoading = false;
    }
  }

  openSendBack() {
    this.sendBackMessage = "";
    this.showSendBack = true;
  }

  openInactive() {
    this.inactiveReason = this.view?.inactiveReason || "";
    this.showInactive = true;
  }

  openDuplicate() {
    this.duplicateOfId = this.view?.duplicateOfId;
    this.showDuplicate = true;
  }

  closeModals() {
    this.showSendBack = false;
    this.showInactive = false;
    this.showDuplicate = false;
  }

  handleSendBackChange(event) {
    this.sendBackMessage = event.target.value;
  }

  handleInactiveChange(event) {
    this.inactiveReason = event.detail.value;
  }

  handleDuplicatePick(event) {
    this.duplicateOfId = event.detail.recordId;
  }

  async handleAdvance() {
    await this.runAction(() => advance({ accountId: this.recordId }), "Stage advanced");
  }

  async handleConfirmSendBack() {
    await this.runAction(
      () => sendBack({ accountId: this.recordId, message: this.sendBackMessage }),
      "Account thrown back one stage"
    );
    this.closeModals();
  }

  async handleConfirmInactive() {
    await this.runAction(
      () => markInactive({ accountId: this.recordId, reason: this.inactiveReason }),
      "Account marked inactive"
    );
    this.closeModals();
  }

  async handleConfirmDuplicate() {
    await this.runAction(
      () => markDuplicate({ accountId: this.recordId, duplicateOfId: this.duplicateOfId }),
      "Account marked as duplicate"
    );
    this.closeModals();
  }

  async runAction(action, successTitle) {
    this.isSaving = true;
    this.errorMessage = undefined;
    try {
      this.view = await action();
      this.dispatchEvent(
        new ShowToastEvent({
          title: successTitle,
          message: this.view.currentLabel,
          variant: "success"
        })
      );
      await notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
    } catch (error) {
      this.errorMessage = this.readError(error);
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Stage update failed",
          message: this.errorMessage,
          variant: "error"
        })
      );
    } finally {
      this.isSaving = false;
    }
  }

  readError(error) {
    if (typeof error === "string") {
      return error;
    }
    return error?.body?.message || error?.message || "Something went wrong.";
  }
}
