import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPatient360 from '@salesforce/apex/CareCoachPatientService.getPatient360';
import sendOnboardingEmailApex from '@salesforce/apex/PatientOnboardingService.sendEmail';
import logOnboardingWhatsApp from '@salesforce/apex/PatientOnboardingService.logWhatsApp';
import getOnboardingHistory from '@salesforce/apex/PatientOnboardingService.history';
import getFilterOptions from '@salesforce/apex/CareCoachPatientService.getFilterOptions';
import logInteraction from '@salesforce/apex/CareCoachPatientService.logInteraction';
import updateInteraction from '@salesforce/apex/CareCoachPatientService.updateInteraction';
import getScripts from '@salesforce/apex/CareCoachCatalogController.getScripts';
import getCallRecording from '@salesforce/apex/CareCoachTelephonyController.getCallRecording';
import createOrder from '@salesforce/apex/CareCoachPatientService.createOrder';
import updatePatientStatus from '@salesforce/apex/CareCoachPatientService.updatePatientStatus';
import analyze from '@salesforce/apex/CareCoachCallAnalysisService.analyze';
import attachCallRecording from '@salesforce/apex/CareCoachTelephonyController.attachCallRecording';
import requestSentiment from '@salesforce/apex/CareCoachTelephonyController.requestSentiment';
import {
    statusStyle,
    riskClass,
    sentimentClass,
    formatDate,
    formatDateTime,
    formatRelative,
    reduceError,
    initialsAvatar,
    CALL_STATUS_COLORS
} from 'c/careCoachUtils';

const SENTIMENT_POLL_MS = 5000;
const SENTIMENT_MAX_POLLS = 12;
const DROP_REASONS = ['Switched therapy', 'Side effects', 'Cost / access', 'Lost to follow-up', 'Physician decision', 'Deceased', 'Other'];
const CALL_OUTCOMES = ['Reached', 'Unreached (No Answer)', 'Unreached (Switched Off)', 'Call back'];
const REASONS = [
    'Welcome call',
    'Follow up',
    'Adherence check',
    'Injection training',
    'Side effect report',
    'Order refill',
    'Disease education',
    'Re-engagement'
];

export default class CareCoachPatient360 extends LightningElement {
    @api context;
    _patientId;
    _mode = 'psp';

    @api
    get patientId() {
        return this._patientId;
    }
    set patientId(value) {
        this._patientId = value;
        if (this.isConnected) this.load();
    }

    @api
    get mode() {
        return this._mode;
    }
    set mode(value) {
        const changed = value !== this._mode;
        this._mode = value;
        if (changed && this.isConnected) this.load();
    }

    data;
    isLoading = true;
    error;
    sendingOnboarding = false;
    activeTab = 'timeline';
    expanded = {};
    analyzingId;
    products = [];

    showCallModal = false;
    showOrderModal = false;
    showStatusModal = false;
    showInteraction = false;
    interactionId;
    interactionForm = {};
    scriptOptions = [];
    audioError;
    audioLoading = false;
    pendingPlay = false;
    pendingAudio = false;
    objectUrl;
    scriptsLoaded = false;
    saving = false;
    callForm = {};
    orderForm = {};
    statusForm = {};
    showDialer = false;
    pendingRecording;
    sentimentTimer;
    sentimentPolls = 0;

    connectedCallback() {
        this.load();
    }

    disconnectedCallback() {
        clearTimeout(this.sentimentTimer);
        this.revokeAudio();
    }

    renderedCallback() {
        if (!this.pendingAudio || !this.showInteraction) return;
        const autoplay = this.pendingPlay;
        this.pendingAudio = false;
        this.pendingPlay = false;
        this.loadAudio(autoplay);
    }

    async load() {
        if (!this._patientId) return;
        this.isLoading = true;
        this.error = undefined;
        try {
            this.data = await getPatient360({ patientId: this._patientId, mode: this._mode });
            await this.applyHistory();
            this.scheduleSentimentRefresh();
            if (this.data.interactions.length && Object.keys(this.expanded).length === 0) {
                const firstWithTranscript = this.data.interactions.find((i) => i.transcript);
                if (firstWithTranscript) this.expanded = { [firstWithTranscript.id]: true };
            }
        } catch (e) {
            this.error = reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async applyHistory() {
        if (!this.data || !this.data.canEdit) return;
        try {
            const history = await getOnboardingHistory({ patientId: this._patientId });
            this.data = { ...this.data, patient: { ...this.data.patient, ...history } };
        } catch (ignore) {
            /* History stays blank until the coach can read the new fields. */
        }
    }

    scheduleSentimentRefresh() {
        clearTimeout(this.sentimentTimer);
        const pending = this.data && this.data.interactions.some((i) => i.sentimentPending);
        if (!pending) {
            this.sentimentPolls = 0;
            return;
        }
        if (this.sentimentPolls >= SENTIMENT_MAX_POLLS) return;
        this.sentimentPolls += 1;
        this.sentimentTimer = setTimeout(async () => {
            try {
                this.data = await getPatient360({ patientId: this._patientId, mode: this._mode });
                await this.applyHistory();
            } catch (e) {
                return;
            }
            this.scheduleSentimentRefresh();
        }, SENTIMENT_POLL_MS);
    }

    // ---------------------------------------------------------------- header

    get core() {
        return this.data ? this.data.patient.core : {};
    }

    get patient() {
        return this.data ? this.data.patient : {};
    }

    get masked() {
        return this.data && this.data.masked;
    }

    get canEdit() {
        return this.data && this.data.canEdit;
    }

    get avatar() {
        return initialsAvatar(this.core.displayName);
    }

    get avatarClass() {
        return this.masked ? 'cc-avatar cc-avatar_lg cc-avatar_masked' : 'cc-avatar cc-avatar_lg';
    }

    get statusStyle() {
        return statusStyle(this.core.status);
    }

    get adherenceClass() {
        return riskClass(this.core.adherence);
    }

    get riskGaugeStyle() {
        const score = this.core.riskScore || 0;
        const color = score >= 60 ? '#ba0517' : score >= 35 ? '#dd7a01' : '#2e844a';
        return `--score:${score};--gauge-color:${color};`;
    }

    get riskScoreLabel() {
        return this.core.riskScore != null ? this.core.riskScore : '—';
    }

    get demographics() {
        return [this.core.gender, this.core.age != null ? `${this.core.age} years` : null, this.core.city].filter(Boolean).join(' · ');
    }

    get contactItems() {
        if (this.masked) return [];
        return [
            { key: 'mobile', icon: 'utility:phone_portrait', label: 'Mobile', value: this.core.mobile },
            { key: 'phone', icon: 'utility:call', label: 'Phone', value: this.core.phone },
            { key: 'email', icon: 'utility:email', label: 'Email', value: this.core.email },
            { key: 'address', icon: 'utility:location', label: 'Address', value: this.patient.address },
            { key: 'nid', icon: 'utility:identity', label: 'National ID', value: this.patient.nationalId },
            { key: 'dob', icon: 'utility:event', label: 'Birthdate', value: formatDate(this.patient.birthdate) }
        ].filter((c) => c.value);
    }

    get hasContacts() {
        return this.contactItems.length > 0;
    }

    get onboardingStatus() {
        const p = this.patient;
        if (!p) return '';
        if (p.onboardingCompletedOn) return `History form completed ${formatDateTime(p.onboardingCompletedOn)}`;
        if (p.onboardingSentOn) return `History form sent ${formatDateTime(p.onboardingSentOn)}`;
        return 'History form not sent yet';
    }

    get emailFormDisabled() {
        return this.sendingOnboarding || !this.core || !this.core.email;
    }

    get whatsappFormDisabled() {
        return this.sendingOnboarding || !this.core || (!this.core.mobile && !this.core.phone);
    }

    async sendOnboardingEmail() {
        await this.dispatchOnboarding('email');
    }

    async sendOnboardingWhatsApp() {
        await this.dispatchOnboarding('whatsapp');
    }

    async dispatchOnboarding(channel) {
        this.sendingOnboarding = true;
        try {
            const result = channel === 'email'
                ? await sendOnboardingEmailApex({ patientId: this._patientId })
                : await logOnboardingWhatsApp({ patientId: this._patientId });
            if (channel === 'whatsapp') {
                const opened = window.open(result.whatsappUrl, '_blank', 'noopener');
                this.toast(
                    opened ? 'WhatsApp opened' : 'Allow pop-ups to open WhatsApp',
                    'The history form link is in the message.',
                    opened ? 'success' : 'warning'
                );
            } else {
                this.toast('Email sent', `The history form was sent to ${result.email}.`, 'success');
            }
            await this.load();
        } catch (e) {
            this.toast('Could not send the form', reduceError(e), 'error');
        } finally {
            this.sendingOnboarding = false;
        }
    }

    get headerStats() {
        const p = this.patient;
        return [
            { key: 'int', label: 'Interactions', value: p.interactionCount || 0 },
            { key: 'reach', label: 'Reached calls', value: p.reachedCallCount || 0 },
            { key: 'orders', label: 'Orders', value: p.orderCount || 0 },
            { key: 'last', label: 'Last call', value: formatRelative(this.core.lastCallDate) }
        ];
    }

    get profileItems() {
        const p = this.patient;
        const c = this.core;
        return [
            { key: 'num', label: 'Patient number', value: c.patientNumber },
            { key: 'product', label: 'Primary product', value: c.productName },
            { key: 'ta', label: 'Therapy area', value: c.therapyArea },
            { key: 'diag', label: 'Diagnosis', value: p.diagnosis },
            { key: 'diagDate', label: 'Diagnosis date', value: formatDate(p.diagnosisDate) },
            { key: 'phys', label: 'Physician in charge', value: p.physician },
            { key: 'hosp', label: 'Hospital', value: p.hospital },
            { key: 'coach', label: 'Care coach', value: c.coachName },
            { key: 'src', label: 'Lead source', value: p.leadSource },
            { key: 'enr', label: 'Enrolled', value: formatDate(c.enrollmentDate) },
            { key: 'journey', label: 'Journey start', value: formatDate(p.journeyStartDate) },
            { key: 'nat', label: 'Nationality', value: p.nationality },
            { key: 'mar', label: 'Marital status', value: p.maritalStatus },
            { key: 'occ', label: 'Occupation', value: p.occupation },
            { key: 'allergies', label: 'Allergies', value: p.allergies },
            { key: 'meds', label: 'Current medications', value: p.medications },
            { key: 'conditions', label: 'Other conditions', value: p.conditions },
            { key: 'emergency', label: 'Emergency contact', value: [p.emergencyName, p.emergencyPhone].filter(Boolean).join(' · ') },
            { key: 'consent', label: 'PSP consent', value: p.consentGiven ? 'Given' : 'Not recorded' },
            { key: 'drop', label: 'Drop reason', value: c.dropReason }
        ].filter((i) => i.value);
    }

    get therapies() {
        return (this.data ? this.data.therapies : []).map((t) => ({
            ...t,
            period: `${formatDate(t.startDate)}${t.stopDate ? ' – ' + formatDate(t.stopDate) : ' – present'}`,
            statusClass: t.status === 'Active' ? 'cc-pill cc-pill_positive' : t.status === 'Stopped' ? 'cc-pill cc-pill_negative' : 'cc-pill',
            details: [t.dosage, t.dosageForm, t.frequency].filter(Boolean).join(' · ')
        }));
    }

    get hasTherapies() {
        return this.therapies.length > 0;
    }

    // ---------------------------------------------------------------- tabs

    get tabs() {
        const d = this.data || { interactions: [], orders: [], history: [] };
        return [
            { key: 'timeline', label: `Interactions (${d.interactions.length})` },
            { key: 'orders', label: `Orders (${d.orders.length})` },
            { key: 'history', label: `Status history (${d.history.length})` }
        ].map((t) => ({ ...t, cls: t.key === this.activeTab ? 'tab is-active' : 'tab' }));
    }

    handleTab(event) {
        this.activeTab = event.currentTarget.dataset.key;
    }

    get isTimeline() {
        return this.activeTab === 'timeline';
    }

    get isOrders() {
        return this.activeTab === 'orders';
    }

    get isHistory() {
        return this.activeTab === 'history';
    }

    get interactions() {
        return (this.data ? this.data.interactions : []).map((i) => {
            const open = !!this.expanded[i.id];
            return {
                ...i,
                when: formatDateTime(i.startTime),
                dotStyle: `background:${CALL_STATUS_COLORS[i.status] || '#8a8886'};`,
                statusLabel: i.status,
                dirIcon: i.direction === 'Inbound' ? 'utility:incoming_call' : 'utility:outgoing_call',
                meta: [i.type, i.direction, i.reason, i.durationMinutes ? `${i.durationMinutes} min` : null, i.coachName]
                    .filter(Boolean)
                    .join(' · '),
                languageLabel: i.language === 'Arabic (Egypt)' ? 'العربية المصرية' : i.language === 'English' ? '' : i.language,
                canPlay: this.canPlay(i),
                hasAi: !!i.aiSummary,
                hasTranscript: !!i.transcript,
                expandable: !!(i.transcript || i.aiSummary || i.notes),
                open,
                chevron: open ? 'utility:chevrondown' : 'utility:chevronright',
                sentimentClass: sentimentClass(i.aiSentiment),
                riskClass: riskClass(i.aiRisk),
                riskLabel: i.aiRisk ? `${i.aiRisk} risk · ${i.aiRiskScore}` : '',
                transcriptLines: (i.transcript || '').split('\n').filter((l) => l.trim()).map((line, idx) => {
                    const speaker = line.includes(':') ? line.split(':')[0].trim() : '';
                    const isCoach = speaker.toLowerCase() === 'coach';
                    return {
                        key: `${i.id}-${idx}`,
                        speaker,
                        text: speaker ? line.substring(line.indexOf(':') + 1).trim() : line,
                        cls: isCoach ? 'line line_coach' : 'line line_patient'
                    };
                }),
                analyzing: this.analyzingId === i.id,
                aiAnalyzedLabel: i.aiAnalyzedOn ? `${i.aiEngine || 'AI'} · ${formatDateTime(i.aiAnalyzedOn)}` : '',
                canAnalyze: this.canEdit && !!i.transcript,
                ...this.sentimentView(i)
            };
        });
    }

    sentimentView(i) {
        let details = null;
        try {
            details = i.aiSentimentDetails ? JSON.parse(i.aiSentimentDetails) : null;
        } catch (e) {
            details = null;
        }
        const error = details && details.error ? details.error : '';
        const hasSentiment = !!details && !error && !!(details.overall || details.patient);
        const speakers = hasSentiment
            ? [
                  { key: 'patient', label: 'Patient', data: details.patient },
                  { key: 'coach', label: 'Coach', data: details.coach }
              ]
                  .filter((s) => s.data)
                  .map((s) => ({
                      key: `${i.id}-${s.key}`,
                      label: s.label,
                      sentiment: s.data.sentiment,
                      cls: sentimentClass(s.data.sentiment),
                      scoreLabel: `${s.data.score > 0 ? '+' : ''}${s.data.score}`,
                      barStyle: `--pos:${Math.round(s.data.positive * 100)}%;--neu:${Math.round(s.data.neutral * 100)}%;--neg:${Math.round(s.data.negative * 100)}%;`
                  }))
            : [];
        const highlights = hasSentiment
            ? (details.sentences || [])
                  .filter((s) => s.speaker === 'Patient' && s.sentiment !== 'Neutral')
                  .sort((a, b) => Math.abs(b.score) - Math.abs(a.score))
                  .slice(0, 5)
                  .map((s, idx) => ({
                      key: `${i.id}-h${idx}`,
                      text: s.text,
                      cls: s.sentiment === 'Negative' ? 'hl hl_neg' : s.sentiment === 'Positive' ? 'hl hl_pos' : 'hl',
                      label: s.sentiment
                  }))
            : [];
        const opinions = hasSentiment
            ? (details.opinions || []).slice(0, 12).map((o, idx) => ({
                  key: `${i.id}-o${idx}`,
                  label: o.assessments ? `${o.target}: ${o.assessments}` : o.target,
                  cls: o.sentiment === 'Negative' ? 'cc-pill cc-pill_negative' : o.sentiment === 'Positive' ? 'cc-pill cc-pill_positive' : 'cc-pill'
              }))
            : [];
        const phrases = (i.aiKeyPhrases || '')
            .split(';')
            .map((p) => p.trim())
            .filter(Boolean)
            .map((p, idx) => ({ key: `${i.id}-k${idx}`, label: p }));
        return {
            hasSentiment,
            sentimentError: error,
            sentimentSpeakers: speakers,
            sentimentHighlights: highlights,
            hasHighlights: highlights.length > 0,
            sentimentOpinions: opinions,
            hasOpinions: opinions.length > 0,
            keyPhrases: phrases,
            hasKeyPhrases: phrases.length > 0,
            sentimentScoreLabel: i.aiSentimentScore != null ? `${i.aiSentimentScore > 0 ? '+' : ''}${i.aiSentimentScore}` : '',
            canRunSentiment: this.canEdit && !this.masked && !!i.transcript && !i.sentimentPending,
            runSentimentLabel: hasSentiment ? 'Re-run sentiment' : 'Run sentiment',
            showSentimentBlock: hasSentiment || i.sentimentPending || !!error
        };
    }

    async handleRunSentiment(event) {
        const callId = event.currentTarget.dataset.id;
        try {
            await requestSentiment({ callId });
            this.toast('Sentiment analysis started', 'Azure AI Language is analysing the transcript.', 'success');
            this.sentimentPolls = 0;
            await this.load();
        } catch (e) {
            this.toast('Could not start sentiment analysis', reduceError(e), 'error');
        }
    }

    // ---------------------------------------------------------------- dialler

    get canCall() {
        return this.canEdit && !this.masked;
    }

    get dialPhone() {
        return this.core.mobile || this.core.phone || '';
    }

    get recordingHint() {
        if (!this.pendingRecording) return '';
        const kb = Math.round((this.pendingRecording.base64.length * 3) / 4 / 1024);
        return `The call recording (${kb} KB) will be attached when you save.`;
    }

    openDialer() {
        this.showDialer = true;
    }

    closeDialer() {
        this.showDialer = false;
    }

    handleCallComplete(event) {
        const d = event.detail || {};
        this.showDialer = false;
        this.pendingRecording = d.recording || null;
        this.callForm = {
            status: d.status || 'Reached',
            direction: 'Outbound',
            reason: 'Follow up',
            startTime: new Date(Date.now() - (d.durationSeconds || 0) * 1000).toISOString(),
            durationMinutes: d.durationMinutes,
            notes: '',
            transcript: d.transcript || '',
            followUpDate: null,
            adverseEvent: false,
            recordingConsent: d.consent === true,
            language: d.language || 'English',
            recordingUrl: d.recordingUrl || null
        };
        this.showCallModal = true;
        if (d.transcriptError) {
            this.toast('Transcription failed', `${d.transcriptError}. You can type notes or paste a transcript instead.`, 'warning');
        }
    }

    get hasInteractions() {
        return this.interactions.length > 0;
    }

    toggleInteraction(event) {
        const id = event.currentTarget.dataset.id;
        this.expanded = { ...this.expanded, [id]: !this.expanded[id] };
    }

    async handleAnalyze(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        this.analyzingId = id;
        try {
            await analyze({ interactionId: id });
            this.toast('AI analysis updated', 'The call transcript was re-analysed.', 'success');
            await this.load();
        } catch (e) {
            this.toast('AI analysis failed', reduceError(e), 'error');
        } finally {
            this.analyzingId = undefined;
        }
    }

    canPlay(row) {
        return this.canCall && row.recordingUrl && !String(row.recordingUrl).includes('recordings.zeta-pharma.com');
    }

    handleRecording(event) {
        event.stopPropagation();
        this.openInteraction(event);
    }

    get selectedInteraction() {
        return this.interactions.find((i) => i.id === this.interactionId) || null;
    }

    get languageOptions() {
        return [
            { label: 'English', value: 'English' },
            { label: 'العربية المصرية', value: 'Arabic (Egypt)' }
        ];
    }

    get knowledgeOptions() {
        const options = this.scriptOptions.length ? this.scriptOptions : [{ label: 'No knowledge article', value: '' }];
        const current = this.selectedInteraction;
        if (current && current.scriptId && !options.some((o) => o.value === current.scriptId)) {
            return options.concat([{ label: current.scriptTitle || 'Linked article', value: current.scriptId }]);
        }
        return options;
    }

    openInteraction(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.id;
        const row = (this.data ? this.data.interactions : []).find((i) => i.id === id);
        if (!row) return;
        this.interactionId = id;
        this.interactionForm = {
            status: row.status,
            reason: row.reason || 'Follow up',
            notes: row.notes || '',
            followUpDate: row.followUpDate,
            durationMinutes: row.durationMinutes,
            adverseEvent: row.adverseEvent === true,
            scriptId: row.scriptId || '',
            language: row.language || 'English'
        };
        this.audioError = undefined;
        this.showInteraction = true;
        this.pendingPlay = event.currentTarget.dataset.play === '1';
        this.pendingAudio = this.canPlay(row);
        this.loadScripts();
    }

    closeInteraction() {
        this.showInteraction = false;
        this.pendingAudio = false;
        this.pendingPlay = false;
        this.revokeAudio();
    }

    revokeAudio() {
        if (this.objectUrl) {
            URL.revokeObjectURL(this.objectUrl);
            this.objectUrl = null;
        }
    }

    async loadScripts() {
        if (!this.canEdit || this.scriptsLoaded) return;
        try {
            const rows = await getScripts({ productId: this.core.productId || null, publishedOnly: true });
            this.scriptOptions = [{ label: 'No knowledge article', value: '' }].concat(
                rows.map((s) => ({ label: [s.title, s.language].filter(Boolean).join(' · '), value: s.id }))
            );
            this.scriptsLoaded = true;
        } catch (e) {
            this.scriptOptions = [{ label: 'No knowledge article', value: '' }];
        }
    }

    async loadAudio(autoplay) {
        const audio = this.template.querySelector('audio.call-audio');
        if (!audio || !this.interactionId) return;
        this.audioLoading = true;
        this.audioError = undefined;
        try {
            const rec = await getCallRecording({ interactionId: this.interactionId });
            this.revokeAudio();
            if (rec.streamUrl) {
                audio.src = rec.streamUrl;
            } else {
                const binary = atob(rec.base64Data || '');
                const bytes = new Uint8Array(binary.length);
                for (let n = 0; n < binary.length; n += 1) bytes[n] = binary.charCodeAt(n);
                this.objectUrl = URL.createObjectURL(new Blob([bytes], { type: rec.mimeType || 'audio/webm' }));
                audio.src = this.objectUrl;
            }
            if (autoplay) await audio.play();
        } catch (e) {
            this.audioError = reduceError(e);
        } finally {
            this.audioLoading = false;
        }
    }

    handleInteractionField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' || event.target.type === 'toggle' ? event.target.checked : event.detail.value;
        this.interactionForm = { ...this.interactionForm, [field]: value };
    }

    async saveInteraction() {
        this.saving = true;
        try {
            await updateInteraction({
                interactionId: this.interactionId,
                payloadJson: JSON.stringify({
                    ...this.interactionForm,
                    durationMinutes: this.interactionForm.durationMinutes ? Number(this.interactionForm.durationMinutes) : null,
                    scriptId: this.interactionForm.scriptId || null
                })
            });
            this.toast('Interaction updated', 'The notes and knowledge article were saved. The recording and transcript stay as captured.', 'success');
            await this.load();
        } catch (e) {
            this.toast('Could not save the interaction', reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    get orders() {
        return (this.data ? this.data.orders : []).map((o) => ({
            ...o,
            ordered: formatDate(o.orderDate),
            delivered: formatDate(o.deliveryDate) || '—',
            statusClass:
                o.status === 'Delivered'
                    ? 'cc-pill cc-pill_positive'
                    : o.status === 'Cancelled'
                      ? 'cc-pill cc-pill_negative'
                      : 'cc-pill cc-pill_accent'
        }));
    }

    get hasOrders() {
        return this.orders.length > 0;
    }

    get showAddressColumn() {
        return !this.masked;
    }

    get history() {
        return (this.data ? this.data.history : []).map((h, idx) => ({
            ...h,
            key: `h-${idx}`,
            when: formatDateTime(h.changedOn)
        }));
    }

    get hasHistory() {
        return this.history.length > 0;
    }

    handleBack() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    // ---------------------------------------------------------------- modals

    get outcomeOptions() {
        return CALL_OUTCOMES.map((v) => ({ label: v, value: v }));
    }

    get reasonOptions() {
        return REASONS.map((v) => ({ label: v, value: v }));
    }

    get directionOptions() {
        return [
            { label: 'Outbound', value: 'Outbound' },
            { label: 'Inbound', value: 'Inbound' }
        ];
    }

    get channelOptions() {
        return ['Home Delivery', 'Pharmacy Pick-up', 'Hospital'].map((v) => ({ label: v, value: v }));
    }

    get statusOptions() {
        return ['Ongoing', 'Pending', 'Dropped (Switched)', 'Dropped (Stopped)', 'Unknown (Failed calls)'].map((v) => ({
            label: v,
            value: v
        }));
    }

    get dropReasonOptions() {
        return DROP_REASONS.map((v) => ({ label: v, value: v }));
    }

    get statusNeedsReason() {
        return (this.statusForm.status || '').startsWith('Dropped');
    }

    openCall() {
        this.callForm = {
            status: 'Reached',
            direction: 'Outbound',
            reason: 'Follow up',
            startTime: new Date().toISOString(),
            durationMinutes: 10,
            notes: '',
            transcript: '',
            followUpDate: null,
            adverseEvent: false
        };
        this.showCallModal = true;
    }

    async openOrder() {
        if (!this.products.length) {
            try {
                const opts = await getFilterOptions();
                this.products = opts.products;
            } catch (e) {
                this.toast('Could not load products', reduceError(e), 'error');
            }
        }
        this.orderForm = { productId: this.core.productId, quantity: 1, channel: 'Home Delivery', notes: '' };
        this.showOrderModal = true;
    }

    openStatus() {
        this.statusForm = { status: this.core.status, dropReason: this.core.dropReason };
        this.showStatusModal = true;
    }

    closeModals() {
        this.pendingRecording = null;
        this.closeInteraction();
        this.showCallModal = false;
        this.showOrderModal = false;
        this.showStatusModal = false;
    }

    handleCallField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' || event.target.type === 'toggle' ? event.target.checked : event.detail.value;
        this.callForm = { ...this.callForm, [field]: value };
    }

    handleOrderField(event) {
        this.orderForm = { ...this.orderForm, [event.target.dataset.field]: event.detail.value };
    }

    handleStatusField(event) {
        this.statusForm = { ...this.statusForm, [event.target.dataset.field]: event.detail.value };
    }

    async saveCall() {
        this.saving = true;
        try {
            const payload = { ...this.callForm, durationMinutes: this.callForm.durationMinutes ? Number(this.callForm.durationMinutes) : null };
            const row = await logInteraction({ patientId: this._patientId, payloadJson: JSON.stringify(payload) });
            const recording = this.pendingRecording;
            if (recording && payload.recordingConsent) {
                try {
                    await attachCallRecording({ callId: row.id, fileName: recording.fileName, base64Data: recording.base64 });
                } catch (e) {
                    this.toast('Recording not saved', reduceError(e), 'warning');
                }
            }
            this.closeModals();
            this.toast(
                'Call logged',
                row.aiRisk ? `AI analysis: ${row.aiRisk} adherence risk, ${String(row.aiSentiment).toLowerCase()} sentiment.` : 'Interaction saved.',
                'success'
            );
            this.expanded = { [row.id]: true };
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.toast('Could not log call', reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    async saveOrder() {
        this.saving = true;
        try {
            await createOrder({
                patientId: this._patientId,
                productId: this.orderForm.productId,
                quantity: Number(this.orderForm.quantity) || 1,
                channel: this.orderForm.channel,
                notes: this.orderForm.notes
            });
            this.closeModals();
            this.toast('Order created', 'The order was sent for approval.', 'success');
            this.activeTab = 'orders';
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.toast('Could not create order', reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    async saveStatus() {
        this.saving = true;
        try {
            await updatePatientStatus({
                patientId: this._patientId,
                status: this.statusForm.status,
                dropReason: this.statusNeedsReason ? this.statusForm.dropReason : null
            });
            this.closeModals();
            this.toast('Status updated', `Patient is now ${this.statusForm.status}.`, 'success');
            await this.load();
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.toast('Could not update status', reduceError(e), 'error');
        } finally {
            this.saving = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}