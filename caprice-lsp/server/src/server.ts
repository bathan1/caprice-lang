import {
	createConnection,
	DidChangeTextDocumentParams,
	ProposedFeatures,
	InitializeParams,
	InitializeResult,
	TextDocumentSyncKind
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { TextDocumentContentChangeEvent } from 'vscode-languageserver/node';
import { spawn } from 'child_process';
import * as path from 'path';

import type { CheckerPacket } from './protocol';

const connection = createConnection(ProposedFeatures.all);

const docs = new Map<string, TextDocument>();

const typecheckerPath = path.join(__dirname, '..', '..', '..', 'typecheck_lsp.exe');
const ocamlChecker = spawn(typecheckerPath);

ocamlChecker.stdout.on('data', (data) => {
	connection.console.log(`OCaml response: ${data}`);
});

ocamlChecker.stderr.on('data', (data) => {
	connection.console.error(`OCaml error: ${data}`);
});

function updateDocument(params: DidChangeTextDocumentParams): TextDocument | undefined {
	const doc = docs.get(params.textDocument.uri);
	if (!doc) {
		connection.console.warn(`document not found: ${params.textDocument.uri}`);
		return undefined;
	}

	const updated = TextDocument.update(doc, params.contentChanges, params.textDocument.version);
	docs.set(params.textDocument.uri, updated);
	return updated;
}

function writeFramedMessage(message: CheckerPacket): void {
	const body = JSON.stringify(message);
	const len = Buffer.byteLength(body, 'utf8');
	ocamlChecker.stdin.write(`${len}\n${body}`, 'utf8');
}

connection.onInitialize((params: InitializeParams) => {
	const result: InitializeResult = {
		capabilities: {
			textDocumentSync: TextDocumentSyncKind.Incremental
		}
	};
	return result;
});

function buildDidChangePacket(
	params: DidChangeTextDocumentParams,
	updated: TextDocument
): CheckerPacket {
	const incrementalChanges = params.contentChanges.filter(
		TextDocumentContentChangeEvent.isIncremental
	);

	if (incrementalChanges.length !== params.contentChanges.length) {
		throw new Error(
			`Expected incremental changes for ${params.textDocument.uri}@${params.textDocument.version}`
		);
	}

	const changes = incrementalChanges.map((change) => change.range);

	return {
		uri: params.textDocument.uri,
		version: params.textDocument.version,
		changes,
		fullText: updated.getText()
	};
}

connection.onDidOpenTextDocument(({ textDocument }) => {
	const doc = TextDocument.create(
		textDocument.uri,
		textDocument.languageId,
		textDocument.version,
		textDocument.text
	);
	docs.set(textDocument.uri, doc);
});

connection.onDidChangeTextDocument((params) => {
	const updated = updateDocument(params);
	if (!updated) return;

	try {
		const packet = buildDidChangePacket(params, updated);
		writeFramedMessage(packet);
	} catch (error) {
		connection.console.error(`protocol_error:${String(error)}`);
	}
});

connection.onDidCloseTextDocument(({ textDocument }) => {
	docs.delete(textDocument.uri);
});

connection.listen();