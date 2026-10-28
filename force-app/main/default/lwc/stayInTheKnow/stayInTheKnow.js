import { LightningElement, track } from 'lwc';
import getStayInTheKnowArticles from '@salesforce/apex/StayInTheKnowController.getStayInTheKnowArticles';
import { isFieldFeatureEnabled, loadFieldFeatures } from 'c/fieldFeatureFlags';

const ROTATE_MS = 12000;
const SWIPE_THRESHOLD_PX = 48;
const TAP_MAX_PX = 10;
const AXIS_LOCK_PX = 8;

const FILTERS = [
    { value: 'All', label: 'All' },
    { value: 'Egypt', label: 'Egypt' },
    { value: 'Specialty', label: 'My specialties' },
    { value: 'My Products', label: 'My products' },
    { value: 'Pharma', label: 'Pharma' },
    { value: 'Salesforce', label: 'Salesforce' },
    { value: 'Zeta', label: 'Zeta' }
];

export default class StayInTheKnow extends LightningElement {
    @track articles = [];
    @track isLoading = true;
    @track loadError = '';
    @track activeIndex = 0;
    @track dragOffsetPx = 0;
    @track isDragging = false;
    @track activeFilter = 'All';
    @track selectedArticle = null;
    @track progressPaused = false;
    featureEnabled = true;

    _rotateTimer = null;
    _pointerId = null;
    _startX = 0;
    _startY = 0;
    _lockAxis = null;
    _suppressClick = false;
    _tapIndex = null;

    connectedCallback() {
        void this.bootstrap();
    }

    async bootstrap() {
        await loadFieldFeatures();
        this.featureEnabled = isFieldFeatureEnabled('home.beInTheKnow');
        if (this.featureEnabled) {
            this.loadArticles();
        } else {
            this.isLoading = false;
        }
    }

    disconnectedCallback() {
        this.stopRotation();
        this.unlockBodyScroll();
    }

    get filterChips() {
        const available = new Set((this.articles || []).map((a) => a.category));
        return FILTERS.filter((f) => f.value === 'All' || available.has(f.value)).map((f) => ({
            ...f,
            chipClass:
                f.value === this.activeFilter ? 'sik-chip sik-chip-active' : 'sik-chip',
            ariaPressed: f.value === this.activeFilter ? 'true' : 'false'
        }));
    }

    get filteredArticles() {
        if (this.activeFilter === 'All') {
            return this.articles || [];
        }
        return (this.articles || []).filter((a) => a.category === this.activeFilter);
    }

    get articleRows() {
        return this.filteredArticles.map((article, index) => {
            const cat = (article.category || 'News').toLowerCase().replace(/\s+/g, '-');
            return {
                ...article,
                index,
                isActive: index === this.activeIndex,
                cardClass: `sik-card sik-card-${cat}`,
                badgeClass: `sik-badge sik-badge-${cat}`,
                categoryLabel: article.category || 'News',
                publishedLabel: this.formatPublished(article.publishedAt),
                summaryPreview: this.clampText(article.summary, 140),
                hasFavicon: !!article.faviconUrl,
                faviconUrl: article.faviconUrl || '',
                domainLabel: article.domain || article.source || ''
            };
        });
    }

    get hasArticles() {
        return this.articleRows.length > 0;
    }

    get showDots() {
        return this.filteredArticles.length > 1;
    }

    get counterLabel() {
        const total = this.filteredArticles.length;
        if (total < 1) return '';
        return `${this.activeIndex + 1} / ${total}`;
    }

    get visibleDots() {
        const total = this.filteredArticles.length;
        if (total <= 1) return [];
        const maxDots = Math.min(total, 7);
        let start = Math.max(0, this.activeIndex - Math.floor(maxDots / 2));
        let end = start + maxDots;
        if (end > total) {
            end = total;
            start = Math.max(0, end - maxDots);
        }
        const dots = [];
        for (let index = start; index < end; index += 1) {
            dots.push({
                key: `dot-${index}`,
                index,
                isActive: index === this.activeIndex,
                dotClass: index === this.activeIndex ? 'sik-dot sik-dot-active' : 'sik-dot',
                dotLabel: `Article ${index + 1} of ${total}`
            });
        }
        return dots;
    }

    get canSwipe() {
        return this.filteredArticles.length > 1;
    }

    get viewportClass() {
        return this.isDragging ? 'sik-viewport is-dragging' : 'sik-viewport';
    }

    get trackClass() {
        return this.isDragging ? 'sik-track is-dragging' : 'sik-track';
    }

    get trackStyle() {
        return `transform: translate3d(calc(-${this.activeIndex * 100}% + ${this.dragOffsetPx}px), 0, 0);`;
    }

    get progressStyle() {
        if (this.progressPaused || this.filteredArticles.length <= 1) {
            return 'width: 0%; transition: none;';
        }
        return `width: 100%; transition: width ${ROTATE_MS}ms linear;`;
    }

    get showReader() {
        return !!this.selectedArticle;
    }

    get readerTitle() {
        return this.selectedArticle ? this.selectedArticle.title : '';
    }

    get readerSource() {
        return this.selectedArticle ? this.selectedArticle.source : '';
    }

    get readerDate() {
        return this.selectedArticle
            ? this.formatPublished(this.selectedArticle.publishedAt)
            : '';
    }

    get readerSummary() {
        return this.selectedArticle
            ? this.selectedArticle.summary || 'No summary available for this article.'
            : '';
    }

    get readerUrl() {
        return this.selectedArticle ? this.selectedArticle.url : '#';
    }

    get readerCategory() {
        return this.selectedArticle ? this.selectedArticle.category : '';
    }

    get readerCategoryClass() {
        const cat = (this.readerCategory || 'news').toLowerCase().replace(/\s+/g, '-');
        return `sik-badge sik-badge-${cat}`;
    }

    get readerFaviconUrl() {
        return this.selectedArticle && this.selectedArticle.faviconUrl
            ? this.selectedArticle.faviconUrl
            : '';
    }

    get hasReaderFavicon() {
        return !!this.readerFaviconUrl;
    }

    get readerDomain() {
        return (this.selectedArticle && (this.selectedArticle.domain || this.selectedArticle.source)) || '';
    }

    clampText(value, max) {
        const text = (value || '').trim();
        if (text.length <= max) return text;
        return `${text.slice(0, max - 1).trim()}…`;
    }

    formatPublished(iso) {
        if (!iso) return '';
        const d = new Date(iso);
        if (Number.isNaN(d.getTime())) {
            return String(iso).slice(0, 16);
        }
        const today = new Date();
        if (
            d.getFullYear() === today.getFullYear() &&
            d.getMonth() === today.getMonth() &&
            d.getDate() === today.getDate()
        ) {
            return 'Today';
        }
        return d.toLocaleDateString(undefined, {
            month: 'short',
            day: 'numeric',
            year: 'numeric'
        });
    }

    async loadArticles() {
        this.isLoading = true;
        this.loadError = '';
        this.stopRotation();
        try {
            const rows = await getStayInTheKnowArticles({ limitSize: 28 });
            const list = Array.isArray(rows) ? rows.filter((r) => r && r.title && r.url) : [];
            this.articles = list;
            this.activeIndex = 0;
            if (this.filteredArticles.length > 1) {
                this.startRotation();
            }
        } catch (e) {
            // eslint-disable-next-line no-console
            console.warn('[stayInTheKnow] load failed', e);
            this.articles = [];
            this.loadError = 'Unable to load industry news right now.';
        } finally {
            this.isLoading = false;
        }
    }

    startRotation() {
        this.stopRotation();
        if (this.filteredArticles.length <= 1 || this.showReader) {
            return;
        }
        this.progressPaused = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.progressPaused = false;
            this._rotateTimer = setInterval(() => {
                this.goNext();
            }, ROTATE_MS);
        });
    }

    stopRotation() {
        if (this._rotateTimer) {
            clearInterval(this._rotateTimer);
            this._rotateTimer = null;
        }
        this.progressPaused = true;
    }

    goNext() {
        const count = this.filteredArticles.length;
        if (count <= 1) return;
        this.activeIndex = (this.activeIndex + 1) % count;
        this.restartProgress();
    }

    goPrev() {
        const count = this.filteredArticles.length;
        if (count <= 1) return;
        this.activeIndex = (this.activeIndex - 1 + count) % count;
        this.restartProgress();
    }

    restartProgress() {
        if (this.filteredArticles.length <= 1 || this.showReader) return;
        this.progressPaused = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.progressPaused = false;
        });
    }

    handleFilterClick(event) {
        event.stopPropagation();
        const value = event.currentTarget.dataset.filter;
        if (!value || value === this.activeFilter) return;
        this.activeFilter = value;
        this.activeIndex = 0;
        this.dragOffsetPx = 0;
        if (this.filteredArticles.length > 1) {
            this.startRotation();
        } else {
            this.stopRotation();
        }
    }

    handleDotClick(event) {
        event.stopPropagation();
        const index = Number.parseInt(event.currentTarget.dataset.index, 10);
        if (Number.isNaN(index)) return;
        this.activeIndex = index;
        this.dragOffsetPx = 0;
        if (this.filteredArticles.length > 1) {
            this.startRotation();
        }
    }

    handleCardPointerDown(event) {
        // Remember which card was pressed so a tap can open the modal on pointerup.
        const index = Number.parseInt(event.currentTarget.dataset.index, 10);
        this._tapIndex = Number.isNaN(index) ? null : index;
    }

    openArticleAt(index) {
        const article = this.filteredArticles[index];
        if (!article) return;
        this.openReader(article);
    }

    openReader(article) {
        this.selectedArticle = { ...article };
        this.stopRotation();
        this.lockBodyScroll();
    }

    handleCloseReader(event) {
        if (event) {
            event.preventDefault();
            event.stopPropagation();
        }
        this.selectedArticle = null;
        this.unlockBodyScroll();
        if (this.filteredArticles.length > 1) {
            this.startRotation();
        }
    }

    stopModalBubble(event) {
        event.stopPropagation();
    }

    lockBodyScroll() {
        try {
            document.body.style.overflow = 'hidden';
        } catch (_err) {
            /* ignore */
        }
    }

    unlockBodyScroll() {
        try {
            document.body.style.overflow = '';
        } catch (_err) {
            /* ignore */
        }
    }

    handleCarouselMouseEnter() {
        this.stopRotation();
    }

    handleCarouselMouseLeave() {
        if (!this.isDragging && !this.showReader && this.filteredArticles.length > 1) {
            this.startRotation();
        }
    }

    handlePointerDown(event) {
        if (event.pointerType === 'mouse' && event.button !== 0) return;
        this._pointerId = event.pointerId;
        this._startX = event.clientX;
        this._startY = event.clientY;
        this._lockAxis = null;
        this.isDragging = false;
        this.dragOffsetPx = 0;
        this._suppressClick = false;
        this.stopRotation();
    }

    handlePointerMove(event) {
        if (event.pointerId !== this._pointerId) return;
        const dx = event.clientX - this._startX;
        const dy = event.clientY - this._startY;

        if (!this._lockAxis) {
            if (Math.abs(dx) < AXIS_LOCK_PX && Math.abs(dy) < AXIS_LOCK_PX) return;
            this._lockAxis = Math.abs(dx) >= Math.abs(dy) ? 'x' : 'y';
            if (this._lockAxis === 'y') {
                this.resetSwipeState(event.currentTarget);
                return;
            }
            if (this.canSwipe) {
                this.isDragging = true;
                try {
                    event.currentTarget.setPointerCapture(event.pointerId);
                } catch (_err) {
                    /* ignore */
                }
            }
        }

        if (this._lockAxis !== 'x' || !this.canSwipe) return;
        event.preventDefault();
        this.isDragging = true;
        this.dragOffsetPx = dx;
    }

    handlePointerUp(event) {
        if (event.pointerId !== this._pointerId) return;
        const dx = this.dragOffsetPx;
        const totalDx = event.clientX - this._startX;
        const totalDy = event.clientY - this._startY;
        const moved = Math.hypot(totalDx, totalDy);
        const swipedHorizontally =
            this._lockAxis === 'x' && Math.abs(dx || totalDx) >= SWIPE_THRESHOLD_PX;
        const wasTap = !swipedHorizontally && moved <= TAP_MAX_PX;
        const tapIndex = this._tapIndex;

        this.resetSwipeState(event.currentTarget);
        this._tapIndex = null;

        if (swipedHorizontally) {
            this._suppressClick = true;
            if ((dx || totalDx) < 0) this.goNext();
            else this.goPrev();
        } else if (wasTap && tapIndex != null && !this.showReader) {
            // Open modal on tap — do not rely on click (pointer capture steals it).
            this.openArticleAt(tapIndex);
            return;
        }

        if (!this.showReader && this.filteredArticles.length > 1) {
            this.startRotation();
        }
    }

    resetSwipeState(target) {
        if (this._pointerId != null && target && typeof target.releasePointerCapture === 'function') {
            try {
                if (target.hasPointerCapture?.(this._pointerId)) {
                    target.releasePointerCapture(this._pointerId);
                }
            } catch (_err) {
                /* ignore */
            }
        }
        this._pointerId = null;
        this._lockAxis = null;
        this.isDragging = false;
        this.dragOffsetPx = 0;
    }

    handleFaviconError(event) {
        const el = event && event.target;
        if (el && el.style) {
            el.style.display = 'none';
        }
    }
}