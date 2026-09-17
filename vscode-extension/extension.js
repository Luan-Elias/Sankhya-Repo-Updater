// Extensao VS Code do Sankhya Repo Updater.
// JavaScript puro (CommonJS), sem etapa de build - o VS Code carrega este
// arquivo diretamente com o Node.js que ja vem embutido nele. Nao precisa de
// Node.js/npm instalado na maquina pra rodar (so pra quem for editar o codigo
// com ferramentas de desenvolvedor, o que nao e o caso aqui).

const vscode = require("vscode");
const path = require("path");
const { execFile } = require("child_process");

let statusBarItem;
let outputChannel;

function activate(context) {
  outputChannel = vscode.window.createOutputChannel("Sankhya Repo Updater");
  context.subscriptions.push(outputChannel);

  statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
  statusBarItem.command = "sankhyaUpdater.updateNow";
  statusBarItem.text = "$(sync) Sankhya";
  statusBarItem.tooltip = "Sankhya Repo Updater — clique para atualizar agora";
  statusBarItem.show();
  context.subscriptions.push(statusBarItem);

  context.subscriptions.push(
    vscode.commands.registerCommand("sankhyaUpdater.updateNow", () => runUpdate(true)),
    vscode.commands.registerCommand("sankhyaUpdater.discoverRepos", discoverRepos),
    vscode.commands.registerCommand("sankhyaUpdater.showLog", () => outputChannel.show())
  );

  const config = vscode.workspace.getConfiguration("sankhyaUpdater");
  if (config.get("updateOnStartup", true)) {
    // pequeno atraso pra nao competir com o resto da inicializacao do VS Code
    setTimeout(() => runUpdate(false), 4000);
  }
}

function deactivate() {}

function getScriptPath(context) {
  return path.join(context.extensionPath, "resources", "Update-Sankhya.ps1");
}

function runPowerShell(context, args) {
  return new Promise((resolve, reject) => {
    const scriptPath = getScriptPath(context);
    const fullArgs = [
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", scriptPath,
      ...args
    ];
    outputChannel.appendLine(`> powershell ${fullArgs.join(" ")}`);
    execFile(
      "powershell.exe",
      fullArgs,
      { maxBuffer: 10 * 1024 * 1024, windowsHide: true },
      (err, stdout, stderr) => {
        if (stderr && stderr.trim()) {
          outputChannel.appendLine(stderr.trim());
        }
        if (err && !stdout) {
          reject(err);
          return;
        }
        try {
          // o script so imprime UM objeto JSON de verdade; usa a ultima linha
          // nao-vazia como salvaguarda caso algo mais tenha vazado pro stdout.
          const lines = stdout.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
          const jsonText = lines.length ? lines[lines.length - 1] : stdout;
          resolve(JSON.parse(jsonText));
        } catch (parseErr) {
          outputChannel.appendLine("Falha ao interpretar a saida do script:");
          outputChannel.appendLine(stdout);
          reject(parseErr);
        }
      }
    );
  });
}

async function discoverRepos() {
  const context = global.__sankhyaExtensionContext;
  const config = vscode.workspace.getConfiguration("sankhyaUpdater");
  const gitHost = config.get("gitHost", "gitlab.sankhya.com.br");

  vscode.window.withProgress(
    { location: vscode.ProgressLocation.Notification, title: "Sankhya: procurando repositorios..." },
    async () => {
      try {
        const result = await runPowerShell(context, ["-Mode", "discover", "-GitHost", gitHost]);
        if (!result.ok) {
          vscode.window.showErrorMessage(`Sankhya: falha ao descobrir repositorios - ${result.error || "erro desconhecido"}`);
          return;
        }
        if (!result.repoPaths || result.repoPaths.length === 0) {
          vscode.window.showWarningMessage("Sankhya: nenhum repositorio encontrado. Confirme que ja foram clonados (git clone).");
          return;
        }
        await config.update("repoPaths", result.repoPaths, vscode.ConfigurationTarget.Global);
        vscode.window.showInformationMessage(
          `Sankhya: ${result.repoPaths.length} repositorio(s) configurado(s): ${result.repoNames.join(", ")}`
        );
      } catch (e) {
        vscode.window.showErrorMessage(`Sankhya: erro ao descobrir repositorios - ${e.message}`);
        outputChannel.appendLine(String(e.stack || e));
      }
    }
  );
}

async function runUpdate(interactive) {
  const context = global.__sankhyaExtensionContext;
  const config = vscode.workspace.getConfiguration("sankhyaUpdater");
  const gitHost = config.get("gitHost", "gitlab.sankhya.com.br");
  const repoPaths = config.get("repoPaths", []);
  const discardMode = config.get("discardMode", "stash");
  const vpnAutoConnect = config.get("vpnAutoConnect", false);

  if (!repoPaths || repoPaths.length === 0) {
    statusBarItem.text = "$(warning) Sankhya: sem repositorios";
    if (interactive) {
      const choice = await vscode.window.showWarningMessage(
        "Sankhya: nenhum repositorio configurado ainda.",
        "Descobrir repositorios"
      );
      if (choice) discoverRepos();
    }
    return;
  }

  statusBarItem.text = "$(sync~spin) Sankhya: verificando...";

  const args = [
    "-Mode", "update",
    "-GitHost", gitHost,
    "-RepoPaths", ...repoPaths,
    "-DiscardMode", discardMode
  ];
  if (vpnAutoConnect) args.push("-VpnAutoConnect");

  try {
    const result = await runPowerShell(context, args);
    outputChannel.appendLine(`=== ${new Date().toLocaleString("pt-BR")} ===`);
    outputChannel.appendLine(JSON.stringify(result, null, 2));

    if (result.vpnDown) {
      statusBarItem.text = "$(circle-slash) Sankhya: VPN desconectada";
      const msg = vpnAutoConnect
        ? "Sankhya: tentei conectar a VPN sozinho, mas nao consegui. Conecte manualmente e rode 'Sankhya: Atualizar Agora'."
        : "Sankhya: VPN desconectada. Conecte e rode 'Sankhya: Atualizar Agora'.";
      vscode.window.showWarningMessage(msg);
      return;
    }

    const parts = [];
    if (result.vpnAutoConnected) parts.push("VPN conectada automaticamente");
    if (result.updated && result.updated.length) parts.push(`Atualizados: ${result.updated.join("; ")}`);
    if (result.discardedLocal && result.discardedLocal.length) parts.push(`Descartado: ${result.discardedLocal.join("; ")}`);
    if (result.stashedLocal && result.stashedLocal.length) parts.push(`Guardado em stash: ${result.stashedLocal.length} repositorio(s)`);
    if (result.errors && result.errors.length) parts.push(`Erros: ${result.errors.join("; ")}`);

    if (result.errors && result.errors.length) {
      statusBarItem.text = "$(error) Sankhya: erro";
      vscode.window.showErrorMessage(`Sankhya: ${result.errors.join(" | ")}`);
    } else if (result.updated && result.updated.length) {
      statusBarItem.text = "$(check) Sankhya: atualizado";
      vscode.window.showInformationMessage(`Sankhya: ${result.updated.join(" | ")}`);
    } else {
      statusBarItem.text = "$(check) Sankhya: em dia";
      if (interactive) vscode.window.showInformationMessage("Sankhya: tudo em dia, nenhuma novidade.");
    }
    statusBarItem.tooltip = parts.length ? parts.join("\n") : "Tudo em dia";
  } catch (e) {
    statusBarItem.text = "$(error) Sankhya: falhou";
    outputChannel.appendLine(String(e.stack || e));
    if (interactive) {
      vscode.window.showErrorMessage(`Sankhya: erro ao verificar - ${e.message}`);
    }
  }
}

module.exports = {
  activate: (context) => {
    global.__sankhyaExtensionContext = context;
    activate(context);
  },
  deactivate
};
