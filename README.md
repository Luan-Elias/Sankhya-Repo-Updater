# Sankhya Repo Updater

Verifica diariamente se ha versoes novas nos repositorios git configurados e atualiza
automaticamente (`git pull --ff-only`), sem precisar pedir manualmente toda vez.

Todos os arquivos executaveis deste pacote sao `.bat` - de 2 cliques em qualquer um deles e
roda direto, sem abrir editor de texto nem pedir configuracao de PowerShell.

## O que isso faz

- 1x por dia (horario configuravel), roda em segundo plano via Tarefa Agendada do Windows:
  - Testa se consegue alcancar o host git (detecta VPN desconectada antes de tentar qualquer coisa)
  - Para cada repositorio configurado: `git fetch` e, se houver commits novos no branch atual,
    `git pull --ff-only` (so avanca se for fast-forward - nunca faz merge/rebase automatico)
  - Se o repositorio tiver alteracoes locais nao commitadas, aplica o `discardMode` configurado
    (ver abaixo) antes de atualizar
  - Loga tudo em `.\logs\update-YYYYMM.log` e mostra uma notificacao (balao do Windows) quando
    ha algo novo, erro, ou a VPN esta desconectada
- Um atalho na area de trabalho para rodar a verificacao manualmente a qualquer momento (util
  logo depois de conectar a VPN), com um resumo em uma janela que fica aberta ate voce fechar

## Pre-requisitos

- Windows + PowerShell + git ja instalados
- Os repositorios que voce quer manter atualizados ja clonados (`git clone`) em algum lugar da
  maquina
- Se algum repositorio tiver arquivos com caminho muito longo (ex: pastas de build geradas com
  nomes profundos), habilite suporte a caminhos longos do Windows 1x, em um PowerShell como
  **Administrador**:
  ```powershell
  New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name LongPathsEnabled -Value 1 -PropertyType DWord -Force
  ```
  Sem isso, `git.exe` pode falhar com "Filename too long" ao tentar atualizar esses repositorios
  - o script trata isso como um erro normal (loga e pula aquele repositorio naquele dia), nao
  trava nem corrompe nada.

## Como instalar (automatico - recomendado para quem nao quer editar nada)

1. Extraia esta pasta inteira em qualquer lugar do computador (nao precisa ser dentro da pasta
   dos projetos).
2. De 2 cliques em `Instalar-Automatico.bat`.
   - O script varre os discos fixos do computador procurando pastas com repositorio git cujo
     remoto `origin` aponte para `gitlab.sankhya.com.br`, monta o `config.json` sozinho com o
     que encontrar, e ja instala a tarefa agendada e o atalho.
   - Pode levar 1-2 minutos na primeira vez. Uma janela de console mostra o progresso e, ao
     final, uma caixa de mensagem lista quais repositorios foram encontrados e configurados.
     Aperte qualquer tecla para fechar a janela de console quando terminar.
   - Se os seus repositorios usam outro host git, abra um "Prompt de Comando" nesta pasta e
     rode:
     ```
     Instalar-Automatico.bat -GitHost "seu.git.host"
     ```
   - Se nao encontrar nenhum repositorio, verifique se eles ja foram clonados, ou use a
     instalacao manual abaixo.

## Como instalar (manual - se preferir controlar exatamente quais pastas entram)

1. Extraia esta pasta inteira em qualquer lugar do computador.
2. Edite `config.json` e preencha:
   - `reposRoot`: pasta que contem todos os seus repositorios (ex: `C:\\SK-Code`)
   - `repoNames`: lista dos nomes das pastas dos repositorios (dentro de `reposRoot`)
   - `gitHost`: host do git usado para testar se a VPN/rede esta ok (ex: `gitlab.sankhya.com.br`)
   - `scheduleTime`: horario de execucao diaria (formato `HH:mm`) - escolha um horario em que
     voce normalmente ja esta com a VPN conectada
   - `discardMode`: **veja a secao de seguranca abaixo antes de mudar isso**
   - `vpnAutoConnect`: **veja a secao "VPN automatica" abaixo antes de mudar isso**

   Alternativa: em vez de `reposRoot`/`repoNames`, voce pode preencher `repoPaths` diretamente
   com uma lista de caminhos completos (util se os repositorios estao espalhados em lugares
   diferentes). Se `repoPaths` tiver algo, ele tem prioridade sobre `reposRoot`/`repoNames`.
3. De 2 cliques em `install.bat`. Isso cria a tarefa agendada e o atalho na area de trabalho.

## Como desinstalar

De 2 cliques em `uninstall.bat`.

## Seguranca: `discardMode` (importante)

Quando um repositorio tem alteracoes locais nao commitadas, o script precisa decidir o que
fazer com elas antes de puxar a atualizacao. Ha duas opcoes em `config.json`:

- **`"stash"` (padrao, recomendado)** - roda `git stash push -u`. O repositorio fica limpo e a
  atualizacao segue normalmente, mas suas alteracoes **nao sao perdidas**: ficam guardadas no
  stash e podem ser recuperadas depois com `git stash pop` (ou `git stash list` para ver todos).
- **`"hard"`** - roda `git reset --hard` + `git clean -fd`. O repositorio fica identico ao
  remoto, mas isso **apaga permanentemente** qualquer alteracao ou arquivo novo nao commitado
  naquele repositorio, sem possibilidade de recuperacao. So use isso se tiver certeza de que
  nunca vai ter trabalho em andamento sem commit nesses repositorios no horario agendado - como
  a tarefa roda todo dia sem supervisao, isso pode destruir trabalho real sem aviso previo no
  momento em que acontece (o log registra o que foi apagado, mas o conteudo em si nao volta).

Se voce (ou quem for configurar isso) nao tem certeza de qual usar, fique no `"stash"`.

## VPN automatica: `vpnAutoConnect` (opcional)

Por padrao (`"vpnAutoConnect": false`), quando a VPN esta desconectada o pacote so abre a janela
do FortiClient (se estiver fixado na barra de tarefas) e mostra o aviso normal - a pessoa clica
em "Conectar" ela mesma.

Se mudar para `"vpnAutoConnect": true`, o pacote tenta conectar sozinho: abre a janela do
FortiClient e clica em "Conectar" pela pessoa. Isso so funciona se:

- O **FortiClient estiver fixado na barra de tarefas** (clique direito no icone dele -> "Fixar
  na barra de tarefas", 1x so, manual - nao da pra fixar por script).
- A sessao de SSO da pessoa ja estiver autenticada (mesmo fluxo que ela usaria manualmente, sem
  digitar senha) - se a sessao expirou, o clique automatico nao resolve sozinho, e cai de volta
  no aviso normal.

Se algum desses dois pontos nao se aplicar numa maquina, o auto-connect simplesmente nao
consegue e cai no comportamento padrao (abrir a janela, avisar) - nao quebra nada.

## Se algo der errado

- **Notificacao "VPN desconectada"**: normal - o script detectou que nao alcanca o `gitHost`.
  Conecte a VPN e rode o atalho manual.
- **"git pull --ff-only falhou (provavel divergencia)"**: seu branch local e o remoto
  divergiram (ex: alguem reescreveu historico). O script nao forca nada - resolva manualmente
  com `git pull` ou `git rebase` naquele repositorio.
- **"Filename too long" durante a atualizacao**: limite de caminho do Windows. Aplique o passo
  de `LongPathsEnabled` acima. Ate la, o script so pula aquele repositorio naquele dia, sem
  quebrar nada.
- **Instalador automatico nao encontrou nenhum repositorio**: confirme que os projetos ja foram
  clonados com `git clone`, e que o remoto `origin` deles realmente aponta para o `gitHost`
  configurado (`git remote -v` dentro da pasta do projeto).
- **Antivirus reclama do `certutil` sendo usado por um `.bat`**: os `.bat` deste pacote usam
  `certutil -decode` (ferramenta nativa do Windows) para reconstruir, num arquivo temporario em
  `%TEMP%`, o script que efetivamente roda - e apagam esse arquivo temporario logo depois. E uma
  tecnica valida e comum, mas alguns antivirus mais agressivos podem estranhar por padrao. Se
  isso acontecer, adicione uma excecao para a pasta do pacote.

## Estrutura dos arquivos

- `Instalar-Automatico.bat` - **de 2 cliques aqui** para instalar sem configurar nada: descobre
  os repositorios sozinho e ja instala
- `install.bat` - instalador manual: usa o `config.json` que voce preencheu (`reposRoot`/
  `repoNames` ou `repoPaths`)
- `uninstall.bat` - remove a tarefa agendada e o atalho
- `config.json` - configuracao (gerada sozinha pelo instalador automatico, ou editada a mao)
- `Atualizar-Agora.bat` - o que o atalho da area de trabalho executa (verificacao manual, com
  janela de resultado)
- `update-sankhya-modules.bat` - o que a tarefa agendada executa sozinha, 1x por dia (nao
  precisa clicar nele nunca)
- `logs\` - historico de cada execucao

Nenhum destes arquivos e um `.ps1` solto - a logica de cada um esta embutida dentro do proprio
`.bat`. Se precisar alterar o comportamento do pacote, peca a fonte legivel (em PowerShell) de
quem gerou este template - editar o `.bat` diretamente nao e pratico.
