# Caprice LSP

A language server for the Caprice language, providing diagnostics in VS
Code.

## Running

#### Build the TypeScript server (once, or after TS changes):

`cd caprice-lsp && npm install && npm run compile`

#### Run in VS Code:

Open any file in `caprice-lsp/server/src/` (e.g. `server.ts`), press
`F5`, and select **VS Code Extension Development**. A new VS Code
window will open with the extension loaded. The LSP activates
automatically on `.caprice` files.