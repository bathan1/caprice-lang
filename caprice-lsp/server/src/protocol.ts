import type { Range } from 'vscode-languageserver-types';

export type CheckerPacket = {
	uri: string;
	version: number;
	fullText: string;
	changes: Range[];
};
