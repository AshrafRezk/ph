import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig, loadEnv } from 'vite';
import basicSsl from '@vitejs/plugin-basic-ssl';
import { transformSync } from '@lwc/compiler';

const root = path.dirname(fileURLToPath(import.meta.url));
const lwcDir = path.resolve(root, '../force-app/main/default/lwc');
const engineDom = path.resolve(root, 'node_modules/@lwc/engine-dom/dist/index.js');

const ASSET_PREFIX = '\0lwc-asset:';

function encodeAsset(kind, filename, scoped) {
    const scopedFlag = scoped ? '1' : '0';
    return `${ASSET_PREFIX}${kind}:${scopedFlag}:${filename}.virtual.js`;
}

function decodeAsset(id) {
    if (!id.startsWith(ASSET_PREFIX) || !id.endsWith('.virtual.js')) {
        return null;
    }
    const rest = id.slice(ASSET_PREFIX.length, -'.virtual.js'.length);
    const kindEnd = rest.indexOf(':');
    const kind = rest.slice(0, kindEnd);
    const scopedEnd = rest.indexOf(':', kindEnd + 1);
    const scoped = rest.slice(kindEnd + 1, scopedEnd) === '1';
    const filename = rest.slice(scopedEnd + 1);
    return { kind, scoped, filename };
}

function virtualFromImporter(id, importer) {
    if (!importer || (!id.endsWith('.html') && !id.includes('.css'))) {
        return null;
    }
    const decodedImporter = decodeAsset(importer);
    const importerFile = decodedImporter ? decodedImporter.filename : importer.split('?')[0];
    if (!isSfdxLwcFile(importerFile)) {
        return null;
    }
    const bare = id.split('?')[0];
    const filename = path.normalize(path.resolve(path.dirname(importerFile), bare));
    if (bare.endsWith('.html')) {
        return encodeAsset('html', filename, false);
    }
    if (bare.endsWith('.css')) {
        const scoped = id.includes('scoped=true') || bare.endsWith('.scoped.css');
        return encodeAsset('css', filename, scoped);
    }
    return null;
}

const stubsLightningDir = path.resolve(root, 'src/stubs/lightning');

function componentMeta(filename) {
    const normalized = path.normalize(filename);
    if (normalized.startsWith(stubsLightningDir + path.sep)) {
        return {
            name: path.basename(path.dirname(filename)),
            namespace: 'lightning'
        };
    }
    return {
        name: path.basename(path.dirname(filename)),
        namespace: 'c'
    };
}

function isSfdxLwcFile(filename) {
    const normalized = path.normalize(filename);
    return (
        normalized.startsWith(lwcDir + path.sep) ||
        normalized.startsWith(stubsLightningDir + path.sep)
    );
}

function compileLwcSource(src, filename, extra = {}) {
    const { name, namespace } = componentMeta(filename);
    return transformSync(src, filename, {
        name,
        namespace,
        enableStaticContentOptimization: false,
        ...extra
    });
}

function compileSfdxLwc() {
    return {
        name: 'compile-sfdx-lwc',
        enforce: 'pre',
        resolveId(id, importer) {
            if (id === 'lwc' || id === '@lwc/engine-dom') {
                return engineDom;
            }
            if (id.startsWith('c/')) {
                const name = id.slice(2);
                const file = path.join(lwcDir, name, `${name}.js`);
                if (fs.existsSync(file)) {
                    return file;
                }
            }
            if (id === '@salesforce/apex') {
                return path.resolve(root, 'src/apex/refreshApex.js');
            }
            if (id.startsWith('@salesforce/apex/')) {
                const parts = id.split('/');
                const method = parts[parts.length - 1].split('.')[1] || parts[parts.length - 1];
                const specificStub = path.resolve(root, `src/apex/${method}.js`);
                if (fs.existsSync(specificStub)) {
                    return specificStub;
                }
                return path.resolve(root, 'src/apex/noopApex.js');
            }
            if (id.startsWith('@salesforce/schema/')) {
                const spec = id.slice('@salesforce/schema/'.length);
                if (spec.startsWith('Time_Off_Request__c')) {
                    const [objectName, fieldName] = spec.split('.');
                    const target = fieldName
                        ? `src/schema/${fieldName}.js`
                        : `src/schema/${objectName}.js`;
                    return path.resolve(root, target);
                }
                // Virtual module carrying the real object/field API names so
                // getRecord + getFieldValue can resolve fields offline.
                return '\0sfschema:' + spec;
            }
            if (id === 'lightning/uiRecordApi') {
                return path.resolve(root, 'src/stubs/uiRecordApi.js');
            }
            if (id === 'lightning/navigation') {
                return path.resolve(root, 'src/stubs/navigation.js');
            }
            if (id === 'lightning/platformShowToastEvent') {
                return path.resolve(root, 'src/stubs/showToastEvent.js');
            }
            if (id === 'lightning/confirm') {
                return path.resolve(root, 'src/stubs/confirm.js');
            }
            if (id === 'lightning/alert') {
                return path.resolve(root, 'src/stubs/alert.js');
            }
            if (id === 'lightning/prompt') {
                return path.resolve(root, 'src/stubs/prompt.js');
            }
            if (id === 'lightning/platformResourceLoader') {
                return path.resolve(root, 'src/stubs/resourceLoader.js');
            }
            if (id.startsWith('lightning/')) {
                const name = id.slice('lightning/'.length);
                const file = path.resolve(stubsLightningDir, name, `${name}.js`);
                if (fs.existsSync(file)) {
                    return file;
                }
                const generic = path.resolve(stubsLightningDir, 'generic', 'generic.js');
                if (fs.existsSync(generic)) {
                    this.warn(`[osr] no dedicated stub for ${id}; using lightning/generic`);
                    return generic;
                }
            }
            if (id === '@salesforce/user/Id') {
                return path.resolve(root, 'src/stubs/userId.js');
            }
            if (id === '@salesforce/client/formFactor') {
                return path.resolve(root, 'src/stubs/formFactor.js');
            }
            if (id === '@salesforce/resourceUrl/jszip') {
                return path.resolve(root, 'src/stubs/resourceJszip.js');
            }
            if (id === '@salesforce/resourceUrl/pdfjs') {
                return path.resolve(root, 'src/stubs/resourcePdfjs.js');
            }
            if (id.startsWith('@salesforce/resourceUrl/')) {
                return path.resolve(root, 'src/stubs/leafletUrl.js');
            }
            return virtualFromImporter(id, importer);
        },
        load(id) {
            if (id.startsWith('\0sfschema:')) {
                const spec = id.slice('\0sfschema:'.length);
                const dot = spec.indexOf('.');
                if (dot > 0) {
                    const objectApiName = spec.slice(0, dot);
                    return `export default { objectApiName: ${JSON.stringify(objectApiName)}, fieldApiName: ${JSON.stringify(spec)} };`;
                }
                return `export default { objectApiName: ${JSON.stringify(spec)} };`;
            }
            const asset = decodeAsset(id);
            if (!asset) {
                return null;
            }
            const { kind, filename, scoped } = asset;
            if (kind === 'html') {
                const src = fs.existsSync(filename)
                    ? fs.readFileSync(filename, 'utf8')
                    : '<template></template>';
                const { code, warnings } = compileLwcSource(src, filename, {
                    isExplicitImport: true
                });
                if (warnings) {
                    for (const warning of warnings) {
                        this.warn(warning.message || String(warning));
                    }
                }
                return code;
            }
            if (kind === 'css') {
                if (!fs.existsSync(filename)) {
                    return 'export default undefined;';
                }
                const src = fs.readFileSync(filename, 'utf8');
                const { code } = compileLwcSource(src, filename, {
                    isExplicitImport: true,
                    scopedStyles: scoped
                });
                return code;
            }
            return null;
        },
        transform(src, id) {
            if (id.includes('@lwc/engine-dom') && src.includes('sourceMappingURL=')) {
                return {
                    code: src.replace(/\/\/# sourceMappingURL=.*$/m, ''),
                    map: null
                };
            }
            const filename = id.split('?')[0];
            if (!isSfdxLwcFile(filename) || path.extname(filename) !== '.js') {
                return null;
            }
            // Utility modules (no template) stay as plain JS.
            const htmlPath = filename.replace(/\.js$/, '.html');
            if (!fs.existsSync(htmlPath)) {
                return null;
            }
            const { code, warnings } = compileLwcSource(src, filename, { isExplicitImport: false });
            if (warnings) {
                for (const warning of warnings) {
                    this.warn(warning.message || String(warning));
                }
            }
            return { code, map: null };
        }
    };
}

function salesforceProxy(instanceUrl) {
    return {
        target: instanceUrl,
        changeOrigin: true,
        secure: true,
        configure(proxy) {
            proxy.on('error', (_err, _req, res) => {
                if (res && !res.headersSent && typeof res.writeHead === 'function') {
                    res.writeHead(503, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ message: 'Offline' }));
                }
            });
        }
    };
}

/** Local stand-in for Netlify `sf-token` / `sf-api` so web CORS works in `npm run dev`. */
function netlifyFunctionsPlugin() {
    return {
        name: 'zeta-netlify-functions',
        configureServer(server) {
            // Match production: /oauth/callback must load the SPA (not a missing static file).
            server.middlewares.use((req, res, next) => {
                const pathOnly = (req.url || '').split('?')[0];
                if (pathOnly === '/oauth/callback' || pathOnly === '/oauth/callback/') {
                    req.url = '/' + ((req.url || '').includes('?') ? req.url.slice(req.url.indexOf('?')) : '');
                }
                next();
            });

            server.middlewares.use('/.netlify/functions/sf-token', async (req, res) => {
                if (req.method === 'OPTIONS') {
                    res.statusCode = 204;
                    res.setHeader('Access-Control-Allow-Origin', '*');
                    res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
                    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
                    res.end();
                    return;
                }
                if (req.method !== 'POST') {
                    res.statusCode = 405;
                    res.end('Method Not Allowed');
                    return;
                }
                try {
                    const chunks = [];
                    for await (const chunk of req) chunks.push(Buffer.from(chunk));
                    const body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
                    const grantType = body.grant_type || 'authorization_code';
                    const tokenUrl =
                        body.tokenUrl || 'https://login.salesforce.com/services/oauth2/token';
                    const params = new URLSearchParams({
                        grant_type: grantType,
                        client_id: body.client_id || ''
                    });
                    if (grantType === 'refresh_token') {
                        params.set('refresh_token', body.refresh_token || '');
                    } else {
                        params.set('redirect_uri', body.redirect_uri || '');
                        params.set('code', body.code || '');
                        params.set('code_verifier', body.code_verifier || '');
                    }
                    const upstream = await fetch(tokenUrl, {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                        body: params
                    });
                    const text = await upstream.text();
                    res.statusCode = upstream.status;
                    res.setHeader('Access-Control-Allow-Origin', '*');
                    res.setHeader('Content-Type', 'application/json');
                    res.end(text);
                } catch (e) {
                    res.statusCode = 500;
                    res.end(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }));
                }
            });

            server.middlewares.use('/.netlify/functions/sf-api', async (req, res) => {
                if (req.method === 'OPTIONS') {
                    res.statusCode = 204;
                    res.setHeader('Access-Control-Allow-Origin', '*');
                    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
                    res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
                    res.end();
                    return;
                }
                if (req.method !== 'POST') {
                    res.statusCode = 405;
                    res.end('Method Not Allowed');
                    return;
                }
                try {
                    const chunks = [];
                    for await (const chunk of req) chunks.push(Buffer.from(chunk));
                    const payload = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
                    const targetUrl = String(payload.url || '');
                    const host = new URL(targetUrl).hostname.toLowerCase();
                    const allowed =
                        host === 'login.salesforce.com' ||
                        host === 'test.salesforce.com' ||
                        host.endsWith('.salesforce.com') ||
                        host.endsWith('.force.com') ||
                        host.endsWith('.site.com') ||
                        host.endsWith('.salesforce-sites.com');
                    if (!targetUrl.startsWith('https://') || !allowed) {
                        res.statusCode = 400;
                        res.end(
                            JSON.stringify({ error: 'URL host is not an allowed Salesforce endpoint' })
                        );
                        return;
                    }
                    const method = String(payload.method || 'GET').toUpperCase();
                    const headers = {
                        Accept: 'application/json',
                        ...(payload.headers || {})
                    };
                    if (payload.authorization) headers.Authorization = payload.authorization;
                    let upstreamBody;
                    if (payload.body != null && method !== 'GET' && method !== 'DELETE') {
                        upstreamBody =
                            typeof payload.body === 'string'
                                ? payload.body
                                : JSON.stringify(payload.body);
                        headers['Content-Type'] = headers['Content-Type'] || 'application/json';
                    }
                    const upstream = await fetch(targetUrl, {
                        method,
                        headers,
                        body: upstreamBody
                    });
                    const contentType =
                        upstream.headers.get('content-type') || 'application/octet-stream';
                    const buf = Buffer.from(await upstream.arrayBuffer());
                    res.statusCode = upstream.status;
                    res.setHeader('Access-Control-Allow-Origin', '*');
                    res.setHeader('Content-Type', contentType);
                    res.end(buf);
                } catch (e) {
                    res.statusCode = 500;
                    res.end(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }));
                }
            });
        }
    };
}

export default defineConfig(({ mode }) => {
    const env = loadEnv(mode, root, '');
    // Local /services proxy only — production uses Netlify sf-api. Require env; no tenant default.
    const instanceUrl = (env.VITE_SF_INSTANCE_URL || '').replace(/\/$/, '');

    return {
        root,
        base: '/',
        publicDir: 'public',
        plugins: [
            compileSfdxLwc(),
            netlifyFunctionsPlugin(),
            basicSsl({
                name: 'zeta-field-pwa',
                domains: ['localhost']
            })
        ],
        optimizeDeps: {
            exclude: ['c/fieldRepHomeMetrics', 'c/clmOfflineStore']
        },
        server: {
            port: 5173,
            fs: {
                allow: [root, path.resolve(root, '..')]
            },
            ...(instanceUrl
                ? { proxy: { '/services': salesforceProxy(instanceUrl) } }
                : {})
        },
        preview: {
            port: 4173,
            ...(instanceUrl
                ? { proxy: { '/services': salesforceProxy(instanceUrl) } }
                : {})
        },
        build: {
            outDir: 'dist',
            emptyOutDir: true
        }
    };
});
