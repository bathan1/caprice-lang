import {
  Diagnostic,
  DiagnosticSeverity,
  Connection,
} from 'vscode-languageserver/node';
import type { OcamlMessage } from './protocol';

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
  private pendingTimers = new Map<number, NodeJS.Timeout>();

  constructor(private connection: Connection) {}

  private flush(uri: string): void {
    this.connection.sendDiagnostics({
      uri,
      diagnostics: Array.from(this.byStmt.values()),
    });
  }

  private commitPending(uri: string): void {
    if (this.pending === null) return;
    const { idx, diagnostic } = this.pending;
    this.pending = null;
    this.byStmt.set(idx, diagnostic);
    this.flush(uri);
  }

  private invalidate(idx: number): void {
    this.byStmt.delete(idx);
    if (this.pending !== null && this.pending.idx >= idx) {
      clearTimeout(this.pending.timer);
      this.pending = null;
    }
    const t = this.pendingTimers.get(idx);
    if (t !== undefined) {
      clearTimeout(t);
      this.pendingTimers.delete(idx);
    }
  }

  handle(uri: string, msg: OcamlMessage): void {
    switch (msg.tag) {
      case 'pending': {
        const existing = this.pendingTimers.get(msg.idx);
        if (existing !== undefined) clearTimeout(existing);
        this.pendingTimers.set(msg.idx, setTimeout(() => {
          this.pendingTimers.delete(msg.idx);
          this.byStmt.set(msg.idx, {
            range: msg.range,
            message: 'checking...',
            severity: DiagnosticSeverity.Warning,
          });
          this.flush(uri);
        }, 250));
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

  clear(): void {
    if (this.pending !== null) {
      clearTimeout(this.pending.timer);
      this.pending = null;
    }
    for (const t of this.pendingTimers.values()) clearTimeout(t);
    this.pendingTimers.clear();
    this.byStmt.clear();
  }
}
