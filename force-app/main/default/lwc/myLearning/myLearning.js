import { LightningElement, track, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMyCourses from '@salesforce/apex/MyLearningController.getMyCourses';
import getTeamLearning from '@salesforce/apex/MyLearningController.getTeamLearning';
import openCourse from '@salesforce/apex/MyLearningController.openCourse';

function normalizeStatus(status) {
    if (
        status === 'In Progress' ||
        status === 'Completed' ||
        status === 'Missed'
    ) {
        return status;
    }
    return 'Not Started';
}

function formatEndDate(value) {
    if (!value) {
        return null;
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return null;
    }
    return date.toLocaleDateString(undefined, {
        year: 'numeric',
        month: 'short',
        day: 'numeric'
    });
}

function enrichCourse(course) {
    const status = normalizeStatus(course.status);
    const canAccess = course.canAccess !== false && status !== 'Missed';
    let actionLabel = 'Continue';
    if (status === 'Not Started') {
        actionLabel = 'Start';
    } else if (status === 'Completed') {
        actionLabel = 'Review';
    } else if (status === 'Missed') {
        actionLabel = null;
    }
    let endDateLabel = null;
    if (course.effectiveEndDate) {
        const formatted = formatEndDate(course.effectiveEndDate);
        endDateLabel =
            status === 'Missed'
                ? `Ended ${formatted}`
                : `Available until ${formatted}`;
    }
    return {
        ...course,
        normalizedStatus: status,
        canAccess,
        progressLabel: `${Math.round(course.progress || 0)}%`,
        progressStyle: `width:${Math.round(course.progress || 0)}%`,
        actionLabel,
        endDateLabel,
        cardClass:
            status === 'Missed' ? 'course-card course-card-missed' : 'course-card'
    };
}

function enrichTeamRow(row) {
    const status = normalizeStatus(row.status);
    return {
        ...row,
        normalizedStatus: status,
        progressLabel: `${Math.round(row.progress || 0)}%`,
        progressStyle: `width:${Math.round(row.progress || 0)}%`,
        statusClass: status === 'Missed' ? 'status status-missed' : 'status'
    };
}

export default class MyLearning extends LightningElement {
    @track courses = [];
    @track teamRows = [];
    @track player;
    @track showCertificate = false;
    courseInstanceId;
    loading = true;
    errorMessage;
    teamError;
    refreshKey = 0;
    wiredCoursesResult;
    wiredTeamResult;
    isManager = false;
    scope = 'mine';

    @wire(getMyCourses)
    wiredCourses(result) {
        this.wiredCoursesResult = result;
        const { data, error } = result;
        this.loading = false;
        if (data) {
            this.courses = data.map(enrichCourse);
            this.errorMessage = null;
        } else if (error) {
            this.errorMessage = error?.body?.message || error?.message || 'Unable to load learning.';
        }
    }

    @wire(getTeamLearning)
    wiredTeam(result) {
        this.wiredTeamResult = result;
        const { data, error } = result;
        if (data) {
            this.isManager = data.isManager === true;
            this.teamRows = (data.rows || []).map(enrichTeamRow);
            this.teamError = null;
            if (!this.isManager) {
                this.scope = 'mine';
            }
        } else if (error) {
            this.teamError = error?.body?.message || error?.message || 'Unable to load team learning.';
        }
    }

    get hasCourses() {
        return this.courses.length > 0;
    }

    get inProgressCourses() {
        return this.courses.filter((c) => c.normalizedStatus === 'In Progress');
    }

    get notStartedCourses() {
        return this.courses.filter((c) => c.normalizedStatus === 'Not Started');
    }

    get completedCourses() {
        return this.courses.filter((c) => c.normalizedStatus === 'Completed');
    }

    get missedCourses() {
        return this.courses.filter((c) => c.normalizedStatus === 'Missed');
    }

    get hasInProgressCourses() {
        return this.inProgressCourses.length > 0;
    }

    get hasNotStartedCourses() {
        return this.notStartedCourses.length > 0;
    }

    get hasCompletedCourses() {
        return this.completedCourses.length > 0;
    }

    get hasMissedCourses() {
        return this.missedCourses.length > 0;
    }

    get inProgressCountLabel() {
        return `In Progress (${this.inProgressCourses.length})`;
    }

    get notStartedCountLabel() {
        return `Not Started (${this.notStartedCourses.length})`;
    }

    get completedCountLabel() {
        return `Completed (${this.completedCourses.length})`;
    }

    get missedCountLabel() {
        return `Missed (${this.missedCourses.length})`;
    }

    get showCatalog() {
        return !this.player && !this.showCertificate;
    }

    get showScopeTabs() {
        return this.showCatalog && this.isManager;
    }

    get showMineCatalog() {
        return this.showCatalog && this.scope !== 'team';
    }

    get showTeamCatalog() {
        return this.showCatalog && this.isManager && this.scope === 'team';
    }

    get mineTabClass() {
        return this.scope === 'mine' ? 'scope-tab is-active' : 'scope-tab';
    }

    get teamTabClass() {
        return this.scope === 'team' ? 'scope-tab is-active' : 'scope-tab';
    }

    get mineSelected() {
        return this.scope === 'mine' ? 'true' : 'false';
    }

    get teamSelected() {
        return this.scope === 'team' ? 'true' : 'false';
    }

    get catalogIntro() {
        return this.showTeamCatalog
            ? 'Courses assigned on your subordinate territories, and where each person stands.'
            : 'Continue your assigned courses and track your progress.';
    }

    get teamGroups() {
        const groups = [];
        const byLearner = new Map();
        this.teamRows.forEach((row) => {
            const key = row.learnerId || row.learnerName;
            if (!byLearner.has(key)) {
                const group = {
                    key,
                    learnerName: row.learnerName || 'Team member',
                    territoryName: row.territoryName,
                    courses: []
                };
                byLearner.set(key, group);
                groups.push(group);
            }
            byLearner.get(key).courses.push(row);
        });
        return groups;
    }

    get hasTeamRows() {
        return this.teamRows.length > 0;
    }

    get showTeamEmpty() {
        return this.showTeamCatalog && !this.hasTeamRows && !this.teamError;
    }

    get teamSummary() {
        const people = this.teamGroups.length;
        const assignments = this.teamRows.length;
        const completed = this.teamRows.filter((row) => row.normalizedStatus === 'Completed').length;
        return `${assignments} assigned · ${people} ${people === 1 ? 'person' : 'people'} · ${completed} completed`;
    }

    get showPlayer() {
        return !!this.player && !this.showCertificate;
    }

    get wrapperClass() {
        return this.showPlayer ? 'my-learning my-learning--player' : 'my-learning';
    }

    async handleContinue(event) {
        const instanceId = event.currentTarget.dataset.id;
        this.loading = true;
        try {
            this.player = await openCourse({
                courseInstanceId: instanceId,
                selectedMaterialId: null
            });
            this.courseInstanceId = instanceId;
            this.showCertificate = false;
        } catch (error) {
            this.toast('Unable to open course', error?.body?.message || error?.message, 'error');
        } finally {
            this.loading = false;
        }
    }

    handleShowCertificateFromCard(event) {
        this.courseInstanceId = event.currentTarget.dataset.id;
        this.player = null;
        this.showCertificate = true;
    }

    handleShowCertificate(event) {
        this.courseInstanceId = event.detail?.courseInstanceId || this.courseInstanceId;
        this.showCertificate = true;
    }

    handleScopeChange(event) {
        const next = event.currentTarget?.dataset?.scope;
        if (next === 'mine' || next === 'team') {
            this.scope = next;
        }
    }

    handleBackToCatalog() {
        this.player = null;
        this.showCertificate = false;
        this.courseInstanceId = null;
        this.refreshCatalog();
    }

    handlePlayerRefresh(event) {
        this.player = event.detail?.player || this.player;
    }

    refreshCatalog() {
        if (this.wiredCoursesResult) {
            refreshApex(this.wiredCoursesResult);
        }
        if (this.wiredTeamResult) {
            refreshApex(this.wiredTeamResult);
        }
        this.refreshKey += 1;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}