# Redsis — para agentes que nao sao o Claude Code

**Este repositorio e um ponteiro de 2 KB e nao contem as skills.** Se voce e um agente
lendo este arquivo procurando o indice dos procedimentos: ele nao esta aqui. Esta no
pacote que a secao 2 explica como baixar.

O que existe aqui e so o `.claude-plugin/marketplace.json`, que a aba de plugins do Claude
Code precisa encontrar no `github.com`. Todo o resto — skills e bases de conhecimento —
e servido pelo servidor da Redsis.

---

## 1. As bases de conhecimento (funciona em qualquer cliente MCP)

O banco `DBCOM.RED` e as regras de negocio do ERP sao servidos ao vivo por MCP sobre HTTP.
Isso funciona **hoje**, sem baixar nada, em Codex, Cursor, Gemini CLI e VS Code.

No Codex, em `~/.codex/config.toml`:

```toml
[mcp_servers.redsis]
url = "https://mcp.redsis.com.br/mcp"
bearer_token_env_var = "REDSIS_MCP_TOKEN"
```

E o token no ambiente, uma vez so:

```powershell
[Environment]::SetEnvironmentVariable('REDSIS_MCP_TOKEN', '<o token>', 'User')
```

Terminal que ja estava aberto nao enxerga a variavel nova. Abra um novo depois.

Para os outros clientes — Cursor, VS Code, Gemini CLI — o bloco de cada um esta em
<https://mcp.redsis.com.br/plugin/CLIENTES-MCP.md>. Atencao: o Gemini CLI nao expande
variavel de ambiente em `headers`, entao la o token fica literal no arquivo.

As bases saem por quatro ferramentas, somente leitura: `redsis_camada1`, `redsis_buscar`,
`redsis_ler`, `redsis_listar`. **Comece sempre pela `redsis_camada1`** da base que a pergunta
pede: e a camada que permite interpretar qualquer nota. Ler uma nota sem ela leva a conclusao
errada, porque as notas assumem as convencoes como sabidas.

O mesmo servidor tambem compila o exe do chamado (`redsis_exe_*`) e oferece a bancada
(`redsis_bancada_*`): o git e os arquivos do Redsis no servidor, para resolver conflito e
montar integracao sem Delphi nem clone na maquina.

## 2. O texto dos procedimentos

Os procedimentos (atender chamado, resolver conflitos, QA, auditoria) sao arquivos de
texto. Para te-los em disco, com o indice `AGENTS.md` que os organiza:

```powershell
$c = irm https://mcp.redsis.com.br/plugin/marketplace.json
irm $c.plugins[0].source.url -OutFile "$env:TEMP\redsis.zip"
Expand-Archive "$env:TEMP\redsis.zip" -DestinationPath .\redsis -Force
```

Isso resolve a versao atual pelo catalogo e deixa em `.\redsis` um `AGENTS.md` com as 12
descricoes e a pasta `skills\` com o texto completo de cada uma. Aponte o seu agente para
essa pasta.

Da para so olhar o indice antes de baixar, em
<https://mcp.redsis.com.br/plugin/AGENTS.md>.

---

## O que esperar, com honestidade

| | |
|---|---|
| As skills de consulta (`cerebro-*`) e o contexto dos agentes | funcionam inteiros: sao puro MCP, uma base por agente |
| Os procedimentos que mexem no clone do Redsis (`redsis-chamado`, `redsis-excluir-branchs-mergeadas`) | precisam do Redsis clonado e das ferramentas git da maquina |
| `Test-Ancoras.ps1` | so serve a quem mantem as skills; o zip o traz em `scripts\`, e quem o coloca no caminho absoluto e o instalador do Claude Code |

Os perfis de subagente vao em `agents\`: no Claude Code um agente pode consultar o outro. Em
ferramenta que nao tem subagente, leia a base do dono direto com `redsis_camada1`.

E um limite que instalador nenhum resolve: os procedimentos foram escritos para as
ferramentas do Claude Code — `allowed-tools`, worktree, comandos git especificos. Outro
agente **le** essas instrucoes e tenta seguir, mas nao tem as mesmas travas. Para consultar
as bases isso nao importa. Para conduzir um chamado de verdade, importa bastante.

## Claude Code

Se voce usa Claude Code, ignore tudo acima. Uma linha instala tudo:

```powershell
& ([scriptblock]::Create((irm https://mcp.redsis.com.br/plugin/Instalar.ps1).TrimStart([char]0xFEFF))) -Token '<o token>'
```
