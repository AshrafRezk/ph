import { cachePayload, cacheRead, cacheWrite } from './tabCache.js';
import { sfGet, sfSend } from './sfRest.js';
import {
    escapeHtml,
    errorMessage,
    formatRelative,
    formatSynced,
    initials,
    isNetworkError
} from './viewUtils.js';

const FEED_KEY = 'chatter.news';
const OUTBOX_KEY = 'chatter.outbox';
const PAGE_SIZE = 25;

let rootEl = null;
let loading = false;

function readOutbox() {
    const payload = cachePayload(OUTBOX_KEY);
    return Array.isArray(payload) ? payload : [];
}

function writeOutbox(items) {
    cacheWrite(OUTBOX_KEY, items);
}

function enqueue(action) {
    writeOutbox([...readOutbox(), { ...action, queuedAt: Date.now() }]);
}

function feedText(element) {
    return (
        (element && element.body && element.body.text) ||
        (element && element.header && element.header.text) ||
        ''
    );
}

function actorName(element) {
    return (element && element.actor && element.actor.displayName) || 'Someone';
}

function likeInfo(element) {
    const likes = element && element.capabilities && element.capabilities.chatterLikes;
    return {
        liked: !!(likes && likes.isLikedByCurrentUser),
        count: (likes && likes.page && likes.page.total) || 0,
        myLikeId: likes && likes.myLike && likes.myLike.id
    };
}

function commentsOf(element) {
    const page = element && element.capabilities && element.capabilities.comments && element.capabilities.comments.page;
    return {
        items: (page && page.items) || [],
        total: (page && page.total) || 0
    };
}

function bannerHtml(savedAt, staleMessage) {
    const bits = [];
    if (savedAt) bits.push(escapeHtml(formatSynced(savedAt)));
    if (staleMessage) bits.push(escapeHtml(staleMessage));
    if (!bits.length) return '';
    return `<div class="osr-tab-banner" role="status">${bits.join(' ù ')}</div>`;
}

function commentHtml(comment) {
    const name = (comment.user && comment.user.displayName) || 'Someone';
    return `<li class="osr-chatter-comment">
        <span class="osr-chatter-avatar osr-chatter-avatar--sm" aria-hidden="true">${escapeHtml(initials(name))}</span>
        <div>
            <div class="osr-chatter-meta"><strong>${escapeHtml(name)}</strong> <span>${escapeHtml(formatRelative(comment.createdDate))}</span></div>
            <p>${escapeHtml((comment.body && comment.body.text) || '')}</p>
        </div>
    </li>`;
}

function pendingPostHtml(item) {
    return `<article class="osr-chatter-item osr-chatter-item--pending" data-pending-id="${escapeHtml(item.clientId)}">
        <span class="osr-chatter-avatar" aria-hidden="true">${escapeHtml(initials('You'))}</span>
        <div class="osr-chatter-body">
            <div class="osr-chatter-meta"><strong>You</strong> <span>Pending</span></div>
            <p>${escapeHtml(item.text)}</p>
        </div>
    </article>`;
}

function itemHtml(element) {
    const name = actorName(element);
    const likes = likeInfo(element);
    const comments = commentsOf(element);
    const likeLabel = likes.liked ? 'Unlike' : 'Like';
    return `<article class="osr-chatter-item" data-id="${escapeHtml(element.id)}">
        <span class="osr-chatter-avatar" aria-hidden="true">${escapeHtml(initials(name))}</span>
        <div class="osr-chatter-body">
            <div class="osr-chatter-meta">
                <strong>${escapeHtml(name)}</strong>
                <span>${escapeHtml(formatRelative(element.createdDate))}</span>
            </div>
            <p>${escapeHtml(feedText(element))}</p>
            <div class="osr-chatter-actions">
                <button type="button" class="osr-tab-btn osr-tab-btn--ghost osr-chatter-like${likes.liked ? ' is-on' : ''}" data-action="like" aria-pressed="${likes.liked}">
                    ${likeLabel}${likes.count ? ` ù ${likes.count}` : ''}
                </button>
                <button type="button" class="osr-tab-btn osr-tab-btn--ghost" data-action="toggle-comments">
                    Comment${comments.total ? ` ù ${comments.total}` : ''}
                </button>
            </div>
            <div class="osr-chatter-thread" hidden>
                <ul class="osr-chatter-comments">${comments.items.map(commentHtml).join('')}</ul>
                <form class="osr-chatter-reply" data-action="comment">
                    <label class="visually-hidden" for="reply-${escapeHtml(element.id)}">Write a comment</label>
                    <input id="reply-${escapeHtml(element.id)}" type="text" maxlength="10000" placeholder="Write a commentù" />
                    <button type="submit" class="osr-tab-btn">Post</button>
                </form>
            </div>
        </div>
    </article>`;
}

function render(elements, { savedAt, staleMessage, pending = [] } = {}) {
    if (!rootEl) return;
    const feed = rootEl.querySelector('[data-chatter-feed]');
    const banner = rootEl.querySelector('[data-chatter-banner]');
    const empty = rootEl.querySelector('[data-chatter-empty]');
    if (banner) banner.innerHTML = bannerHtml(savedAt, staleMessage);
    const pendingHtml = pending
        .filter((item) => item.type === 'post')
        .map(pendingPostHtml)
        .join('');
    const itemsHtml = (elements || []).map(itemHtml).join('');
    if (feed) {
        feed.innerHTML = pendingHtml + itemsHtml;
    }
    if (empty) {
        const hasItems = !!(elements && elements.length) || pending.length > 0;
        empty.hidden = hasItems;
        if (!hasItems) {
            empty.textContent = staleMessage || 'No posts in your news feed yet.';
        }
    }
}

function ensureShell(root) {
    if (root.querySelector('.osr-chatter')) return;
    root.innerHTML = `
        <section class="osr-tab osr-chatter">
            <header class="osr-tab-header">
                <h1>Chatter</h1>
                <p>Company news feed. Posts, likes, and comments sync when you are back online.</p>
            </header>
            <div data-chatter-banner></div>
            <form class="osr-chatter-composer" data-chatter-composer>
                <label class="visually-hidden" for="osr-chatter-input">Share an update</label>
                <textarea id="osr-chatter-input" rows="3" maxlength="10000" placeholder="Share an updateù"></textarea>
                <div class="osr-tab-row">
                    <button type="submit" class="osr-tab-btn osr-tab-btn--primary">Share</button>
                    <button type="button" class="osr-tab-btn" data-chatter-refresh>Refresh</button>
                </div>
            </form>
            <p class="osr-tab-empty" data-chatter-empty>Loading feedù</p>
            <div class="osr-chatter-feed" data-chatter-feed></div>
        </section>
    `;
    bind(root);
}

function bind(root) {
    const composer = root.querySelector('[data-chatter-composer]');
    const refresh = root.querySelector('[data-chatter-refresh]');
    const feed = root.querySelector('[data-chatter-feed]');
    if (composer) {
        composer.addEventListener('submit', async (event) => {
            event.preventDefault();
            const input = composer.querySelector('textarea');
            const text = (input && input.value || '').trim();
            if (!text) return;
            input.value = '';
            await shareUpdate(text);
        });
    }
    if (refresh) {
        refresh.addEventListener('click', () => loadFeed({ force: true }));
    }
    if (feed) {
        feed.addEventListener('click', onFeedClick);
        feed.addEventListener('submit', onCommentSubmit);
    }
}

async function shareUpdate(text) {
    const clientId = `p-${Date.now()}`;
    try {
        await sfSend('/chatter/feed-elements', 'POST', {
            body: { messageSegments: [{ type: 'Text', text }] },
            feedElementType: 'FeedItem',
            subjectId: 'me'
        });
        await loadFeed({ force: true });
    } catch (error) {
        enqueue({ type: 'post', text, clientId });
        const cached = cacheRead(FEED_KEY);
        render((cached && cached.payload && cached.payload.elements) || [], {
            savedAt: cached && cached.savedAt,
            staleMessage: isNetworkError(error)
                ? 'Saved offline ù will post when you are back online.'
                : errorMessage(error),
            pending: readOutbox()
        });
    }
}

async function toggleLike(elementId) {
    const cached = cacheRead(FEED_KEY);
    const elements = (cached && cached.payload && cached.payload.elements) || [];
    const element = elements.find((item) => item.id === elementId);
    const likes = likeInfo(element || {});
    try {
        if (likes.liked && likes.myLikeId) {
            await sfSend(
                `/chatter/feed-elements/${encodeURIComponent(elementId)}/capabilities/chatterLikes/items/${encodeURIComponent(likes.myLikeId)}`,
                'DELETE'
            );
        } else {
            await sfSend(
                `/chatter/feed-elements/${encodeURIComponent(elementId)}/capabilities/chatterLikes/items`,
                'POST'
            );
        }
        await loadFeed({ force: true });
    } catch (error) {
        enqueue({
            type: 'like',
            feedElementId: elementId,
            liked: !likes.liked,
            myLikeId: likes.myLikeId || null
        });
        const staleMessage = isNetworkError(error)
            ? 'Like queued until you are back online.'
            : errorMessage(error);
        render(elements, {
            savedAt: cached && cached.savedAt,
            staleMessage,
            pending: readOutbox()
        });
    }
}

async function postComment(elementId, text) {
    try {
        await sfSend(
            `/chatter/feed-elements/${encodeURIComponent(elementId)}/capabilities/comments/items`,
            'POST',
            { body: { messageSegments: [{ type: 'Text', text }] } }
        );
        await loadFeed({ force: true });
    } catch (error) {
        enqueue({ type: 'comment', feedElementId: elementId, text, clientId: `c-${Date.now()}` });
        const cached = cacheRead(FEED_KEY);
        render((cached && cached.payload && cached.payload.elements) || [], {
            savedAt: cached && cached.savedAt,
            staleMessage: isNetworkError(error)
                ? 'Comment queued until you are back online.'
                : errorMessage(error),
            pending: readOutbox()
        });
    }
}

function onFeedClick(event) {
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const item = button.closest('[data-id]');
    if (!item) return;
    const id = item.dataset.id;
    const action = button.dataset.action;
    if (action === 'like') {
        toggleLike(id);
        return;
    }
    if (action === 'toggle-comments') {
        const thread = item.querySelector('.osr-chatter-thread');
        if (thread) thread.hidden = !thread.hidden;
    }
}

function onCommentSubmit(event) {
    const form = event.target.closest('form[data-action="comment"]');
    if (!form) return;
    event.preventDefault();
    const item = form.closest('[data-id]');
    const input = form.querySelector('input');
    const text = (input && input.value || '').trim();
    if (!item || !text) return;
    input.value = '';
    postComment(item.dataset.id, text);
}

async function executeOutboxItem(item) {
    if (item.type === 'post') {
        await sfSend('/chatter/feed-elements', 'POST', {
            body: { messageSegments: [{ type: 'Text', text: item.text }] },
            feedElementType: 'FeedItem',
            subjectId: 'me'
        });
        return;
    }
    if (item.type === 'comment') {
        await sfSend(
            `/chatter/feed-elements/${encodeURIComponent(item.feedElementId)}/capabilities/comments/items`,
            'POST',
            { body: { messageSegments: [{ type: 'Text', text: item.text }] } }
        );
        return;
    }
    if (item.type === 'like') {
        if (item.liked === false && item.myLikeId) {
            await sfSend(
                `/chatter/feed-elements/${encodeURIComponent(item.feedElementId)}/capabilities/chatterLikes/items/${encodeURIComponent(item.myLikeId)}`,
                'DELETE'
            );
            return;
        }
        await sfSend(
            `/chatter/feed-elements/${encodeURIComponent(item.feedElementId)}/capabilities/chatterLikes/items`,
            'POST'
        );
    }
}

async function flushOutbox() {
    const items = readOutbox();
    if (!items.length) return;
    const remaining = [];
    for (const item of items) {
        try {
            await executeOutboxItem(item);
        } catch (error) {
            remaining.push(item);
            if (isNetworkError(error)) break;
        }
    }
    writeOutbox(remaining);
}

async function loadFeed({ force = false } = {}) {
    if (!rootEl || loading) return;
    loading = true;
    const cached = cacheRead(FEED_KEY);
    const cachedElements = (cached && cached.payload && cached.payload.elements) || [];
    if (cachedElements.length && !force) {
        render(cachedElements, { savedAt: cached.savedAt, pending: readOutbox() });
    }
    try {
        await flushOutbox();
        const data = await sfGet(`/chatter/feeds/news/me/feed-elements?pageSize=${PAGE_SIZE}`);
        const elements = (data && data.elements) || [];
        cacheWrite(FEED_KEY, { elements });
        render(elements, { savedAt: Date.now(), pending: readOutbox() });
    } catch (error) {
        render(cachedElements, {
            savedAt: cached && cached.savedAt,
            staleMessage: cachedElements.length
                ? isNetworkError(error)
                    ? 'Showing cached feed.'
                    : errorMessage(error)
                : errorMessage(error),
            pending: readOutbox()
        });
        if (!cachedElements.length && rootEl) {
            const empty = rootEl.querySelector('[data-chatter-empty]');
            if (empty) {
                empty.hidden = false;
                empty.textContent = errorMessage(error);
            }
        }
    } finally {
        loading = false;
    }
}

export function mountChatterView(root) {
    if (!root) return;
    rootEl = root;
    ensureShell(root);
    loadFeed();
}
