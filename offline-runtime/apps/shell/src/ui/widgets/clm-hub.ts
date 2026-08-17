import { html, nothing, type TemplateResult } from 'lit';
import {
  type ClmAuth,
  deleteCachedClmAsset,
  getPresentationPdfObjectUrl,
  getSlideMediaObjectUrl,
  prefetchAllPresentations,
  type ClmPresentationAsset
} from '../clm/clm-content-cache';

type Presentation = ClmPresentationAsset & {
  title?: string;
  productName?: string;
  status?: string;
  slideCount?: number;
};

type SlideView = {
  title: string;
  messages: string[];
  imagePath?: string | null;
  pageNumber?: number | null;
};

type Sentiment = 'Negative' | 'Neutral' | 'Positive';

type MessageRow = {
  key: string;
  name: string;
  sentiment: Sentiment | null;
};

type PlayerPhase = 'play' | 'feedback' | 'ratings' | 'done';

type PlayerState = {
  phase: PlayerPhase;
  slideIndex: number;
  sessionKey: string;
  startedAt: string;
  messages: MessageRow[];
  overlayOpen: boolean;
  ratingNotes: string;
  ratingScore: string;
  saved: boolean;
  slideSrc: string | null;
  slideLoading: boolean;
  slideError: string | null;
  slideLoadKey: string | null;
  slideIsPdfEmbed: boolean;
  slideRetried: boolean;
};

const DEFAULT_MESSAGES = ['EFFICACY', 'INDICATION', 'SAFETY', 'SIDE EFFECTS', 'USAGE'];
const SENTIMENTS: { label: string; value: Sentiment; color: string }[] = [
  { label: 'Negative', value: 'Negative', color: '#ba0517' },
  { label: 'Neutral', value: 'Neutral', color: '#706e6b' },
  { label: 'Positive', value: 'Positive', color: '#2e844a' }
];

const playerUi = new Map<string, PlayerState>();

function idOf(p: Presentation): string {
  return String(p.id ?? p.presentationId ?? '');
}

function nameOf(p: Presentation): string {
  return String(p.name ?? p.title ?? 'Presentation');
}

function slidesFor(p: Presentation | null): SlideView[] {
  if (!p) return [{ title: 'Slide 1', messages: DEFAULT_MESSAGES }];
  const seqs = (p.sequences || [])
    .slice()
    .sort(
      (a, b) =>
        Number(a.sequenceOrder ?? a.order ?? 0) - Number(b.sequenceOrder ?? b.order ?? 0)
    );
  if (seqs.length) {
    return seqs.map((s, i) => ({
      title: s.sequenceName || s.name || `Slide ${i + 1}`,
      messages: String(s.messageNames || '')
        .split(/[;,]/)
        .map((x) => x.trim())
        .filter(Boolean)
        .map((x) => x.toUpperCase()),
      imagePath: s.slideImageUrl || s.thumbnailUrl || null,
      pageNumber: s.pageNumber ?? i + 1
    }));
  }
  const count = Math.max(1, Number(p.slideCount) || 8);
  return Array.from({ length: Math.min(count, 24) }, (_, i) => ({
    title: `Slide ${i + 1}`,
    messages: i === 0 || i === count - 1 ? DEFAULT_MESSAGES.slice(0, 3) : [],
    imagePath: null,
    pageNumber: i + 1
  }));
}

async function resolveSlideSrc(
  p: Presentation,
  slide: SlideView,
  auth: ClmAuth | null | undefined,
  online: boolean,
  skipCache = false
): Promise<{ src: string | null; isPdfEmbed: boolean; error: string | null }> {
  if (!auth) {
    return { src: null, isPdfEmbed: false, error: 'Sign in while online to download slides.' };
  }
  try {
    if (slide.imagePath) {
      const media = await getSlideMediaObjectUrl(slide.imagePath, auth, online, { skipCache });
      if (media) {
        if (media.kind === 'pdf') {
          const page = slide.pageNumber ?? 1;
          return { src: `${media.objectUrl}#page=${page}`, isPdfEmbed: true, error: null };
        }
        return { src: media.objectUrl, isPdfEmbed: false, error: null };
      }
    }
    if (p.formatType === 'PDF' && p.contentDocumentId) {
      const pdfUrl = await getPresentationPdfObjectUrl(p.contentDocumentId, auth, online);
      if (pdfUrl) {
        const page = slide.pageNumber ?? 1;
        return { src: `${pdfUrl}#page=${page}`, isPdfEmbed: true, error: null };
      }
    }
    if (!online) {
      return {
        src: null,
        isPdfEmbed: false,
        error: 'Slide not cached. Sync on Home while online, then open CLM again.'
      };
    }
    return { src: null, isPdfEmbed: false, error: 'No slide image available for this deck.' };
  } catch (e) {
    return {
      src: null,
      isPdfEmbed: false,
      error: e instanceof Error ? e.message : String(e)
    };
  }
}

function scheduleSlideLoad(
  p: Presentation | null,
  state: PlayerState,
  slideIndex: number,
  auth: ClmAuth | null | undefined,
  online: boolean,
  bump: () => void,
  skipCache = false
): void {
  if (!p || state.phase !== 'play') return;
  const slides = slidesFor(p);
  const slide = slides[Math.min(slideIndex, slides.length - 1)];
  const loadKey = `${idOf(p)}:${slideIndex}${skipCache ? ':fresh' : ''}`;
  if (!skipCache && state.slideLoadKey === loadKey && (state.slideLoading || state.slideSrc)) return;
  state.slideLoadKey = loadKey;
  state.slideLoading = true;
  state.slideSrc = null;
  state.slideError = null;
  state.slideIsPdfEmbed = false;
  bump();
  void resolveSlideSrc(p, slide, auth, online, skipCache).then((result) => {
    if (state.slideLoadKey !== loadKey) return;
    state.slideSrc = result.src;
    state.slideIsPdfEmbed = result.isPdfEmbed;
    state.slideError = result.error;
    state.slideLoading = false;
    bump();
  });
}

function handleSlideImageError(
  p: Presentation | null,
  slide: SlideView | undefined,
  state: PlayerState,
  auth: ClmAuth | null | undefined,
  online: boolean,
  bump: () => void
): void {
  if (!slide?.imagePath || !auth || state.slideRetried) {
    state.slideSrc = null;
    state.slideError = 'Slide image failed to load.';
    bump();
    return;
  }
  state.slideRetried = true;
  void deleteCachedClmAsset(slide.imagePath).then(() => {
    state.slideLoadKey = null;
    scheduleSlideLoad(p, state, state.slideIndex, auth, online, bump, true);
  });
}

function stateFor(presentationId: string, visitId?: string | null): PlayerState {
  const key = `${presentationId}::${visitId || 'adhoc'}`;
  let s = playerUi.get(key);
  if (!s) {
    s = {
      phase: 'play',
      slideIndex: 0,
      sessionKey: `local_clm_${crypto.randomUUID()}`,
      startedAt: new Date().toISOString(),
      messages: DEFAULT_MESSAGES.map((name, i) => ({
        key: `${name}_${i}`,
        name,
        sentiment: null
      })),
      overlayOpen: false,
      ratingNotes: '',
      ratingScore: '',
      saved: false,
      slideSrc: null,
      slideLoading: false,
      slideError: null,
      slideLoadKey: null,
      slideIsPdfEmbed: false,
      slideRetried: false
    };
    playerUi.set(key, s);
  }
  return s;
}

function collectMessagesFromSlides(slides: SlideView[]): MessageRow[] {
  const names = new Set<string>();
  for (const s of slides) for (const m of s.messages) names.add(m);
  const list = names.size ? Array.from(names) : DEFAULT_MESSAGES;
  return list.map((name, i) => ({ key: `${name}_${i}`, name, sentiment: null }));
}

/** Vite catalog port for c/clmPresentationsHub. */
export function renderClmPresentationsHub(opts: {
  label: string;
  presentations: unknown[] | null;
  cached?: boolean;
  onOpenPlayer?: (presentationId: string) => void;
}): TemplateResult {
  const rows = (opts.presentations ?? []) as Presentation[];
  return html`
    <div class="osr-lwc-mirror clm-hub slds-card">
      <header class="slds-p-around_medium" style="border-bottom:1px solid #e5e5e5">
        <h2 class="slds-text-heading_medium" style="margin:0">${opts.label || 'CLM Presentations'}</h2>
        <p class="slds-text-body_small slds-text-color_weak" style="margin:0.25rem 0 0">
          ${rows.length} cached on device${opts.cached ? ' · offline snapshot' : ''}
        </p>
      </header>
      ${!rows.length
        ? html`<div class="slds-p-around_medium slds-text-color_weak">
            No CLM presentations cached. Sync while online, or open Home CLM prefetch.
          </div>`
        : html`<ul style="list-style:none;margin:0;padding:0">
            ${rows.map((p) => {
              const id = idOf(p);
              return html`
                <li
                  class="slds-p-around_small"
                  style="border-bottom:1px solid #f3f3f3;cursor:pointer"
                  @click=${() => id && opts.onOpenPlayer?.(id)}
                >
                  <strong>${nameOf(p)}</strong>
                  <div class="slds-text-body_small slds-text-color_weak">
                    ${[p.productName, p.status].filter(Boolean).join(' · ') || 'Ready offline'}
                  </div>
                  <button
                    type="button"
                    class="slds-button slds-button_brand slds-m-top_x-small"
                    @click=${(e: Event) => {
                      e.stopPropagation();
                      if (id) opts.onOpenPlayer?.(id);
                    }}
                  >
                    Play
                  </button>
                </li>
              `;
            })}
          </ul>`}
    </div>
  `;
}

/** Vite catalog port for c/clmMessageFeedback. */
export function renderClmMessageFeedback(opts: {
  sessionId?: string | null;
  messages?: MessageRow[];
  productName?: string;
  onChange?: (messages: MessageRow[]) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const rows = opts.messages?.length
    ? opts.messages
    : DEFAULT_MESSAGES.map((name, i) => ({ key: `${name}_${i}`, name, sentiment: null as Sentiment | null }));
  const bump = () => opts.requestUpdate?.();
  return html`
    <div class="osr-lwc-mirror clm-message-feedback slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small" style="margin:0 0 0.35rem">Message sentiment</h3>
      <p class="slds-text-body_small slds-text-color_weak" style="margin:0 0 0.75rem">
        ${opts.productName || 'Product'} · capture Negative / Neutral / Positive per message
      </p>
      ${rows.map(
        (m) => html`
          <div
            style="display:flex;flex-wrap:wrap;align-items:center;gap:0.5rem;margin-bottom:0.65rem;padding-bottom:0.65rem;border-bottom:1px solid #f3f3f3"
          >
            <strong style="min-width:7rem">${m.name}</strong>
            <div style="display:flex;gap:0.35rem;flex-wrap:wrap">
              ${SENTIMENTS.map(
                (s) => html`<button
                  type="button"
                  class="slds-button ${m.sentiment === s.value
                    ? 'slds-button_brand'
                    : 'slds-button_neutral'}"
                  style=${m.sentiment === s.value ? `background:${s.color};border-color:${s.color}` : ''}
                  @click=${() => {
                    m.sentiment = s.value;
                    opts.onChange?.(rows);
                    bump();
                  }}
                >
                  ${s.label}
                </button>`
              )}
            </div>
          </div>
        `
      )}
    </div>
  `;
}

/** Vite catalog port for c/clmRatingsCapture. */
export function renderClmRatingsCapture(opts: {
  visitId?: string | null;
  sessionId?: string | null;
  score?: string;
  notes?: string;
  onScore?: (v: string) => void;
  onNotes?: (v: string) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  return html`
    <div class="osr-lwc-mirror clm-ratings-capture slds-card slds-p-around_medium">
      <h3 class="slds-text-heading_small" style="margin:0 0 0.35rem">Visit ratings</h3>
      <p class="slds-text-body_small slds-text-color_weak" style="margin:0 0 0.75rem">
        Capture post-call ratings for this session
        ${opts.visitId ? html` · visit ${opts.visitId.slice(0, 8)}…` : nothing}
      </p>
      <label class="slds-form-element" style="display:block;margin-bottom:0.75rem">
        <span class="slds-form-element__label">Overall interest</span>
        <div class="slds-form-element__control">
          <select
            class="slds-select"
            .value=${opts.score || ''}
            @change=${(e: Event) => opts.onScore?.((e.target as HTMLSelectElement).value)}
          >
            <option value="">Select…</option>
            <option value="1">1 — Low</option>
            <option value="2">2</option>
            <option value="3">3 — Medium</option>
            <option value="4">4</option>
            <option value="5">5 — High</option>
          </select>
        </div>
      </label>
      <label class="slds-form-element" style="display:block">
        <span class="slds-form-element__label">Notes</span>
        <div class="slds-form-element__control">
          <textarea
            class="slds-textarea"
            rows="3"
            .value=${opts.notes || ''}
            @input=${(e: Event) => opts.onNotes?.((e.target as HTMLTextAreaElement).value)}
          ></textarea>
        </div>
      </label>
    </div>
  `;
}

/** Vite catalog port for c/clmPlayer — play → sentiment → ratings. */
export function renderClmPlayer(opts: {
  presentationId: string | null;
  presentations: unknown[] | null;
  visitId?: string | null;
  sfAuth?: ClmAuth | null;
  online?: boolean;
  onBack?: () => void;
  onComplete?: (payload: {
    presentationId: string;
    sessionKey: string;
    visitId?: string | null;
    messages: MessageRow[];
    ratingScore: string;
    ratingNotes: string;
  }) => void;
  requestUpdate?: () => void;
}): TemplateResult {
  const rows = (opts.presentations ?? []) as Presentation[];
  const presentationId = opts.presentationId || '';
  const p =
    rows.find((x) => idOf(x) === presentationId) ??
    (presentationId.startsWith('demo_')
      ? ({
          id: presentationId,
          name: 'Territory detail aid',
          productName: 'Demo product',
          slideCount: 6
        } as Presentation)
      : null);
  const bump = () => opts.requestUpdate?.();
  const state = stateFor(presentationId || 'unknown', opts.visitId);
  const slides = slidesFor(p);
  const slide = slides[Math.min(state.slideIndex, slides.length - 1)];
  scheduleSlideLoad(p, state, state.slideIndex, opts.sfAuth, opts.online ?? false, bump);
  const slideMessages = slide?.messages?.length
    ? slide.messages
    : [];

  const openOverlay = () => {
    const names = slideMessages.length ? slideMessages : DEFAULT_MESSAGES.slice(0, 3);
    // Merge into session messages
    const byName = new Map(state.messages.map((m) => [m.name, m]));
    for (const name of names) {
      if (!byName.has(name)) {
        const row = { key: `${name}_${state.messages.length}`, name, sentiment: null as Sentiment | null };
        state.messages.push(row);
        byName.set(name, row);
      }
    }
    state.overlayOpen = true;
    bump();
  };

  const finishPlay = () => {
    if (!state.messages.length || state.messages.every((m) => !m.sentiment)) {
      state.messages = collectMessagesFromSlides(slides);
    }
    state.phase = 'feedback';
    state.overlayOpen = false;
    bump();
  };

  return html`
    <div class="osr-lwc-mirror clm-player slds-card" style="display:flex;flex-direction:column;min-height:100%">
      <header
        style="display:flex;align-items:center;justify-content:space-between;gap:0.5rem;padding:0.75rem 1rem;border-bottom:1px solid #e5e5e5;background:#fff"
      >
        <button type="button" class="slds-button slds-button_neutral" @click=${() => opts.onBack?.()}>
          ← Close
        </button>
        <div style="text-align:center;flex:1;min-width:0">
          <strong style="display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
            ${p ? nameOf(p) : presentationId || 'CLM Player'}
          </strong>
          <span class="slds-text-body_small slds-text-color_weak"
            >${p?.productName || ''} · ${state.phase === 'play' ? `Slide ${state.slideIndex + 1}/${slides.length}` : state.phase}</span
          >
        </div>
        <span style="width:4.5rem"></span>
      </header>

      ${state.phase === 'play'
        ? html`
            <div class="clm-slide-stage">
              ${state.slideLoading
                ? html`<div class="clm-slide-status">Loading slide…</div>`
                : nothing}
              ${state.slideSrc && state.slideIsPdfEmbed
                ? html`<iframe
                    class="clm-slide-pdf"
                    title=${slide?.title || 'Slide'}
                    src=${state.slideSrc}
                  ></iframe>`
                : state.slideSrc
                  ? html`<img
                      class="clm-slide-image"
                      src=${state.slideSrc}
                      alt=${slide?.title || 'Slide'}
                      @error=${() =>
                        handleSlideImageError(p, slide, state, opts.sfAuth, opts.online ?? false, bump)}
                    />`
                  : html`<div class="clm-slide-fallback">
                      <div class="clm-slide-fallback-kicker">
                        ${p?.formatType || 'CLM'} · ${opts.online ? 'online' : 'offline'}
                      </div>
                      <h2>${slide?.title || 'Slide'}</h2>
                      <p>
                        ${state.slideError ||
                        (p
                          ? 'Slide image unavailable — open Home while online to cache deck assets.'
                          : 'Presentation not in the offline manifest.')}
                      </p>
                    </div>`}
              ${slideMessages.length
                ? html`<button
                    type="button"
                    class="slds-button slds-button_neutral clm-capture-btn"
                    @click=${openOverlay}
                  >
                    Capture ${slideMessages.length} message${slideMessages.length === 1 ? '' : 's'}
                  </button>`
                : nothing}

              ${state.overlayOpen
                ? html`<div
                    style="position:absolute;inset:0;background:rgba(3,45,96,0.92);display:flex;align-items:center;justify-content:center;padding:1rem;z-index:2"
                  >
                    <div
                      style="background:#fff;color:#181818;border-radius:0.5rem;padding:1rem;width:min(28rem,100%);max-height:90%;overflow:auto"
                    >
                      <h3 style="margin:0 0 0.75rem">Slide messages</h3>
                      ${state.messages
                        .filter((m) => !slideMessages.length || slideMessages.includes(m.name))
                        .map(
                          (m) => html`
                            <div style="margin-bottom:0.75rem">
                              <strong>${m.name}</strong>
                              <div style="display:flex;gap:0.35rem;margin-top:0.35rem;flex-wrap:wrap">
                                ${SENTIMENTS.map(
                                  (s) => html`<button
                                    type="button"
                                    class="slds-button ${m.sentiment === s.value
                                      ? 'slds-button_brand'
                                      : 'slds-button_neutral'}"
                                    @click=${() => {
                                      m.sentiment = s.value;
                                      bump();
                                    }}
                                  >
                                    ${s.label}
                                  </button>`
                                )}
                              </div>
                            </div>
                          `
                        )}
                      <div style="display:flex;gap:0.5rem;justify-content:flex-end;margin-top:0.5rem">
                        <button
                          type="button"
                          class="slds-button slds-button_neutral"
                          @click=${() => {
                            state.overlayOpen = false;
                            bump();
                          }}
                        >
                          Close
                        </button>
                      </div>
                    </div>
                  </div>`
                : nothing}
            </div>

            <footer
              style="display:flex;gap:0.5rem;padding:0.75rem 1rem;border-top:1px solid #e5e5e5;background:#fff;flex-wrap:wrap"
            >
              <button
                type="button"
                class="slds-button slds-button_neutral"
                ?disabled=${state.slideIndex <= 0}
                @click=${() => {
                  state.slideIndex = Math.max(0, state.slideIndex - 1);
                  state.slideRetried = false;
                  bump();
                }}
              >
                Previous
              </button>
              <button
                type="button"
                class="slds-button slds-button_neutral"
                ?disabled=${state.slideIndex >= slides.length - 1}
                @click=${() => {
                  state.slideIndex = Math.min(slides.length - 1, state.slideIndex + 1);
                  state.slideRetried = false;
                  bump();
                }}
              >
                Next
              </button>
              <button
                type="button"
                class="slds-button slds-button_brand"
                style="margin-left:auto"
                @click=${finishPlay}
              >
                End &amp; capture sentiment
              </button>
            </footer>
          `
        : nothing}

      ${state.phase === 'feedback'
        ? html`
            <div style="padding:1rem;flex:1;overflow:auto">
              ${renderClmMessageFeedback({
                sessionId: state.sessionKey,
                messages: state.messages,
                productName: p?.productName,
                onChange: (msgs) => {
                  state.messages = msgs;
                },
                requestUpdate: bump
              })}
              <div style="display:flex;gap:0.5rem;justify-content:flex-end;margin-top:1rem">
                <button
                  type="button"
                  class="slds-button slds-button_brand"
                  @click=${() => {
                    state.phase = 'ratings';
                    bump();
                  }}
                >
                  Continue to ratings
                </button>
              </div>
            </div>
          `
        : nothing}

      ${state.phase === 'ratings'
        ? html`
            <div style="padding:1rem;flex:1;overflow:auto">
              ${renderClmRatingsCapture({
                visitId: opts.visitId,
                sessionId: state.sessionKey,
                score: state.ratingScore,
                notes: state.ratingNotes,
                onScore: (v) => {
                  state.ratingScore = v;
                  bump();
                },
                onNotes: (v) => {
                  state.ratingNotes = v;
                  bump();
                },
                requestUpdate: bump
              })}
              <div style="display:flex;gap:0.5rem;justify-content:flex-end;margin-top:1rem">
                <button
                  type="button"
                  class="slds-button slds-button_neutral"
                  @click=${() => {
                    state.phase = 'feedback';
                    bump();
                  }}
                >
                  Back
                </button>
                <button
                  type="button"
                  class="slds-button slds-button_brand"
                  @click=${() => {
                    state.phase = 'done';
                    state.saved = true;
                    opts.onComplete?.({
                      presentationId: presentationId,
                      sessionKey: state.sessionKey,
                      visitId: opts.visitId,
                      messages: state.messages,
                      ratingScore: state.ratingScore,
                      ratingNotes: state.ratingNotes
                    });
                    bump();
                  }}
                >
                  Save session
                </button>
              </div>
            </div>
          `
        : nothing}

      ${state.phase === 'done'
        ? html`
            <div class="slds-p-around_large" style="text-align:center;flex:1">
              <h2 class="slds-text-heading_medium">Session saved</h2>
              <p class="slds-text-color_weak">
                Sentiment and ratings queued for sync
                ${opts.visitId ? ' against this visit' : ''}.
              </p>
              <button type="button" class="slds-button slds-button_brand" @click=${() => opts.onBack?.()}>
                Done
              </button>
            </div>
          `
        : nothing}
    </div>
  `;
}
