import {
  Diagnostic,
  DiagnosticSeverity,
  Connection,
} from 'vscode-languageserver/node';
import type { OcamlMessage } from './protocol';

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
  private byStmt = new Map<string, Map<number, Diagnostic>>();

  constructor(private connection: Connection) {}

  private flush(uri: string): void {
    const stmtMap = this.byStmt.get(uri);
    const diagnostics =
      stmtMap === undefined
        ? []
        : Array.from(stmtMap.entries()).map(([, d]) => d);

    this.connection.sendDiagnostics({
      uri,
      diagnostics,
    });
  }

  private shouldIgnore(msg: OcamlMessage): boolean {
    return msg.tag === 'error' && /^Unbound variable:/.test(msg.msg);
  }

  private clearStmt(uri: string, idx: number): void {
    const stmtMap = this.byStmt.get(uri);
    if (stmtMap) {
      stmtMap.delete(idx);
      this.byStmt.set(uri, stmtMap);
    }
    this.flush(uri);
  }

  handle(uri: string, msg: OcamlMessage): void {
    switch (msg.tag) {
      case 'error':
      case 'timeout':
      case 'unknown':
      case 'exhausted_pruned': {
        if (this.shouldIgnore(msg)) {
          this.clearStmt(uri, msg.idx);
          break;
        }

        const severity = toSeverity(msg.tag)!;
        const stmtMap = this.byStmt.get(uri) ?? new Map<number, Diagnostic>();
        stmtMap.set(msg.idx, {
          range: msg.range,
          message: msg.tag === 'error' ? msg.msg : msg.tag,
          severity,
        });
        this.byStmt.set(uri, stmtMap);
        this.flush(uri);
        break;
      }
      
      case 'ok': {
        this.clearStmt(uri, msg.idx);
        break;
      }
    }
  }

  clear(uri: string): void {
    this.byStmt.delete(uri);
    this.flush(uri);
  }
}
