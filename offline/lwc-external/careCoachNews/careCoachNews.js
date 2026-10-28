import { LightningElement, track } from 'lwc';
import getProducts from '@salesforce/apex/CareCoachCatalogController.getProducts';

const ROTATE_MS = 12000;
const SWIPE_THRESHOLD_PX = 48;
const TAP_MAX_PX = 10;
const AXIS_LOCK_PX = 8;
const CACHE_KEY = 'ccn.articles.v1';
const CACHE_TTL_MS = 15 * 60 * 1000;
const PROD_FALLBACK = 'https://www.salesforceoffline.com/.netlify/functions/care-coach-news';
const DEFAULT_PRODUCTS = ['Erbitux', 'Rebif', 'Mavenclad', 'Saizen'];

const FILTERS = [
    { value: 'All', label: 'All' },
    { value: 'Prices', label: 'Prices' },
    { value: 'Competitors', label: 'Competitors' },
    { value: 'Adverse events', label: 'Adverse events' },
    { value: 'Recommendations', label: 'Recommendations' }
];

function newsUrl(products) {
    let base = PROD_FALLBACK;
    try {
        const origin = window.location && window.location.origin ? window.location.origin : '';
        if (
            origin.includes('localhost') ||
            origin.includes('127.0.0.1') ||
            origin.includes('salesforceoffline.com') ||
            origin.includes('netlify.app')
        ) {
            base = `${origin}/.netlify/functions/care-coach-news`;
        }
    } catch (_err) {
        /* Lightning without a usable origin keeps the public endpoint */
    }
    const qs = new URLSearchParams();
    if (products.length) qs.set('products', products.join(','));
    const suffix = qs.toString();
    return suffix ? `${base}?${suffix}` : base;
}

function readCache(productsKey) {
    try {
        const raw = sessionStorage.getItem(CACHE_KEY);
        if (!raw) return null;
        const parsed = JSON.parse(raw);
        if (!parsed || parsed.key !== productsKey || Date.now() - parsed.savedAt > CACHE_TTL_MS) return null;
        return Array.isArray(parsed.articles) ? parsed.articles : null;
    } catch (_err) {
        return null;
    }
}

function writeCache(productsKey, articles) {
    try {
        sessionStorage.setItem(
            CACHE_KEY,
            JSON.stringify({ key: productsKey, savedAt: Date.now(), articles })
        );
    } catch (_err) {
        /* storage full or blocked */
    }
}

export default class CareCoachNews extends LightningElement {
    @track articles = [];
    @track isLoading = true;
    @track loadError = '';
    @track activeIndex = 0;
    @track dragOffsetPx = 0;
    @track isDragging = false;
    @track activeFilter = 'All';
    @track selectedArticle = null;
    @track progressPaused = false;

    _rotateTimer = null;
    _pointerId = null;
    _startX = 0;
    _startY = 0;
    _lockAxis = null;
    _tapIndex = null;
    _products = DEFAULT_PRODUCTS.slice();

    connectedCallback() {
        this.loadArticles(false);
    }

    disconnectedCallback() {
        this.stopRotation();
        this.unlockBodyScroll();
    }

    get showBody() {
        return !this.isLoading;
    }

    get showEmpty() {
        return !this.hasArticles;
    }

    get emptyMessage() {
        return this.loadError || 'No programme news available right now.';
    }

    get filterChips() {
        const available = new Set((this.articles || []).map((a) => a.category));
        return FILTERS.filter((f) => f.value === 'All' || available.has(f.value)).map((f) => ({
            ...f,
            chipClass: f.value === this.activeFilter ? 'ccn-chip ccn-chip-active' : 'ccn-chip',
            ariaPressed: f.value === this.activeFilter ? 'true' : 'false'
        }));
    }

    get filteredArticles() {
        if (this.activeFilter === 'All') return this.articles || [];
        return (this.articles || []).filter((a) => a.category === this.activeFilter);
    }

    get articleRows() {
        return this.filteredArticles.map((article, index) => {
            const cat = (article.category || 'News').toLowerCase().replace(/\s+/g, '-');
            const detailed = article.category === 'Prices' || article.category === 'Adverse events';
            return {
                ...article,
                index,
                cardClass: `ccn-card ccn-card-${cat}`,
                badgeClass: `ccn-badge ccn-badge-${cat}`,
                categoryLabel: article.category || 'News',
                publishedLabel: this.formatPublished(article.publishedAt),
                summaryPreview: this.clampText(article.summary, detailed ? 280 : 140),
                summaryClass: detailed ? 'ccn-summary ccn-summary-detail' : 'ccn-summary',
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
                dotClass: index === this.activeIndex ? 'ccn-dot ccn-dot-active' : 'ccn-dot',
                dotLabel: `Article ${index + 1} of ${total}`
            });
        }
        return dots;
    }

    get canSwipe() {
        return this.filteredArticles.length > 1;
    }

    get viewportClass() {
        return this.isDragging ? 'ccn-viewport is-dragging' : 'ccn-viewport';
    }

    get trackClass() {
        return this.isDragging ? 'ccn-track is-dragging' : 'ccn-track';
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

    get readerDate() {
        return this.selectedArticle ? this.formatPublished(this.selectedArticle.publishedAt) : '';
    }

    get readerSummary() {
        return this.selectedArticle
            ? this.selectedArticle.summary || 'No summary available.'
            : '';
    }

    get readerUrl() {
        return this.selectedArticle ? this.selectedArticle.url : '#';
    }

    get readerLinkLabel() {
        return (this.selectedArticle && this.selectedArticle.linkLabel) || 'Open full article';
    }

    get readerCategory() {
        return this.selectedArticle ? this.selectedArticle.category : '';
    }

    get readerCategoryClass() {
        const cat = (this.readerCategory || 'news').toLowerCase().replace(/\s+/g, '-');
        return `ccn-badge ccn-badge-${cat}`;
    }

    get readerFaviconUrl() {
        return this.selectedArticle && this.selectedArticle.faviconUrl ? this.selectedArticle.faviconUrl : '';
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
        if (Number.isNaN(d.getTime())) return String(iso).slice(0, 16);
        const today = new Date();
        if (
            d.getFullYear() === today.getFullYear() &&
            d.getMonth() === today.getMonth() &&
            d.getDate() === today.getDate()
        ) {
            return 'Today';
        }
        return d.toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
    }

    handleRefresh() {
        this.loadArticles(true);
    }

    async loadArticles(force) {
        this.isLoading = true;
        this.loadError = '';
        this.stopRotation();
        try {
            this._products = await this.resolveProducts();
            const productsKey = this._products.map((n) => n.toLowerCase()).join('|');
            if (!force) {
                const cached = readCache(productsKey);
                if (cached && cached.length) {
                    this.articles = cached;
                    this.activeIndex = 0;
                    this.isLoading = false;
                    if (this.filteredArticles.length > 1) this.startRotation();
                    return;
                }
            }
            const res = await fetch(newsUrl(this._products), { method: 'GET', headers: { Accept: 'application/json' } });
            if (!res.ok) throw new Error(`care-coach-news ${res.status}`);
            const payload = await res.json();
            const list = Array.isArray(payload && payload.articles)
                ? payload.articles.filter((row) => row && row.title && row.url)
                : [];
            this.articles = list;
            this.activeIndex = 0;
            if (this.activeFilter !== 'All' && !list.some((row) => row.category === this.activeFilter)) {
                this.activeFilter = 'All';
            }
            if (list.length) writeCache(productsKey, list);
            if (this.filteredArticles.length > 1) this.startRotation();
        } catch (e) {
            this.articles = [];
            this.loadError = 'Unable to load programme news right now.';
        } finally {
            this.isLoading = false;
        }
    }

    async resolveProducts() {
        try {
            const groups = await Promise.race([
                getProducts({ scope: 'all' }),
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                new Promise((resolve) => setTimeout(() => resolve(null), 4000))
            ]);
            const names = [];
            (groups || []).forEach((group) => {
                (group.products || []).forEach((product) => {
                    const name = product && product.name ? String(product.name).trim() : '';
                    if (name && !names.includes(name)) names.push(name);
                });
            });
            return names.length ? names.slice(0, 6) : DEFAULT_PRODUCTS.slice();
        } catch (_err) {
            return DEFAULT_PRODUCTS.slice();
        }
    }

    startRotation() {
        this.stopRotation();
        if (this.filteredArticles.length <= 1 || this.showReader) return;
        this.progressPaused = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            this.progressPaused = false;
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this._rotateTimer = setInterval(() => this.goNext(), ROTATE_MS);
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
        if (this.filteredArticles.length > 1) this.startRotation();
        else this.stopRotation();
    }

    handleDotClick(event) {
        event.stopPropagation();
        const index = Number.parseInt(event.currentTarget.dataset.index, 10);
        if (Number.isNaN(index)) return;
        this.activeIndex = index;
        this.dragOffsetPx = 0;
        if (this.filteredArticles.length > 1) this.startRotation();
    }

    handleCardPointerDown(event) {
        const index = Number.parseInt(event.currentTarget.dataset.index, 10);
        this._tapIndex = Number.isNaN(index) ? null : index;
    }

    openArticleAt(index) {
        const article = this.filteredArticles[index];
        if (article) this.openReader(article);
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
        if (this.filteredArticles.length > 1) this.startRotation();
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
        if (!this.isDragging && !this.showReader && this.filteredArticles.length > 1) this.startRotation();
    }

    handlePointerDown(event) {
        if (event.pointerType === 'mouse' && event.button !== 0) return;
        this._pointerId = event.pointerId;
        this._startX = event.clientX;
        this._startY = event.clientY;
        this._lockAxis = null;
        this.isDragging = false;
        this.dragOffsetPx = 0;
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
        const swipedHorizontally = this._lockAxis === 'x' && Math.abs(dx || totalDx) >= SWIPE_THRESHOLD_PX;
        const wasTap = !swipedHorizontally && moved <= TAP_MAX_PX;
        const tapIndex = this._tapIndex;
        this.resetSwipeState(event.currentTarget);
        this._tapIndex = null;
        if (swipedHorizontally) {
            if ((dx || totalDx) < 0) this.goNext();
            else this.goPrev();
        } else if (wasTap && tapIndex != null && !this.showReader) {
            this.openArticleAt(tapIndex);
            return;
        }
        if (!this.showReader && this.filteredArticles.length > 1) this.startRotation();
    }

    resetSwipeState(target) {
        if (this._pointerId != null && target && typeof target.releasePointerCapture === 'function') {
            try {
                if (target.hasPointerCapture && target.hasPointerCapture(this._pointerId)) {
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
        if (el && el.style) el.style.display = 'none';
    }
}
