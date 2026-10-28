import { LightningElement, track } from 'lwc';
import HELP_SHOTS from '@salesforce/resourceUrl/AdminHelpShots';
import { HELP_ITEMS } from './helpContent';
import { HELP_GUIDES } from './helpGuides';

const LABELS = {
    en: {
        openModule: 'Open module',
        viewGuide: 'View guide',
        back: 'All help topics',
        overview: 'What this module does',
        affects: 'Who it affects',
        before: 'Before you start',
        steps: 'Step by step',
        tips: 'Tips',
        cautions: 'Be careful',
        related: 'Related modules',
        shots: 'Screenshots',
        stepCount: 'steps',
        enlarge: 'Click to enlarge',
        close: 'Close'
    },
    ar: {
        openModule: 'افتح الوحدة',
        viewGuide: 'اعرض الدليل',
        back: 'كل مواضيع المساعدة',
        overview: 'ماذا تفعل هذه الوحدة',
        affects: 'على من يؤثر',
        before: 'قبل أن تبدأ',
        steps: 'خطوة بخطوة',
        tips: 'نصائح',
        cautions: 'انتبه',
        related: 'وحدات ذات صلة',
        shots: 'لقطات الشاشة',
        stepCount: 'خطوات',
        enlarge: 'اضغط للتكبير',
        close: 'إغلاق'
    }
};

function normalize(text) {
    return (text || '')
        .toLowerCase()
        .replace(/[^\p{L}\p{N}\s]/gu, ' ')
        .replace(/\s+/g, ' ')
        .trim();
}

function shotUrl(name) {
    return name ? `${HELP_SHOTS}/${name}` : null;
}

/** Merge the short bilingual entry with its detailed guide (if any). */
function buildTopic(item) {
    const guide = HELP_GUIDES[item.id] || {};
    const steps = (guide.steps || item.steps.map((text) => ({ text }))).map((step) =>
        (typeof step === 'string' ? { text: step } : step)
    );
    return {
        ...item,
        overview: guide.overview || item.phrase,
        overviewAr: guide.overviewAr || item.phraseAr,
        affects: guide.affects,
        before: guide.before || [],
        guideSteps: steps,
        tips: guide.tips || [],
        cautions: guide.cautions || [],
        related: guide.related || [],
        shotNames: steps.map((step) => step.shot).filter(Boolean)
    };
}

const TOPICS = HELP_ITEMS.map(buildTopic);
const TOPIC_BY_ID = new Map(TOPICS.map((topic) => [topic.id, topic]));

function scoreItem(item, query) {
    if (!query) {
        return 1;
    }
    const q = normalize(query);
    const tokens = q.split(' ').filter(Boolean);
    const hay = normalize(
        [
            item.tile,
            item.tileAr,
            item.phrase,
            item.phraseAr,
            item.overview,
            ...(item.intents || []),
            ...item.guideSteps.map((step) => `${step.text} ${step.detail || ''}`),
            ...(item.stepsAr || []),
            ...item.tips,
            ...item.cautions
        ].join(' ')
    );
    let score = 0;
    if (normalize(item.tile).includes(q) || normalize(item.tileAr).includes(q)) {
        score += 15;
    }
    if (hay.includes(q)) {
        score += 10;
    }
    tokens.forEach((token) => {
        if (hay.includes(token)) {
            score += 2;
        }
        (item.intents || []).forEach((intent) => {
            if (normalize(intent).includes(token)) {
                score += 3;
            }
        });
    });
    return score;
}

export default class AdminConsoleHelp extends LightningElement {
    @track query = '';
    @track lang = 'en';
    @track selectedId = null;
    @track zoomShot = null;

    get labels() {
        return LABELS[this.lang] || LABELS.en;
    }

    get isAr() {
        return this.lang === 'ar';
    }

    get dir() {
        return this.isAr ? 'rtl' : 'ltr';
    }

    get langOptions() {
        return [
            { label: 'English', value: 'en' },
            { label: 'العربية', value: 'ar' }
        ];
    }

    get results() {
        const ar = this.isAr;
        return TOPICS.map((item) => {
            const thumb = item.shotNames[0];
            return {
                id: item.id,
                tile: item.tile,
                score: scoreItem(item, this.query),
                title: ar ? item.tileAr : item.tile,
                whenText: ar ? item.phraseAr : item.phrase,
                thumbUrl: shotUrl(thumb),
                hasThumb: Boolean(thumb),
                metaText: `${(ar ? item.stepsAr : item.guideSteps).length} ${this.labels.stepCount} · ${item.shotNames.length} 📷`
            };
        })
            .filter((item) => !this.query || item.score > 0)
            .sort((a, b) => b.score - a.score);
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get isDetail() {
        return Boolean(this.selectedId && TOPIC_BY_ID.has(this.selectedId));
    }

    get topic() {
        const item = TOPIC_BY_ID.get(this.selectedId);
        if (!item) {
            return null;
        }
        const ar = this.isAr;
        const toList = (arr) => arr.map((text, i) => ({ key: `${i}`, text }));
        const steps = ar
            ? item.stepsAr.map((text, i) => ({ key: `s${i}`, num: i + 1, text, hasShot: false }))
            : item.guideSteps.map((step, i) => ({
                  key: `s${i}`,
                  num: i + 1,
                  text: step.text,
                  detail: step.detail,
                  hasShot: Boolean(step.shot),
                  shotUrl: shotUrl(step.shot),
                  shotAlt: `${item.tile} – step ${i + 1}`
              }));
        const related = item.related
            .map((id) => TOPIC_BY_ID.get(id))
            .filter(Boolean)
            .map((rel) => ({ id: rel.id, label: ar ? rel.tileAr : rel.tile }));
        return {
            id: item.id,
            tile: item.tile,
            title: ar ? item.tileAr : item.tile,
            subtitle: ar ? item.tile : item.tileAr,
            whenText: ar ? item.phraseAr : item.phrase,
            overview: ar ? item.overviewAr : item.overview,
            affects: ar ? null : item.affects,
            before: ar ? [] : toList(item.before),
            steps,
            tips: ar ? [] : toList(item.tips),
            cautions: ar ? [] : toList(item.cautions),
            related,
            gallery: ar
                ? item.shotNames.map((name, i) => ({ key: name, url: shotUrl(name), alt: `${item.tileAr} ${i + 1}` }))
                : []
        };
    }

    get hasAffects() {
        return Boolean(this.topic && this.topic.affects);
    }
    get hasBefore() {
        return Boolean(this.topic && this.topic.before.length);
    }
    get hasTips() {
        return Boolean(this.topic && this.topic.tips.length);
    }
    get hasCautions() {
        return Boolean(this.topic && this.topic.cautions.length);
    }
    get hasRelated() {
        return Boolean(this.topic && this.topic.related.length);
    }
    get hasGallery() {
        return Boolean(this.topic && this.topic.gallery.length);
    }
    get hasGlance() {
        return this.hasAffects || this.hasBefore;
    }

    handleQuery(event) {
        this.query = event.target.value || '';
        this.selectedId = null;
    }

    handleLang(event) {
        this.lang = event.detail.value;
    }

    handleView(event) {
        this.selectedId = event.currentTarget.dataset.id;
        this.scrollTop();
    }

    handleBack() {
        this.selectedId = null;
        this.scrollTop();
    }

    handleZoom(event) {
        const { url, alt } = event.currentTarget.dataset;
        this.zoomShot = { url, alt };
        this._focusZoom = true;
    }

    renderedCallback() {
        // Focus the overlay so Escape reaches handleZoomKey before the Admin Console panel sees it.
        if (this._focusZoom) {
            const backdrop = this.template.querySelector('.zoom-backdrop');
            if (backdrop) {
                backdrop.focus();
                this._focusZoom = false;
            }
        }
    }

    handleZoomClose() {
        this.zoomShot = null;
    }

    /** Escape closes only the enlarged screenshot; keep it from also closing the Admin Console panel. */
    handleZoomKey(event) {
        if (this.zoomShot && (event.key === 'Escape' || event.key === 'Esc')) {
            event.stopPropagation();
            event.preventDefault();
            this.zoomShot = null;
        }
    }

    scrollTop() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const shell = this.template.querySelector('.help-shell');
            if (shell && shell.scrollIntoView) {
                shell.scrollIntoView({ block: 'start' });
            }
        });
    }

    /** Ask the Admin Console to open the module this walkthrough describes (item ids match console card ids). */
    handleOpen(event) {
        const { id, title } = event.currentTarget.dataset;
        this.dispatchEvent(new CustomEvent('openadminmodule', { detail: { cardId: id, title } }));
    }
}
