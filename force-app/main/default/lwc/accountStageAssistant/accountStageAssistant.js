import advance from "@salesforce/apex/AccountStageService.advance";
import getStage from "@salesforce/apex/AccountStageService.getStage";
import markDuplicate from "@salesforce/apex/AccountStageService.markDuplicate";
import markInactive from "@salesforce/apex/AccountStageService.markInactive";
import sendBack from "@salesforce/apex/AccountStageService.sendBack";
import skipTo from "@salesforce/apex/AccountStageService.skipTo";
import { LightningElement, api, track } from "lwc";
import { notifyRecordUpdateAvailable } from "lightning/uiRecordApi";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

export default class AccountStageAssistant extends LightningElement {
  @api recordId;

  @track view;
  @track errorMessage;
  @track isLoading = true;
  @track isSaving = false;
  @track showSendBack = false;
  @track showInactive = false;
  @track showDuplicate = false;
  @track showMoreMenu = false;
  @track showHistory = false;
  @track sendBackMessage = "";
  @track inactiveReason = "";
  @track duplicateOfId;

  connectedCallback() {
    this.load();
  }

  renderedCallback() {
    const api = this.view?.currentApi;
    if (!api || this._pathScrolledFor === api || this._pathScrollPending === api) {
      return;
    }
    this._pathScrollPending = api;
    this.scrollCurrentStage(api, 0);
  }

  scrollCurrentStage(api, attempt) {
    if (this._pathScrolledFor === api || this.view?.currentApi !== api) {
      return;
    }
    const scroller = this.template.querySelector(".slds-path__scroller_inner");
    const current = this.template.querySelector(".slds-is-current");
    const ready = scroller && current && scroller.clientWidth > 40;
    if (!ready) {
      if (attempt < 10) {
        window.setTimeout(() => this.scrollCurrentStage(api, attempt + 1), 150);
      }
      return;
    }
    const max = Math.max(0, scroller.scrollWidth - scroller.clientWidth);
    const target = Math.min(max, Math.max(0, current.offsetLeft - 12));
    scroller.scrollLeft = target;
    this._pathScrolledFor = api;
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

  get waitingOnLabel() {
    return this.view?.waitingOn ? `Waiting on SFE: ${this.view.waitingOn}` : "";
  }

  get historyEntries() {
    const history = this.view?.history;
    if (!history) {
      return [];
    }
    return history
      .split("\n")
      .map((line) => line.trim())
      .filter((line) => line)
      .reverse()
      .slice(0, 8)
      .map((line, index) => this.parseHistoryLine(line, index));
  }

  get showHistoryButton() {
    return Boolean(this.lastMessage) || this.historyEntries.length > 0;
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

  get skipTargets() {
    return this.view?.skipTargets || [];
  }

  get hasSkipTargets() {
    return this.skipTargets.length > 0;
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

  get canMarkInactive() {
    return this.view?.canMarkInactive === true;
  }

  get canMarkDuplicate() {
    return this.view?.canMarkDuplicate === true;
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
    this.showMoreMenu = false;
    this.sendBackMessage = "";
    this.showSendBack = true;
  }

  openInactive() {
    this.showMoreMenu = false;
    this.inactiveReason = this.view?.inactiveReason || "";
    this.showInactive = true;
  }

  openDuplicate() {
    this.showMoreMenu = false;
    this.duplicateOfId = this.view?.duplicateOfId;
    this.showDuplicate = true;
  }

  handleToggleMore() {
    this.showMoreMenu = !this.showMoreMenu;
    if (this.showMoreMenu) {
      this.showHistory = false;
    }
  }

  handleToggleHistory() {
    this.showHistory = !this.showHistory;
    if (this.showHistory) {
      this.showMoreMenu = false;
    }
  }

  closeModals() {
    this.showSendBack = false;
    this.showInactive = false;
    this.showDuplicate = false;
    this.showMoreMenu = false;
    this.showHistory = false;
  }

  parseHistoryLine(line, index) {
    const parts = line.split("|").map((part) => part.trim());
    if (parts.length < 4) {
      return {
        key: String(index),
        action: line.replace(/\s\?\s/g, " → "),
        when: "",
        who: "",
        move: "",
        note: "",
        hasWhen: false,
        hasWho: false,
        hasMove: false,
        hasNote: false
      };
    }
    const note = parts.slice(4).filter(Boolean).join(" · ");
    const when = this.formatHistoryStamp(parts[0]);
    const move = (parts[3] || "").replace(/\s\?\s/g, " → ");
    return {
      key: String(index),
      when,
      who: parts[1] || "",
      action: parts[2] || "Updated",
      move,
      note,
      hasWhen: Boolean(when),
      hasWho: Boolean(parts[1]),
      hasMove: Boolean(move),
      hasNote: Boolean(note)
    };
  }

  formatHistoryStamp(stamp) {
    const match = /^(\d{4})-(\d{2})-(\d{2})\s+(\d{2}:\d{2})$/.exec(stamp || "");
    if (!match) {
      return stamp || "";
    }
    const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
    const month = months[Number(match[2]) - 1] || match[2];
    return `${Number(match[3])} ${month} ${match[1]} · ${match[4]}`;
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

  async handleSkipTo(event) {
    const targetStage = event.currentTarget?.dataset?.stage;
    if (!targetStage) {
      return;
    }
    this.showMoreMenu = false;
    await this.runAction(
      () => skipTo({ accountId: this.recordId, targetStage }),
      "Optional stage skipped"
    );
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