# Sankhya Repo Updater

Atualiza os repositorios Sankhya sozinho toda vez que voce abre o VS Code — sem depender de
horario fixo do Agendador de Tarefas do Windows. Se a VPN estiver desconectada, opcionalmente
conecta sozinha (FortiClient).

## O que faz

- Roda automaticamente ao abrir o VS Code (alguns segundos depois, pra nao competir com a
  inicializacao).
- Para cada repositorio configurado: `git fetch` e, se houver commits novos, `git pull --ff-only`
  (so avanca em fast-forward - nunca forca merge).
- Se o repositorio tiver alteracoes locais nao commitadas, guarda em `git stash` antes de
  atualizar (configuravel).
- Mostra o resultado como notificacao nativa do VS Code, com um item na barra de status
  clicavel pra rodar na hora.
- Log detalhado de cada execucao no canal de saida "Sankhya Repo Updater".

## Primeiros passos

1. Instale a extensao (`.vsix`).
2. Rode o comando **Sankhya: Descobrir Repositorios** (Ctrl+Shift+P) - ele varre o disco
   procurando repositorios git cujo remoto aponte para `gitlab.sankhya.com.br` e configura
   sozinho.
3. Pronto. Da proxima vez que abrir o VS Code, ele verifica sozinho.

## Comandos

- **Sankhya: Atualizar Agora** - roda a verificacao na hora.
- **Sankhya: Descobrir Repositorios** - varre o disco de novo e atualiza a lista configurada.
- **Sankhya: Ver Log** - abre o canal de saida com o historico detalhado.

## Configuracoes

Acessiveis em Configuracoes (Ctrl+,) buscando por "Sankhya":

| Configuracao | Padrao | Descricao |
|---|---|---|
| `sankhyaUpdater.gitHost` | `gitlab.sankhya.com.br` | Host usado pra testar VPN e descobrir repositorios |
| `sankhyaUpdater.repoPaths` | `[]` | Caminhos completos dos repositorios (preenchido por "Descobrir Repositorios") |
| `sankhyaUpdater.discardMode` | `stash` | O que fazer com alteracoes nao commitadas: `stash` (reversivel) ou `hard` (apaga pra sempre) |
| `sankhyaUpdater.vpnAutoConnect` | `false` | Tentar conectar a VPN sozinho quando desconectada |
| `sankhyaUpdater.updateOnStartup` | `true` | Rodar automaticamente ao abrir o VS Code |

## VPN automatica (`vpnAutoConnect`)

Quando ligado, clica sozinho em "Conectar" na janela do FortiClient (perfil ja configurado no
Windows) e seleciona a conta `@sankhya.com.br` se aparecer a tela de escolha de conta do
Google. So funciona se:

- O **FortiClient estiver fixado na barra de tarefas** do Windows (clique direito no icone →
  "Fixar na barra de tarefas", 1x so).
- A sessao SSO ja estiver autenticada no navegador (mesmo fluxo sem senha que voce ja usa).

Se algum dos dois nao se aplicar, a extensao so avisa que a VPN esta desconectada — nao quebra
nada.

**Limitacao conhecida:** o clique automatico so funciona de forma confiavel quando a janela do
FortiClient ja esta aberta (ex: voce mesmo abriu ela antes). Abrir a janela do zero (quando o
FortiClient esta rodando so na bandeja, sem nenhuma janela aberta) depende de um clique
sintetico no icone fixado na barra de tarefas que o proprio FortiClient parece rejeitar quando
nao vem de um clique real do mouse - diferente de outros apps (testado com Chrome, que aceita
normalmente). Se isso for corrigido no futuro, so precisa atualizar o script empacotado
(`resources/Update-Sankhya.ps1`) e gerar uma nova versao - a configuracao e o resto da extensao
ja estao prontos pra isso.

## Seguranca: `discardMode`

- **`stash`** (padrao, recomendado): `git stash push -u` antes de atualizar. Reversivel —
  recupere com `git stash pop`.
- **`hard`**: `git reset --hard` + `git clean -fd`. Apaga qualquer alteracao nao commitada **para
  sempre**. So use se tiver certeza de nunca deixar trabalho sem commit nesses repositorios.
