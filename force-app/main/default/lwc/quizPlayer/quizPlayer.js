import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getQuizForTake from '@salesforce/apex/MyLearningController.getQuizForTake';
import submitQuiz from '@salesforce/apex/MyLearningController.submitQuiz';

export default class QuizPlayer extends LightningElement {
    _instanceId;
    @track quiz;
    @track answers = {};
    @track result;
    loading = true;
    submitting = false;
    examStarted = false;
    startedAt;
    endsAt;
    remainingSeconds = 0;
    _timerId;

    @api
    get instanceId() {
        return this._instanceId;
    }
    set instanceId(value) {
        this._instanceId = value;
        if (value) {
            this.resetState();
            this.loadQuiz();
        }
    }

    disconnectedCallback() {
        this.clearTimer();
    }

    resetState() {
        this.clearTimer();
        this.quiz = null;
        this.answers = {};
        this.result = null;
        this.examStarted = false;
        this.startedAt = null;
        this.endsAt = null;
        this.remainingSeconds = 0;
        this.submitting = false;
    }

    get questionsView() {
        return (this.quiz?.questions || []).map((q, index) => {
            const type = q.type || 'single-choice';
            const selected = this.answers[q.id];
            const isMultipleChoice = type === 'multiple-choice';
            const isScale = type === 'scale';
            const isSingleChoice = !isMultipleChoice && !isScale;

            let options;
            if (isScale) {
                const min = Number(q.scaleMin ?? 1);
                const max = Number(q.scaleMax ?? 5);
                options = [];
                for (let value = min; value <= max; value++) {
                    let label = String(value);
                    if (value === min && q.scaleMinLabel) {
                        label = `${value} - ${q.scaleMinLabel}`;
                    } else if (value === max && q.scaleMaxLabel) {
                        label = `${value} - ${q.scaleMaxLabel}`;
                    }
                    options.push({
                        label,
                        value: String(value),
                        key: `${q.id}_scale_${value}`
                    });
                }
            } else {
                options = (q.options || []).map((label, optIndex) => ({
                    label,
                    value: String(optIndex),
                    key: `${q.id}_${optIndex}`
                }));
            }

            let selectedValue = null;
            let selectedValues = [];
            if (isMultipleChoice) {
                selectedValues = Array.isArray(selected)
                    ? selected.map(String)
                    : selected == null
                      ? []
                      : [String(selected)];
            } else if (selected != null) {
                selectedValue = String(selected);
            }

            return {
                ...q,
                number: index + 1,
                options,
                selectedValue,
                selectedValues,
                isSingleChoice,
                isMultipleChoice,
                isScale
            };
        });
    }

    get questionCount() {
        return this.quiz?.questions?.length || 0;
    }

    get canSubmit() {
        return (
            this.examStarted &&
            this.quiz?.canAttempt === true &&
            !this.submitting &&
            !this.result &&
            (this.quiz?.questions || []).every((q) => {
                const answer = this.answers[q.id];
                if (q.type === 'multiple-choice') {
                    return Array.isArray(answer) && answer.length > 0;
                }
                return answer != null;
            })
        );
    }

    get submitDisabled() {
        return !this.canSubmit || this.submitting;
    }

    get attemptsUsed() {
        return Number(this.quiz?.attemptNumber || 0);
    }

    get maxAttempts() {
        return this.quiz?.maxAttempts == null ? null : Number(this.quiz.maxAttempts);
    }

    get attemptsRemaining() {
        if (this.maxAttempts == null) {
            return null;
        }
        return Math.max(0, this.maxAttempts - this.attemptsUsed);
    }

    get attemptSummary() {
        if (this.maxAttempts == null) {
            return `${this.attemptsUsed} attempt(s) used - Unlimited retries`;
        }
        return `${this.attemptsRemaining} of ${this.maxAttempts} attempts remaining`;
    }

    get nextAttemptLabel() {
        if (this.maxAttempts == null) {
            return `Attempt ${this.attemptsUsed + 1}`;
        }
        return `Attempt ${this.attemptsUsed + 1} of ${this.maxAttempts}`;
    }

    get timeLimitLabel() {
        const mins = this.quiz?.timeLimitMinutes;
        return mins == null ? 'No time limit' : `${mins} minutes`;
    }

    get hasTimeLimit() {
        return Number(this.quiz?.timeLimitMinutes || 0) > 0;
    }

    get passingLabel() {
        return `${this.quiz?.passingScore ?? 70}%`;
    }

    get showLobby() {
        return this.quiz && !this.result && this.quiz.canAttempt && !this.examStarted;
    }

    get showForm() {
        return this.quiz && !this.result && this.quiz.canAttempt && this.examStarted;
    }

    get blockedMessage() {
        if (!this.quiz) {
            return null;
        }
        if (this.quiz.status === 'Completed') {
            return `Quiz completed. Score: ${this.quiz.lastScore ?? 'n/a'}%`;
        }
        if (!this.quiz.canAttempt) {
            return 'No attempts remaining for this quiz.';
        }
        return null;
    }

    get timerDisplay() {
        const total = Math.max(0, this.remainingSeconds || 0);
        const mins = Math.floor(total / 60);
        const secs = total % 60;
        return `${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`;
    }

    get timerClass() {
        if (this.remainingSeconds <= 60) {
            return 'timer-chip timer-chip--critical';
        }
        if (this.remainingSeconds <= 5 * 60) {
            return 'timer-chip timer-chip--warn';
        }
        return 'timer-chip';
    }

    get answeredCount() {
        return Object.keys(this.answers).filter((id) => {
            const answer = this.answers[id];
            if (Array.isArray(answer)) {
                return answer.length > 0;
            }
            return answer != null;
        }).length;
    }

    get progressLabel() {
        return `${this.answeredCount} / ${this.questionCount} answered`;
    }

    async loadQuiz() {
        this.loading = true;
        try {
            this.quiz = await getQuizForTake({ instanceId: this.instanceId });
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unable to load quiz',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false;
        }
    }

    handleStartExam() {
        if (!this.quiz?.canAttempt || this.examStarted) {
            return;
        }
        this.answers = {};
        this.result = null;
        this.examStarted = true;
        this.startedAt = Date.now();
        const limitMinutes = Number(this.quiz.timeLimitMinutes || 0);
        if (limitMinutes > 0) {
            this.endsAt = this.startedAt + limitMinutes * 60 * 1000;
            this.remainingSeconds = Math.round(limitMinutes * 60);
            this.startTimer();
        } else {
            this.endsAt = null;
            this.remainingSeconds = 0;
        }
    }

    startTimer() {
        this.clearTimer();
        this._timerId = window.setInterval(() => {
            const left = Math.max(0, Math.round((this.endsAt - Date.now()) / 1000));
            this.remainingSeconds = left;
            if (left <= 0) {
                this.clearTimer();
                this.handleSubmit({ auto: true });
            }
        }, 1000);
    }

    clearTimer() {
        if (this._timerId) {
            window.clearInterval(this._timerId);
            this._timerId = null;
        }
    }

    handleAnswer(event) {
        const questionId = event.currentTarget.dataset.id;
        const type = event.currentTarget.dataset.type || 'single-choice';
        if (type === 'multiple-choice') {
            const raw = event.detail.value;
            const values = Array.isArray(raw) ? raw : raw == null || raw === '' ? [] : [raw];
            this.answers = {
                ...this.answers,
                [questionId]: values.map((v) => Number(v)).filter((n) => !Number.isNaN(n))
            };
            return;
        }
        const value = Number(event.detail.value);
        this.answers = { ...this.answers, [questionId]: value };
    }

    async handleSubmit(eventOrOptions) {
        const isAuto = eventOrOptions?.auto === true;
        if (this.submitting || this.result || !this.examStarted) {
            return;
        }
        if (!isAuto && !this.canSubmit) {
            return;
        }
        this.submitting = true;
        this.clearTimer();
        const minutes = Math.max(
            0.1,
            Number(((Date.now() - (this.startedAt || Date.now())) / 60000).toFixed(1))
        );
        try {
            this.result = await submitQuiz({
                instanceId: this.instanceId,
                answersJson: JSON.stringify(this.answers),
                timeTakenMinutes: minutes
            });
            this.examStarted = false;
            if (isAuto) {
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Time is up',
                        message: 'Your exam was submitted automatically.',
                        variant: 'warning'
                    })
                );
            }
            this.dispatchEvent(
                new CustomEvent('quizcomplete', {
                    detail: {
                        passed: this.result.passed,
                        score: this.result.score,
                        courseCompleted: this.result.courseCompleted,
                        canShowCertificate: this.result.canShowCertificate
                    }
                })
            );
        } catch (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Submit failed',
                    message: error?.body?.message || error?.message,
                    variant: 'error'
                })
            );
            // If timer expired submit failed, keep exam open so user can retry submit.
            if (this.endsAt && Date.now() < this.endsAt) {
                this.startTimer();
            }
        } finally {
            this.submitting = false;
        }
    }

    async handleRetry() {
        this.result = null;
        this.answers = {};
        this.examStarted = false;
        await this.loadQuiz();
    }
}