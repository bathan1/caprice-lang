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
  private byStmt = new Map<number, Diagnostic>();

  constructor(private connection: Connection) {}

  private flush(uri: string): void {
    this.connection.sendDiagnostics({
      uri,
      diagnostics: Array.from(this.byStmt.values()),
    });
  }

  private invalidateFrom(idx: number): void {
    for (const key of this.byStmt.keys()) {
      if (key >= idx) this.byStmt.delete(key);
    }
  }

  handle(uri: string, msg: OcamlMessage): void {
    switch (msg.tag) {
      case 'error':
      case 'timeout':
      case 'unknown':
      case 'exhausted_pruned': {
        this.invalidateFrom(msg.idx);
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
        this.invalidateFrom(msg.idx);
        this.flush(uri);
        break;
      }
    }
  }

  clear(): void {
    this.byStmt.clear();
  }
}
