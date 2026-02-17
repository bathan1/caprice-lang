import {
	createConnection,
	TextDocuments,
	ProposedFeatures,
	InitializeParams,
	InitializeResult,
	TextDocumentSyncKind
} from 'vscode-languageserver/node';
import { TextDocument } from 'vscode-languageserver-textdocument';
import { spawn } from 'child_process';
import * as path from 'path';

const connection = createConnection(ProposedFeatures.all);
const documents = new TextDocuments(TextDocument);

const typecheckerPath = path.join(__dirname, '..', '..', '..', 'typecheck_lsp.exe');
const ocamlChecker = spawn(typecheckerPath);

ocamlChecker.stdout.on('data', (data) => {
	connection.console.log(`OCaml response: ${data}`);
});

ocamlChecker.stderr.on('data', (data) => {
	connection.console.error(`OCaml error: ${data}`);
});

connection.onInitialize((params: InitializeParams) => {
	const result: InitializeResult = {
		capabilities: {
			textDocumentSync: TextDocumentSyncKind.Full
		}
	};
	return result;
});

documents.onDidChangeContent(change => {
	const text = change.document.getText();

	const len = Buffer.byteLength(text);
	ocamlChecker.stdin.write(len + '\n' + text);	
});

documents.listen(connection);
connection.listen();