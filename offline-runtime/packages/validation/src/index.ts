/** Salesforce formula subset + validation rule engine */
export { FORMULA_MATRIX } from './formula-matrix.js';
import { FORMULA_MATRIX } from './formula-matrix.js';

export type RecordValues = Record<string, unknown>;

export interface ValidationRuleDef {
  id: string;
  name: string;
  errorCondition: string;
  errorMessage: string;
  errorDisplayField?: string | null;
}

export interface ValidationResult {
  ok: boolean;
  errors: { ruleId: string; ruleName: string; message: string; field?: string | null }[];
  warnings: string[];
}

export interface RequiredFieldCheck {
  apiName: string;
  label: string;
  required: boolean;
}

function isBlank(v: unknown): boolean {
  return v === null || v === undefined || v === '';
}

/** Very small recursive-descent formula evaluator for offline VR */
export class FormulaEvaluator {
  private i = 0;
  private src = '';
  private record: RecordValues = {};
  private warnings: string[] = [];

  evaluate(formula: string, record: RecordValues): { value: unknown; warnings: string[] } {
    this.src = formula.trim();
    this.i = 0;
    this.record = record;
    this.warnings = [];
    if (!this.src) return { value: false, warnings: [] };
    const value = this.parseOr();
    this.skipWs();
    if (this.i < this.src.length) {
      this.warnings.push(`Trailing formula content at ${this.i}`);
    }
    return { value, warnings: this.warnings };
  }

  private peek(): string {
    return this.src[this.i] ?? '';
  }

  private skipWs(): void {
    while (/\s/.test(this.peek())) this.i++;
  }

  private match(re: RegExp): string | null {
    this.skipWs();
    const m = this.src.slice(this.i).match(re);
    if (!m) return null;
    this.i += m[0].length;
    return m[0];
  }

  private expect(ch: string): void {
    this.skipWs();
    if (this.src.slice(this.i, this.i + ch.length) !== ch) {
      throw new Error(`Expected '${ch}' at ${this.i}`);
    }
    this.i += ch.length;
  }

  private parseOr(): unknown {
    let left = this.parseAnd();
    while (true) {
      this.skipWs();
      if (this.match(/^(\|\||OR\b)/i)) {
        const right = this.parseAnd();
        left = Boolean(left) || Boolean(right);
      } else break;
    }
    return left;
  }

  private parseAnd(): unknown {
    let left = this.parseNot();
    while (true) {
      this.skipWs();
      if (this.match(/^(&&|AND\b)/i)) {
        const right = this.parseNot();
        left = Boolean(left) && Boolean(right);
      } else break;
    }
    return left;
  }

  private parseNot(): unknown {
    this.skipWs();
    if (this.match(/^(NOT\b|!)/i)) {
      return !this.parseNot();
    }
    return this.parseComparison();
  }

  private parseComparison(): unknown {
    let left = this.parseAdd();
    this.skipWs();
    const op = this.match(/^(<>|!=|==|=|>=|<=|>|<)/);
    if (!op) return left;
    const right = this.parseAdd();
    const normalized = op === '=' ? '==' : op === '<>' ? '!=' : op;
    switch (normalized) {
      case '==':
        return String(left ?? '') === String(right ?? '');
      case '!=':
        return String(left ?? '') !== String(right ?? '');
      case '>':
        return Number(left) > Number(right);
      case '>=':
        return Number(left) >= Number(right);
      case '<':
        return Number(left) < Number(right);
      case '<=':
        return Number(left) <= Number(right);
      default:
        return false;
    }
  }

  private parseAdd(): unknown {
    let left = this.parseMul();
    while (true) {
      this.skipWs();
      if (this.match(/^\+/)) {
        const right = this.parseMul();
        if (typeof left === 'string' || typeof right === 'string') {
          left = String(left ?? '') + String(right ?? '');
        } else {
          left = Number(left) + Number(right);
        }
      } else if (this.match(/^&/)) {
        left = String(left ?? '') + String(this.parseMul() ?? '');
      } else if (this.match(/^-/)) {
        left = Number(left) - Number(this.parseMul());
      } else break;
    }
    return left;
  }

  private parseMul(): unknown {
    let left = this.parsePrimary();
    while (true) {
      this.skipWs();
      if (this.match(/^\*/)) left = Number(left) * Number(this.parsePrimary());
      else if (this.match(/^\//)) left = Number(left) / Number(this.parsePrimary());
      else break;
    }
    return left;
  }

  private parsePrimary(): unknown {
    this.skipWs();
    if (this.peek() === '(') {
      this.expect('(');
      const v = this.parseOr();
      this.expect(')');
      return v;
    }
    if (this.peek() === "'") {
      this.i++;
      let s = '';
      while (this.i < this.src.length && this.src[this.i] !== "'") {
        s += this.src[this.i++];
      }
      this.expect("'");
      return s;
    }
    if (this.peek() === '"') {
      this.i++;
      let s = '';
      while (this.i < this.src.length && this.src[this.i] !== '"') {
        s += this.src[this.i++];
      }
      this.expect('"');
      return s;
    }
    const num = this.match(/^-?\d+(\.\d+)?/);
    if (num) return Number(num);

    const ident = this.match(/^[A-Za-z_][A-Za-z0-9_.]*/);
    if (!ident) throw new Error(`Unexpected token at ${this.i}`);

    const upper = ident.toUpperCase();
    if (upper === 'TRUE') return true;
    if (upper === 'FALSE') return false;
    if (upper === 'NULL') return null;

    this.skipWs();
    if (this.peek() === '(') {
      return this.callFn(upper);
    }

    // Field reference — allow Account.Name style → last segment or full
    if (ident.includes('.')) {
      const parts = ident.split('.');
      // Prefer local field if present, else nested path
      if (ident in this.record) return this.record[ident];
      let cur: unknown = this.record;
      for (const p of parts) {
        if (cur && typeof cur === 'object' && p in (cur as object)) {
          cur = (cur as Record<string, unknown>)[p];
        } else {
          return this.record[parts[parts.length - 1]] ?? null;
        }
      }
      return cur;
    }
    return this.record[ident] ?? null;
  }

  private callFn(name: string): unknown {
    this.expect('(');
    const args: unknown[] = [];
    this.skipWs();
    if (this.peek() !== ')') {
      args.push(this.parseOr());
      while (true) {
        this.skipWs();
        if (this.peek() === ',') {
          this.expect(',');
          args.push(this.parseOr());
        } else break;
      }
    }
    this.expect(')');

    if (FORMULA_MATRIX.unsupported.includes(name as (typeof FORMULA_MATRIX.unsupported)[number])) {
      this.warnings.push(`Unsupported function ${name}`);
      if (FORMULA_MATRIX.policy.onUnsupported === 'block') {
        throw new Error(`Unsupported formula function: ${name}`);
      }
      return false;
    }

    switch (name) {
      case 'AND':
        return args.every(Boolean);
      case 'OR':
        return args.some(Boolean);
      case 'NOT':
        return !args[0];
      case 'IF':
        return args[0] ? args[1] : args[2];
      case 'ISBLANK':
      case 'ISNULL':
        return isBlank(args[0]);
      case 'ISPICKVAL':
        return String(args[0] ?? '') === String(args[1] ?? '');
      case 'TEXT':
        return String(args[0] ?? '');
      case 'VALUE':
        return Number(args[0]);
      case 'LEN':
        return String(args[0] ?? '').length;
      case 'LEFT':
        return String(args[0] ?? '').slice(0, Number(args[1]));
      case 'RIGHT': {
        const s = String(args[0] ?? '');
        const n = Number(args[1]);
        return s.slice(Math.max(0, s.length - n));
      }
      case 'CONTAINS':
        return String(args[0] ?? '').includes(String(args[1] ?? ''));
      case 'BEGINS':
        return String(args[0] ?? '').startsWith(String(args[1] ?? ''));
      case 'UPPER':
        return String(args[0] ?? '').toUpperCase();
      case 'LOWER':
        return String(args[0] ?? '').toLowerCase();
      case 'TRIM':
        return String(args[0] ?? '').trim();
      default:
        this.warnings.push(`Unknown function ${name}`);
        throw new Error(`Unknown formula function: ${name}`);
    }
  }
}

export function evaluateValidationRules(
  rules: ValidationRuleDef[],
  record: RecordValues,
  options?: { onUnsupported?: 'block' | 'warn-allow' }
): ValidationResult {
  const errors: ValidationResult['errors'] = [];
  const warnings: string[] = [];
  const prevPolicy = FORMULA_MATRIX.policy.onUnsupported;
  if (options?.onUnsupported) {
    (FORMULA_MATRIX.policy as { onUnsupported: 'block' | 'warn-allow' }).onUnsupported =
      options.onUnsupported;
  }

  try {
    const ev = new FormulaEvaluator();
    for (const rule of rules) {
      try {
        const { value, warnings: w } = ev.evaluate(rule.errorCondition, record);
        warnings.push(...w.map((x) => `${rule.name}: ${x}`));
        // Salesforce VR fires when errorCondition is TRUE
        if (value === true) {
          errors.push({
            ruleId: rule.id,
            ruleName: rule.name,
            message: rule.errorMessage,
            field: rule.errorDisplayField
          });
        }
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        warnings.push(`${rule.name}: ${msg}`);
        if (FORMULA_MATRIX.policy.onUnsupported === 'block') {
          errors.push({
            ruleId: rule.id,
            ruleName: rule.name,
            message: `Offline validation could not evaluate rule: ${msg}`,
            field: rule.errorDisplayField
          });
        }
      }
    }
  } finally {
    (FORMULA_MATRIX.policy as { onUnsupported: 'block' | 'warn-allow' }).onUnsupported = prevPolicy;
  }

  return { ok: errors.length === 0, errors, warnings };
}

export function checkRequiredFields(
  fields: RequiredFieldCheck[],
  record: RecordValues
): ValidationResult {
  const errors: ValidationResult['errors'] = [];
  for (const f of fields) {
    if (f.required && isBlank(record[f.apiName])) {
      errors.push({
        ruleId: `required:${f.apiName}`,
        ruleName: 'Required',
        message: `${f.label} is required`,
        field: f.apiName
      });
    }
  }
  return { ok: errors.length === 0, errors, warnings: [] };
}

export function validateRecord(
  record: RecordValues,
  rules: ValidationRuleDef[],
  requiredFields: RequiredFieldCheck[] = []
): ValidationResult {
  const req = checkRequiredFields(requiredFields, record);
  const vr = evaluateValidationRules(rules, record);
  return {
    ok: req.ok && vr.ok,
    errors: [...req.errors, ...vr.errors],
    warnings: [...req.warnings, ...vr.warnings]
  };
}
