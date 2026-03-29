import * as path from 'path';
import { ExtensionContext, StatusBarAlignment, StatusBarItem, commands, window } from 'vscode';
import {
	LanguageClient,
	LanguageClientOptions,
	ServerOptions,
	TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient;
let statusBar: StatusBarItem;
let enabled = true;

function updateStatusBar() {
	statusBar.text = enabled ? '$(check) Caprice Typecheck' : '$(circle-slash) Caprice Typecheck';
	statusBar.tooltip = enabled
		? 'Type checking ON — click to disable'
		: 'Type checking OFF — click to enable';
}

export function activate(context: ExtensionContext) {
	const serverModule = context.asAbsolutePath(
		path.join('server', 'out', 'server.js')
	);

	const serverOptions: ServerOptions = {
		run: { module: serverModule, transport: TransportKind.ipc },
		debug: { module: serverModule, transport: TransportKind.ipc }
	};

	const clientOptions: LanguageClientOptions = {
		documentSelector: [{ scheme: 'file', language: 'caprice' }]
	};

	client = new LanguageClient(
		'CapricelanguageServer',
		'Caprice Language Server',
		serverOptions,
		clientOptions
	);

	client.start();

	statusBar = window.createStatusBarItem(StatusBarAlignment.Right, 100);
	statusBar.command = 'caprice.toggleTypechecking';
	updateStatusBar();
	statusBar.show();

	const toggle = commands.registerCommand('caprice.toggleTypechecking', async () => {
		if (enabled) {
			await client.stop();
		} else {
			await client.start();
		}
		enabled = !enabled;
		updateStatusBar();
	});

	context.subscriptions.push(statusBar, toggle);
}

export function deactivate(): Thenable<void> | undefined {
	if (!client) {
		return undefined;
	}
	return client.stop();
}