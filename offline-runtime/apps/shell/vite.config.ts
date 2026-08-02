import { defineConfig } from 'vite';
import path from 'node:path';
import { resolve } from 'node:path';

export default defineConfig({
  root: '.',
  server: { port: 5173, host: true },
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
