import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import openCourse from '@salesforce/apex/MyLearningController.openCourse';
import startLesson from '@salesforce/apex/MyLearningController.startLesson';
import markLessonComplete from '@salesforce/apex/MyLearningController.markLessonComplete';
import recordItemEngagement from '@salesforce/apex/MyLearningController.recordItemEngagement';

// BRD §5.6: the next video stays locked until this share of the current one is watched.
const VIDEO_UNLOCK_PERCENT = 85;

export default class LearningCoursePlayer extends LightningElement {
    @api courseInstanceId;
    _initialPlayer;
    @track player;
    @track selectedItem;
    busy = false;
    videoUnlocked = false;
    currentWatchPercent = 0;
    _engagementInFlight = false;
    _pendingEngagement;

    @api
    get initialPlayer() {
        return this._initialPlayer;
    }
    set initialPlayer(value) {
        this._initialPlayer = value;
        if (value) {
            this.applyPlayer(value);
        }
    }

    get curriculum() {
        const items = this.player?.curriculum || [];
        return items.map((item, index) => {
            const selected =
                item.instanceId != null &&
                this.selectedItem?.instanceId === item.instanceId;
            const unlocked = this.isIndexUnlocked(index);
            const locked = item.instanceId == null || !unlocked;
            const durationLabel =
                item.duration != null && item.duration !== ''
                    ? `${item.duration} min`
                    : null;
            const statusLabel = locked
                ? 'Locked'
                : item.completed
                  ? 'Completed'
                  : item.status || 'Not Started';
            return {
                ...item,
                rowKey: item.instanceId || item.materialId,
                isDisabled: locked,
                isLocked: locked,
                typeLabel: item.materialType || 'Lesson',
                metaLabel: [durationLabel, statusLabel].filter(Boolean).join(' · '),
                itemClass: `curriculum-item${selected ? ' is-selected' : ''}${
                    item.completed ? ' is-complete' : ''
                }${locked ? ' is-locked' : ''}`,
                iconName: locked ? 'utility:lock' : this.iconForType(item.materialType)
            };
        });
    }

    get hasCurriculum() {
        return this.curriculum.length > 0;
    }

    get curriculumCountLabel() {
        const count = this.curriculum.length;
        return `${count} item${count === 1 ? '' : 's'}`;
    }

    get contentStageItems() {
        if (!this.isContent || !this.selectedItem) {
            return [];
        }
        return [
            {
                key: this.selectedItem.instanceId || this.selectedItem.materialId,
                materialType: this.selectedItem.materialType,
                materialUrl: this.selectedItem.materialUrl,
                description: this.selectedItem.description,
                title: this.selectedItem.title,
                initialWatchPercent: this.selectedItem.watchPercent || 0
            }
        ];
    }

    get quizStageItems() {
        if (!this.isQuiz || !this.selectedItem?.instanceId) {
            return [];
        }
        return [
            {
                key: this.selectedItem.instanceId,
                instanceId: this.selectedItem.instanceId
            }
        ];
    }

    get progressLabel() {
        return `${Math.round(this.player?.progress || 0)}%`;
    }

    get progressStyle() {
        return `width:${Math.round(this.player?.progress || 0)}%`;
    }

    get isQuiz() {
        return this.selectedItem?.materialType === 'Quiz';
    }

    get isContent() {
        return (
            this.selectedItem &&
            ['Video', 'PDF', 'Lesson'].includes(this.selectedItem.materialType)
        );
    }

    get isVideo() {
        return this.selectedItem?.materialType === 'Video';
    }

    get canMarkComplete() {
        if (!this.isContent || this.selectedItem?.completed) {
            return false;
        }
        // Videos auto-complete at 85% (VIDEO_UNLOCK_PERCENT); no free mark-complete shortcut.
        return !this.isVideo;
    }

    get showCertificateCta() {
        return this.player?.canShowCertificate === true;
    }

    get previousDisabled() {
        return !this.hasPrevious || this.busy;
    }

    get nextDisabled() {
        if (!this.hasNext || this.busy) {
            return true;
        }
        return !this.isCurrentItemDone;
    }

    get navHint() {
        if (!this.hasNext) {
            return 'This is the last item';
        }
        if (!this.isCurrentItemDone) {
            return this.isVideo
                ? `Watch ${VIDEO_UNLOCK_PERCENT}% to unlock Next`
                : 'Complete this item to unlock Next';
        }
        return '';
    }

    get isCurrentItemDone() {
        return this.isItemDone(this.selectedItem);
    }

    get hasPrevious() {
        return this.currentIndex > 0;
    }

    get hasNext() {
        return (
            this.currentIndex >= 0 &&
            this.currentIndex < (this.player?.curriculum?.length || 0) - 1
        );
    }

    get currentIndex() {
        if (!this.selectedItem || !this.player?.curriculum) {
            return -1;
        }
        return this.player.curriculum.findIndex(
            (item) => item.instanceId === this.selectedItem.instanceId
        );
    }

    isItemDone(item) {
        if (!item) {
            return false;
        }
        if (item.completed === true) {
            return true;
        }
        if (item.materialType !== 'Video') {
            return false;
        }
        if (Number(item.watchPercent) >= VIDEO_UNLOCK_PERCENT) {
            return true;
        }
        if (this.selectedItem?.instanceId === item.instanceId) {
            return this.videoUnlocked || this.currentWatchPercent >= VIDEO_UNLOCK_PERCENT;
        }
        return false;
    }

    isIndexUnlocked(index) {
        if (index <= 0) {
            return true;
        }
        const items = this.player?.curriculum || [];
        for (let i = 0; i < index; i++) {
            if (!this.isItemDone(items[i])) {
                return false;
            }
        }
        return true;
    }

    applyPlayer(player) {
        this.player = player;
        const selectedId = player.selectedInstanceId;
        const nextItem =
            (player.curriculum || []).find((item) => item.instanceId === selectedId) ||
            (player.curriculum || [])[0] ||
            null;
        this.bindSelectedItem(nextItem, true);
        if (this.selectedItem?.instanceId) {
            startLesson({ instanceId: this.selectedItem.instanceId }).catch(() => {});
        }
    }

    bindSelectedItem(item, resetGate) {
        this.selectedItem = item;
        if (resetGate) {
            this.currentWatchPercent = Number(item?.watchPercent) || 0;
            this.videoUnlocked = false;
        }
        this.syncVideoGate();
    }

    syncVideoGate() {
        const watch = Number(this.selectedItem?.watchPercent) || 0;
        this.currentWatchPercent = Math.max(Number(this.currentWatchPercent) || 0, watch);
        this.videoUnlocked =
            !this.isVideo ||
            this.selectedItem?.completed === true ||
            this.currentWatchPercent >= VIDEO_UNLOCK_PERCENT;
    }

    iconForType(type) {
        switch (type) {
            case 'Video':
                return 'utility:video';
            case 'PDF':
                return 'utility:file';
            case 'Quiz':
                return 'utility:question';
            default:
                return 'utility:knowledge_base';
        }
    }

    async handleSelectLesson(event) {
        const instanceId = event.currentTarget.dataset.id;
        const items = this.player?.curriculum || [];
        const index = items.findIndex((row) => row.instanceId === instanceId);
        const item = index >= 0 ? items[index] : null;
        if (!item || !this.isIndexUnlocked(index)) {
            return;
        }
        this.bindSelectedItem(item, true);
        try {
            await startLesson({ instanceId });
        } catch (error) {
            this.toast('Unable to start lesson', error?.body?.message || error?.message, 'error');
        }
    }

    async handleWatchProgress(event) {
        const detail = event.detail || {};
        const watchPercent = Number(detail.watchPercent) || 0;
        const secondsSpent = Number(detail.secondsSpent) || 0;
        if (watchPercent > this.currentWatchPercent) {
            this.currentWatchPercent = watchPercent;
        }
        if (
            this.isVideo &&
            (watchPercent >= VIDEO_UNLOCK_PERCENT ||
                detail.unlocked === true ||
                detail.forceComplete === true ||
                this.selectedItem?.completed)
        ) {
            this.videoUnlocked = true;
        }
        if (!this.selectedItem?.instanceId) {
            return;
        }
        if (secondsSpent <= 0 && watchPercent < VIDEO_UNLOCK_PERCENT && !detail.forceComplete) {
            // Still push watch % when crossing meaningful thresholds without seconds.
            if (watchPercent < this.currentWatchPercent) {
                return;
            }
        }
        await this.persistEngagement(watchPercent, secondsSpent);
    }

    async persistEngagement(watchPercent, secondsSpent) {
        const payload = {
            instanceId: this.selectedItem.instanceId,
            watchPercent,
            secondsSpent
        };
        if (this._engagementInFlight) {
            this._pendingEngagement = payload;
            return;
        }
        this._engagementInFlight = true;
        try {
            const result = await recordItemEngagement(payload);
            if (result?.watchPercent != null) {
                this.currentWatchPercent = Number(result.watchPercent);
                if (this.selectedItem) {
                    this.selectedItem = {
                        ...this.selectedItem,
                        watchPercent: result.watchPercent,
                        completed: result.completed === true,
                        timeTakenMinutes: result.timeTakenMinutes
                    };
                }
            }
            if (result?.unlockedNext || result?.completed) {
                this.videoUnlocked = true;
            }
            if (result?.player) {
                const keepId = this.selectedItem?.instanceId;
                this.player = result.player;
                this.bindSelectedItem(
                    (result.player.curriculum || []).find((row) => row.instanceId === keepId) ||
                        this.selectedItem,
                    false
                );
                this.dispatchEvent(
                    new CustomEvent('refresh', {
                        detail: {
                            player: result.player,
                            showCertificate: result.player.canShowCertificate === true
                        }
                    })
                );
                if (result.player.canShowCertificate) {
                    this.dispatchEvent(
                        new CustomEvent('showcertificate', {
                            detail: { courseInstanceId: this.courseInstanceId }
                        })
                    );
                }
            }
        } catch (error) {
            // Soft-fail engagement heartbeats so playback is not interrupted.
            // eslint-disable-next-line no-console
            console.warn('Engagement sync failed', error);
        } finally {
            this._engagementInFlight = false;
            if (this._pendingEngagement) {
                const next = this._pendingEngagement;
                this._pendingEngagement = null;
                this.persistEngagement(next.watchPercent, next.secondsSpent);
            }
        }
    }

    async handleMarkComplete() {
        if (!this.selectedItem?.instanceId || this.isVideo) {
            return;
        }
        this.busy = true;
        try {
            const player = await markLessonComplete({ instanceId: this.selectedItem.instanceId });
            this.applyPlayer(player);
            this.dispatchEvent(
                new CustomEvent('refresh', {
                    detail: {
                        player,
                        showCertificate: player.canShowCertificate === true
                    }
                })
            );
            if (player.canShowCertificate) {
                this.dispatchEvent(
                    new CustomEvent('showcertificate', {
                        detail: { courseInstanceId: this.courseInstanceId }
                    })
                );
            } else {
                this.goNext();
            }
        } catch (error) {
            this.toast('Unable to complete lesson', error?.body?.message || error?.message, 'error');
        } finally {
            this.busy = false;
        }
    }

    async handleQuizComplete(event) {
        const detail = event.detail || {};
        try {
            const player = await openCourse({
                courseInstanceId: this.courseInstanceId,
                selectedMaterialId: this.selectedItem?.materialId
            });
            this.applyPlayer(player);
            this.dispatchEvent(
                new CustomEvent('refresh', {
                    detail: {
                        player,
                        showCertificate: detail.canShowCertificate === true
                    }
                })
            );
            if (detail.canShowCertificate) {
                this.dispatchEvent(
                    new CustomEvent('showcertificate', {
                        detail: { courseInstanceId: this.courseInstanceId }
                    })
                );
            }
        } catch (error) {
            this.toast('Unable to refresh course', error?.body?.message || error?.message, 'error');
        }
    }

    handleBack() {
        this.dispatchEvent(
            new CustomEvent('back', {
                bubbles: true,
                composed: true
            })
        );
    }

    handleShowCertificate() {
        this.dispatchEvent(
            new CustomEvent('showcertificate', {
                detail: { courseInstanceId: this.courseInstanceId }
            })
        );
    }

    goPrevious() {
        if (!this.hasPrevious) {
            return;
        }
        const item = this.player.curriculum[this.currentIndex - 1];
        this.bindSelectedItem(item, true);
        startLesson({ instanceId: item.instanceId }).catch(() => {});
    }

    goNext() {
        if (this.nextDisabled) {
            return;
        }
        const nextIndex = this.currentIndex + 1;
        if (!this.isIndexUnlocked(nextIndex) && !this.isCurrentItemDone) {
            return;
        }
        const item = this.player.curriculum[nextIndex];
        if (!item?.instanceId) {
            return;
        }
        this.bindSelectedItem(item, true);
        startLesson({ instanceId: item.instanceId }).catch((error) => {
            this.toast('Unable to open next item', error?.body?.message || error?.message, 'error');
        });
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}