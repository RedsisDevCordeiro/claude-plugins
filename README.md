# Skills da Redsis para o Claude Code

Este repositório é **fino de propósito**: só o plugin, ~75 KB. As bases de conhecimento —
os 40 MB de notas do DBA e as fichas de regra de negócio — **não estão aqui** e nunca vão
para a máquina de ninguém. Elas são servidas ao vivo pelo servidor MCP da Redsis.

## Instalar (uma vez por máquina)

```powershell
git clone https://github.com/RedsisDevCordeiro/claude-plugins.git
cd claude-plugins
powershell -ExecutionPolicy Bypass -File .\Instalar.ps1 -Token "<peça o token a quem cuida do servidor>"
```

Depois disso você não atualiza mais nada. Skill nova, correção de skill e conteúdo novo das
bases chegam sozinhos.

Pré-requisito: o CLI do Claude Code (`npm install -g @anthropic-ai/claude-code`) e `git`.

## O que você ganha

| Skill | Para quê |
|---|---|
| `/redsis:cerebro-dba` | o que é cada tabela, coluna e view do DBCOM.RED, e como juntá-las sem FK |
| `/redsis:cerebro-regras` | qual regra de negócio o ERP aplica, com a ficha e o `arquivo:linha` |
| `/redsis:cerebro-redsis` | qual contexto ler para a tarefa, e qual fonte vence num empate |
| `/redsis:redsis-chamado` | o ciclo de um chamado: triagem, worktree, correção, merge, teste, PR |
| `/redsis:redsis-conflitos` | integrar a `main` nas branches de chamado resolvendo por significado |
| `/redsis:redsis-qa` | o tour de QA sobre o que foi puxado |
| `/redsis:redsis-auditoria` | a auditoria pré-release entre a TAG estável e a `main` |
| `/redsis:redsis-escriba` | registrar na base de contextos o que foi descoberto |

Você não precisa digitar o comando: o Claude escolhe a skill sozinho pela descrição dela.
Digitar serve para forçar uma específica.

## Como as atualizações chegam

Há duas velocidades, e nenhuma delas exige ação sua:

- **Conteúdo das bases** — o dono edita as notas no servidor e a resposta seguinte já sai
  diferente. Instantâneo, porque o conteúdo nunca foi copiado para cá.
- **Texto das skills** — o servidor publica aqui, e o auto-update do Claude Code busca em
  background depois que sua sessão começa. Você vê um aviso para rodar `/reload-plugins`,
  ou a versão nova sobe no próximo start.

## O que a instalação mexe na sua máquina

Tudo reversível, e nada fora destes cinco pontos:

| O quê | Onde |
|---|---|
| variável `REDSIS_MCP_TOKEN` | ambiente do seu usuário |
| plugin `redsis` | `~/.claude/plugins/` (escopo usuário) |
| auto-update do marketplace e liberação das ferramentas do MCP | `~/.claude/settings.json` (o anterior fica em `settings.json.bak`) |
| base de contextos (9 MB de markdown) | `C:\Developer\AGENTS_CONTEXTS_REDSIS` |
| dois scripts de apoio (~9 KB) | `C:\Agentes\scripts` |

Os dois últimos existem porque as skills de procedimento operam no fonte do ERP na **sua**
máquina, e leem o procedimento canônico da base de contextos.

## Não vai nada sensível daqui

O token do MCP **não** está neste repositório e nunca vai estar: ele vem da variável de
ambiente de cada máquina, e o `.mcp.json` do plugin só carrega `${REDSIS_MCP_TOKEN}`. Este
repositório é público; qualquer segredo dentro dele seria um segredo público.

## Publicação (só quem cuida do servidor)

Não edite as skills aqui — este diretório é espelho. A fonte é `C:\Agentes\*\skill\*` no
servidor, e quem espelha é o `C:\Agentes\scripts\Publicar-Plugin.ps1`, que descobre as
skills pela pasta e incrementa a versão sozinho.
