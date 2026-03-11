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
  private pendingParseError: { idx: number; diagnostic: Diagnostic; timer: NodeJS.Timeout } | null = null;
  private inFlight = new Map<number, { range: Range; timer: NodeJS.Timeout }>();

  constructor(private connection: Connection) {}

  private flush(uri: string): void {
    this.connection.sendDiagnostics({
      uri,
      diagnostics: Array.from(this.byStmt.values()),
    });
  }

  private commitPending(uri: string): void {
    if (!this.pendingParseError) return;
    const { idx, diagnostic } = this.pendingParseError;
    this.pendingParseError = null;
    this.byStmt.set(idx, diagnostic);
    this.flush(uri);
  }

  private invalidate(idx: number): void {
    this.byStmt.delete(idx);
    const entry = this.inFlight.get(idx);
    if (entry !== undefined) { clearTimeout(entry.timer); this.inFlight.delete(idx); }
    if (this.pendingParseError !== null && this.pendingParseError.idx >= idx) {
      clearTimeout(this.pendingParseError.timer);
      this.pendingParseError = null;
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
        if (this.pendingParseError !== null) {
          clearTimeout(this.pendingParseError.timer);
          this.commitPending(uri);
        }
        if (this.byStmt.delete(Number.MAX_SAFE_INTEGER)) {
          this.flush(uri);
        }
        this.pendingParseError = {
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

  cancelPendingTimers(uri: string): void {
    if (this.pendingParseError !== null) {
      clearTimeout(this.pendingParseError.timer);
      this.pendingParseError = null;
    }
    for (const [idx, { range, timer }] of this.inFlight) {
      clearTimeout(timer);
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
}
