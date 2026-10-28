export async function loadScript(_component, src) {
    if (typeof document === 'undefined') {
        return;
    }
    const existing = document.querySelector(`script[src="${src}"]`);
    if (existing) {
        if (existing.dataset.clmLoaded === '1') {
            return;
        }
        if (existing.dataset.clmFailed === '1') {
            existing.remove();
        } else {
            await new Promise((resolve, reject) => {
                existing.addEventListener('load', () => resolve(), { once: true });
                existing.addEventListener(
                    'error',
                    () => reject(new Error(`Failed to load script: ${src}`)),
                    { once: true }
                );
            });
            return;
        }
    }
    await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.src = src;
        script.async = true;
        script.onload = () => {
            script.dataset.clmLoaded = '1';
            resolve();
        };
        script.onerror = () => {
            script.dataset.clmFailed = '1';
            reject(new Error(`Failed to load script: ${src}`));
        };
        document.head.appendChild(script);
    });
}

export async function loadStyle(_component, href) {
    if (typeof document === 'undefined') {
        return;
    }
    const existing = document.querySelector(`link[href="${href}"]`);
    if (existing) {
        if (existing.dataset.clmLoaded === '1') {
            return;
        }
        if (existing.dataset.clmFailed === '1') {
            existing.remove();
        } else {
            await new Promise((resolve, reject) => {
                existing.addEventListener('load', () => resolve(), { once: true });
                existing.addEventListener(
                    'error',
                    () => reject(new Error(`Failed to load style: ${href}`)),
                    { once: true }
                );
            });
            return;
        }
    }
    await new Promise((resolve, reject) => {
        const link = document.createElement('link');
        link.rel = 'stylesheet';
        link.href = href;
        link.onload = () => {
            link.dataset.clmLoaded = '1';
            resolve();
        };
        link.onerror = () => {
            link.dataset.clmFailed = '1';
            reject(new Error(`Failed to load style: ${href}`));
        };
        document.head.appendChild(link);
    });
}
