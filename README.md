# redsis-tools — catalogo de plugins da Redsis

Este repositorio carrega o plugin `redsis` para o Claude Code e para o Codex. **As bases de
conhecimento nao estao aqui**: ficam no servidor da Redsis e sao consultadas ao vivo pelo
MCP, autenticadas pelo token. O que existe aqui e so texto de instrucao.

| Caminho | Quem usa | O que e |
|---|---|---|
| `.claude-plugin/marketplace.json` | Claude Code | catalogo que aponta o plugin no servidor da Redsis |
| `.agents/plugins/marketplace.json` | Codex | catalogo que aponta a copia em `plugins/redsis` |
| `plugins/redsis/` | Codex | copia do plugin: skills, `.mcp.json` e os especialistas |
| `plugins/redsis/codex/agents/` | Codex | os especialistas no formato de subagente do Codex |

Por que dois caminhos: a aba de plugins do Claude Code so aceita catalogo de `github.com`,
mas o plugin dele continua saindo do servidor. O Codex so instala plugin por git, entao
para ele o plugin vem inteiro daqui. Cada cliente acha o seu catalogo e ignora o do outro.

## Instalar no Claude Code

Cole na aba de plugins do Claude Code:

```
RedsisDevCordeiro/claude-plugins
```

Depois abra o `redsis-tools`, clique em **Install** no plugin `redsis` e, no menu do
marketplace, em **Enable auto-update**.

Ou, numa linha so e sem aba nenhuma:

```powershell
& ([scriptblock]::Create((irm https://mcp.redsis.com.br/plugin/Instalar.ps1).TrimStart([char]0xFEFF))) -Token '<o token>'
```

Essa forma tambem grava o token, liga o auto-update e pre-aprova as ferramentas do MCP.

## Instalar no Codex

Precisa de git. Numa linha so:

```powershell
& ([scriptblock]::Create((irm https://mcp.redsis.com.br/plugin/Instalar.ps1).TrimStart([char]0xFEFF))) -Token '<o token>' -Codex
```

Ela grava o token, registra este catalogo, instala o plugin, liga os especialistas como
subagentes, pre-aprova as ferramentas do servidor (menos as que escrevem no SAC, na pasta
da Juliana e no Bitbucket, que o Codex pergunta antes) e pede ao Codex, no
`~/.codex/AGENTS.md`, que delegue aos especialistas as perguntas sobre o Redsis.

Depois disso nada se atualiza a mao: o Codex busca este catalogo sempre que abre.

## Manutencao

Nada aqui e editado a mao. O `scripts/Publicar-Plugin.ps1` gera os dois catalogos e a copia
em `plugins/redsis` a partir do zip que acabou de publicar no servidor, e faz o commit.
Editar a mao so cria divergencia.
