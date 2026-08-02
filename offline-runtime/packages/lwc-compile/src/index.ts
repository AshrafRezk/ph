/**
 * LWC compile + compatibility scanning for OSR offline engine.
 * Browser apps should import `@osr/lwc-compile/scan` only (no @lwc/compiler).
 */
export {
  scanLwcSource,
  rewriteApexImportsToInvoker,
  buildFallbackModule,
  compileToolingBundle,
  pascal,
  STUBBED_LIGHTNING_TAGS,
  COMPILE_ALLOWLIST,
  type CompatFinding,
  type CompileResult,
  type AllowlistName
} from './scan.js';

export {
  compileLwcModule,
  compileToolingBundleNative,
  type CompileInput
} from './compile.js';
