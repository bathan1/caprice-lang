import type { Range } from 'vscode-languageserver-types';

// TypeScript -> OCaml
export type CheckerPacket = {
	uri: string;
	version: number;
	fullText: string;
	changes: Range[];
};

// OCaml -> TypeScript
export type OcamlMessage =
  | { tag: 'ok';               idx: number; range: Range }
  | { tag: 'error';            idx: number; range: Range; msg: string }
  | { tag: 'timeout';          idx: number; range: Range }
  | { tag: 'unknown';          idx: number; range: Range }
  | { tag: 'exhausted_pruned'; idx: number; range: Range }
  | { tag: 'done' }
  | { tag: 'parse_error';      line: number; col: number; tok: string }

function parseIndexed(parts: string[]) {
  return {
    idx: +parts[1],
    range: {
      start: { line: +parts[2], character: +parts[3] },
      end:   { line: +parts[4], character: +parts[5] },
    } satisfies Range,
  };
}

export function parseLine(line: string): OcamlMessage | null {
  const parts = line.split(':');
  switch (parts[0]) {
    case 'ok': return { tag: 'ok', ...parseIndexed(parts) };
    case 'error': return { tag: 'error', ...parseIndexed(parts), msg: parts.slice(6).join(':') };
    case 'parse_error': return { tag: 'parse_error', line: +parts[1], col: +parts[2], tok: parts[3] };
    case 'timeout': return { tag: 'timeout', ...parseIndexed(parts) };
    case 'unknown': return { tag: 'unknown', ...parseIndexed(parts) };
    case 'exhausted_pruned': return { tag: 'exhausted_pruned', ...parseIndexed(parts) };
    case 'done': return { tag: 'done' };
    default: return null;
  }
}
