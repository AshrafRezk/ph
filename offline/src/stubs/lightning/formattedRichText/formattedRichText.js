import { LightningElement, api } from 'lwc';

const ALLOWED = new Set(['P', 'BR', 'B', 'STRONG', 'I', 'EM', 'U', 'UL', 'OL', 'LI', 'A', 'H1', 'H2', 'H3', 'H4', 'SPAN', 'DIV', 'BLOCKQUOTE', 'CODE', 'PRE']);

// Keeps the rich-text tags Salesforce allows and drops scripts, handlers and styles.
function sanitize(html) {
    const doc = new DOMParser().parseFromString(`<div>${html || ''}</div>`, 'text/html');
    const walk = (node) => {
        Array.from(node.childNodes).forEach((child) => {
            if (child.nodeType === 1) {
                if (!ALLOWED.has(child.tagName)) {
                    if (['SCRIPT', 'STYLE', 'IFRAME', 'OBJECT'].includes(child.tagName)) {
                        child.remove();
                        return;
                    }
                    walk(child);
                    child.replaceWith(...child.childNodes);
                    return;
                }
                Array.from(child.attributes).forEach((attr) => {
                    const keep = child.tagName === 'A' && attr.name === 'href' && /^(https?:|mailto:|tel:)/i.test(attr.value);
                    if (!keep) child.removeAttribute(attr.name);
                });
                if (child.tagName === 'A') {
                    child.setAttribute('target', '_blank');
                    child.setAttribute('rel', 'noopener noreferrer');
                }
                walk(child);
            } else if (child.nodeType !== 3) {
                child.remove();
            }
        });
    };
    const root = doc.body.firstChild;
    walk(root);
    return root.innerHTML;
}

export default class FormattedRichText extends LightningElement {
    @api value = '';

    renderedCallback() {
        const host = this.template.querySelector('.rich-text');
        if (!host) return;
        const html = sanitize(this.value);
        if (host.dataset.html === html) return;
        host.dataset.html = html;
        host.innerHTML = html;
    }
}
