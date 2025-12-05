import * as path from 'path';
import * as vscode from 'vscode';
import {
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  TransportKind,
} from 'vscode-languageclient/node';

let client: LanguageClient | undefined;

export function activate(context: vscode.ExtensionContext) {
  const config = vscode.workspace.getConfiguration('gene');
  const lspEnabled = config.get<boolean>('lsp.enabled', true);
  const trace = config.get<boolean>('lsp.trace', false);

  console.log('Gene Language Support extension is now active');

  if (!lspEnabled) {
    console.log('Gene LSP is disabled via configuration');
    return;
  }

  // Find the gene executable
  const geneCommand = findGeneExecutable();
  if (!geneCommand) {
    vscode.window.showWarningMessage(
      'Gene executable not found. LSP features will be disabled. ' +
      'Make sure "gene" is in your PATH or build it with "nimble build".'
    );
    return;
  }

  // Server options - run gene lsp --stdio
  const serverOptions: ServerOptions = {
    command: geneCommand,
    args: ['lsp', '--stdio'],
    transport: TransportKind.stdio,
    options: {
      env: {
        ...process.env,
        GENE_LSP_TRACE: trace ? '1' : '0',
      },
    },
  };

  // Client options
  const clientOptions: LanguageClientOptions = {
    documentSelector: [{ scheme: 'file', language: 'gene' }],
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher('**/*.gene'),
    },
    outputChannelName: 'Gene Language Server',
  };

  // Create and start the client
  client = new LanguageClient(
    'geneLsp',
    'Gene Language Server',
    serverOptions,
    clientOptions
  );

  // Start the client (also launches the server)
  client.start().then(() => {
    console.log('Gene Language Server started successfully');
  }).catch((error) => {
    console.error('Failed to start Gene Language Server:', error);
    vscode.window.showErrorMessage(
      `Failed to start Gene Language Server: ${error.message}`
    );
  });

  // Register the client for disposal
  context.subscriptions.push({
    dispose: () => {
      if (client) {
        client.stop();
      }
    },
  });

  // Register commands
  context.subscriptions.push(
    vscode.commands.registerCommand('gene.restartServer', async () => {
      if (client) {
        await client.stop();
        await client.start();
        vscode.window.showInformationMessage('Gene Language Server restarted');
      }
    })
  );
}

export function deactivate(): Thenable<void> | undefined {
  if (!client) {
    return undefined;
  }
  return client.stop();
}

function findGeneExecutable(): string | undefined {
  // Check common locations
  const possiblePaths = [
    // Relative to workspace (for development)
    path.join(vscode.workspace.workspaceFolders?.[0]?.uri.fsPath || '', 'bin', 'gene'),
    // System PATH
    'gene',
  ];

  // For now, just return 'gene' and let the system find it
  // In production, you might want to check if the file exists
  return 'gene';
}

