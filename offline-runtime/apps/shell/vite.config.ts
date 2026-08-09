import { defineConfig, type Plugin } from 'vite';
import path from 'node:path';
import { resolve } from 'node:path';

/** Local stand-in for Netlify `sf-api` so web CORS works in `npm run dev`. */
function salesforceProxyPlugin(): Plugin {
  return {
    name: 'osr-salesforce-proxy',
    configureServer(server) {
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
          const chunks: Buffer[] = [];
          for await (const chunk of req) chunks.push(Buffer.from(chunk));
          const payload = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}') as {
            url?: string;
            method?: string;
            authorization?: string;
            body?: unknown;
            headers?: Record<string, string>;
          };
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
            res.end(JSON.stringify({ error: 'URL host is not an allowed Salesforce endpoint' }));
            return;
          }
          const method = String(payload.method || 'GET').toUpperCase();
          const headers: Record<string, string> = {
            Accept: 'application/json',
            ...(payload.headers || {})
          };
          if (payload.authorization) headers.Authorization = payload.authorization;
          let upstreamBody: string | undefined;
          if (payload.body != null && method !== 'GET' && method !== 'DELETE') {
            upstreamBody =
              typeof payload.body === 'string' ? payload.body : JSON.stringify(payload.body);
            headers['Content-Type'] = headers['Content-Type'] || 'application/json';
          }
          const upstream = await fetch(targetUrl, { method, headers, body: upstreamBody });
          const text = await upstream.text();
          res.statusCode = upstream.status;
          res.setHeader('Access-Control-Allow-Origin', '*');
          res.setHeader('Content-Type', upstream.headers.get('content-type') || 'application/json');
          res.end(text);
        } catch (e) {
          res.statusCode = 500;
          res.end(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }));
        }
      });
    }
  };
}

export default defineConfig({
  root: '.',
  server: { port: 5173, host: true },
  plugins: [salesforceProxyPlugin()],
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    rollupOptions: {
      input: {
        main: resolve(__dirname, 'index.html'),
        lwcHost: resolve(__dirname, 'osr-lwc-host.html')
      }
    }
  },
  resolve: {
    alias: {
      '@osr/db': path.resolve(__dirname, '../../packages/db/src/index.ts'),
      '@osr/sync': path.resolve(__dirname, '../../packages/sync/src/index.ts'),
      '@osr/validation': path.resolve(__dirname, '../../packages/validation/src/index.ts'),
      '@osr/ui-runtime': path.resolve(__dirname, '../../packages/ui-runtime/src/index.ts'),
      '@osr/bridge': path.resolve(__dirname, '../../packages/bridge/src/index.ts'),
      '@osr/platform': path.resolve(__dirname, '../../packages/platform/src/index.ts'),
      '@osr/lwc-engine': path.resolve(__dirname, '../../packages/lwc-engine/src/index.ts'),
      '@osr/lwc-compile/scan': path.resolve(__dirname, '../../packages/lwc-compile/src/scan.ts'),
      '@osr/platform/apex': path.resolve(__dirname, '../../packages/platform/src/apex.ts'),
      // Prefer engine-dom only — avoid pulling Node @lwc/compiler via package "lwc"
      lwc: path.resolve(__dirname, '../../node_modules/@lwc/engine-dom')
    }
  }
});
