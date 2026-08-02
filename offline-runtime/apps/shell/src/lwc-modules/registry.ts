/**
 * Registry of engine-ready modules shipped with the shell (build-time allowlist).
 * These run inside the local LWC iframe via Custom Element or LWC createElement.
 */
import HomeOfficeMessages from './homeOfficeMessages';
import HelloRecord from './helloRecord';
import FieldRepHomeNextBestCustomer from './fieldRepHomeNextBestCustomer';
import FieldRepHomeTodayPlan from './fieldRepHomeTodayPlan';
import FieldRepHomeMetrics from './fieldRepHomeMetrics';
import FieldRepPlanner from './fieldRepPlanner';
import VisitCallShell from './visitCallShell';

export type EngineModuleKind = 'ce' | 'lwc';

export type EngineModuleEntry = {
  bundle: string;
  kind: EngineModuleKind;
  /** Custom element tag when kind=ce */
  tag?: string;
  Ctor: CustomElementConstructor | any;
  label?: string;
};

const ENTRIES: EngineModuleEntry[] = [
  {
    bundle: 'c/homeOfficeMessages',
    kind: 'ce',
    tag: 'osr-home-office-messages',
    Ctor: HomeOfficeMessages,
    label: 'Office Messages'
  },
  {
    bundle: 'c/helloRecord',
    kind: 'ce',
    tag: 'osr-hello-record',
    Ctor: HelloRecord,
    label: 'Hello Record'
  },
  {
    bundle: 'c/fieldRepHomeNextBestCustomer',
    kind: 'ce',
    tag: 'osr-field-rep-home-nbc',
    Ctor: FieldRepHomeNextBestCustomer,
    label: 'Next Best Customer'
  },
  {
    bundle: 'c/fieldRepHomeTodayPlan',
    kind: 'ce',
    tag: 'osr-field-rep-home-today-plan',
    Ctor: FieldRepHomeTodayPlan,
    label: "Today's Plan"
  },
  {
    bundle: 'c/fieldRepHomeMetrics',
    kind: 'ce',
    tag: 'osr-field-rep-home-metrics',
    Ctor: FieldRepHomeMetrics,
    label: 'Metrics'
  },
  {
    bundle: 'c/fieldRepPlanner',
    kind: 'ce',
    tag: 'osr-field-rep-planner',
    Ctor: FieldRepPlanner,
    label: 'Planner'
  },
  {
    bundle: 'c/visitCallShell',
    kind: 'ce',
    tag: 'osr-visit-call-shell',
    Ctor: VisitCallShell,
    label: 'Visit Call'
  },
  {
    bundle: 'c/visitCallShellLite',
    kind: 'ce',
    tag: 'osr-visit-call-shell-lite',
    Ctor: class VisitCallShellLite extends VisitCallShell {},
    label: 'Visit Call'
  }
];

const byBundle = new Map(ENTRIES.map((e) => [e.bundle, e]));

export function getEngineModule(bundle: string): EngineModuleEntry | undefined {
  const name = bundle.startsWith('c/') ? bundle : `c/${bundle}`;
  return byBundle.get(name);
}

export function listEngineModules(): EngineModuleEntry[] {
  return [...ENTRIES];
}

export function isEngineModule(bundle: string): boolean {
  return !!getEngineModule(bundle);
}

/** Ensure custom elements are defined in the iframe realm. */
export function defineEngineCustomElements(): void {
  for (const e of ENTRIES) {
    if (e.kind === 'ce' && e.tag && !customElements.get(e.tag)) {
      customElements.define(e.tag, e.Ctor as CustomElementConstructor);
    }
  }
}
