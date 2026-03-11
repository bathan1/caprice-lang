import {
  Diagnostic,
  DiagnosticSeverity,
  Connection,
} from 'vscode-languageserver/node';
import type { OcamlMessage } from './protocol';
import type { Range } from 'vscode-languageserver-types';

function parseErrorDiagnostic(msg: Extract<OcamlMessage, { tag: 'parse_error' }>): Diagnostic {
  const [start, end] = msg.tok.length > 0
    ? [msg.col - msg.tok.length, msg.col]
    : [msg.col, msg.col + 1];
  return {
    range: {
      start: { line: msg.line - 1, character: start },
      end:   { line: msg.line - 1, character: end },
    },
    message: msg.tok.length > 0 ? `Parse error: unexpected '${msg.tok}'` : 'Parse error',
    severity: DiagnosticSeverity.Error,
  };
}

function toSeverity(tag: OcamlMessage['tag']): DiagnosticSeverity | null {
  switch (tag) {
    case 'error':               return DiagnosticSeverity.Error;
    case 'timeout':
    case 'unknown':
    case 'exhausted_pruned':    return DiagnosticSeverity.Warning;
    default:                    return null;
  }
}

export class DiagnosticsManager {
  private byStmt = new Map<number, Diagnostic>();
  private pending: { idx: number; diagnostic: Diagnostic; timer: NodeJS.Timeout } | null = null;
  private inFlight = new Map<number, { range: Range; timer: NodeJS.Timeout }>();

  constructor(private connection: Connection) {}

  private flush(uri: string): void {
    this.connection.sendDiagnostics({
      uri,
      diagnostics: Array.from(this.byStmt.values()),
    });
  }

  private commitPending(uri: string): void {
    if (!this.pending) return;
    const { idx, diagnostic } = this.pending;
    this.pending = null;
    this.byStmt.set(idx, diagnostic);
    this.flush(uri);
  }

  private invalidate(idx: number): void {
    this.byStmt.delete(idx);
    const entry = this.inFlight.get(idx);
    if (entry !== undefined) { clearTimeout(entry.timer); this.inFlight.delete(idx); }
    if (this.pending !== null && this.pending.idx >= idx) {
      clearTimeout(this.pending.timer);
      this.pending = null;
    }
  }

  handle(uri: string, msg: OcamlMessage): void {
    switch (msg.tag) {
      case 'pending': {
        const existing = this.inFlight.get(msg.idx);
        if (existing !== undefined) clearTimeout(existing.timer);
        this.inFlight.set(msg.idx, {
          range: msg.range,
          timer: setTimeout(() => {
            this.byStmt.set(msg.idx, {
              range: msg.range,
              message: 'checking...',
              severity: DiagnosticSeverity.Warning,
            });
            this.flush(uri);
          }, 250),
        });
        break;
      }
      case 'parse_error': {
        const diagnostic = parseErrorDiagnostic(msg);
        if (this.pending !== null) {
          clearTimeout(this.pending.timer);
          this.commitPending(uri);
        }
        if (this.byStmt.delete(Number.MAX_SAFE_INTEGER)) {
          this.flush(uri);
        }
        this.pending = {
          idx: Number.MAX_SAFE_INTEGER, diagnostic,
          timer: setTimeout(() => { this.commitPending(uri); }, 1000),
        };
        break;
      }

      case 'error':
      case 'timeout':
      case 'unknown':
      case 'exhausted_pruned': {
        this.invalidate(msg.idx);
        const severity = toSeverity(msg.tag)!;
        const diagnostic: Diagnostic = {
          range: msg.range,
          message: msg.tag === 'error' ? msg.msg : msg.tag,
          severity,
        };

        if (msg.tag === 'error' && msg.msg.includes('Unbound variable')) {
          for (const key of this.byStmt.keys()) {
            if (key >= msg.idx) this.byStmt.delete(key);
          }
        }
        this.byStmt.set(msg.idx, diagnostic);
        this.flush(uri);
        break;
      }

      case 'ok': {
        this.invalidate(msg.idx);
        this.flush(uri);
        break;
      }
    }
  }

  private cancelTimers(): void {
    if (this.pending !== null) { clearTimeout(this.pending.timer); this.pending = null; }
    for (const { timer } of this.inFlight.values()) clearTimeout(timer);
  }

  cancelPendingTimers(uri: string): void {
    this.cancelTimers();
    for (const [idx, { range }] of this.inFlight) {
      this.byStmt.set(idx, {
        range,
        message: 'timeout',
        severity: DiagnosticSeverity.Warning,
      });
    }
    this.inFlight.clear();
    this.flush(uri);
  }

  resetForNewDoc(): void {
    this.byStmt.clear();
  }

  clear(): void {
    this.cancelTimers();
  }
}
