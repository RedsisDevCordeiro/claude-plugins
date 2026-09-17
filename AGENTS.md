# Redsis — para agentes que nao sao o Claude Code

Este repositorio traz o **texto** dos procedimentos da Redsis e o catalogo do plugin. **As
bases de conhecimento nao estao aqui**: ficam no servidor da Redsis e sao consultadas ao
vivo pelo MCP. Nao procure nota de base neste repositorio nem copie base para disco.

---

## Codex

Instale o plugin. Ele traz as skills, os especialistas como subagentes e o servidor MCP:

```powershell
& ([scriptblock]::Create((irm https://mcp.redsis.com.br/plugin/Instalar.ps1).TrimStart([char]0xFEFF))) -Token '<o token>' -Codex
```

O que a instalacao faz esta no `README.md`.

## Outros clientes (Cursor, VS Code, Gemini CLI)

### 1. As bases de conhecimento

O banco `DBCOM.RED`, as regras de negocio e o contexto de cada especialista sao servidos ao
vivo por MCP sobre HTTP, em `https://mcp.redsis.com.br/mcp`, com o token no cabecalho
`Authorization: Bearer`. O bloco de configuracao de cada cliente esta em
<https://mcp.redsis.com.br/plugin/CLIENTES-MCP.md>. Atencao: o Gemini CLI nao expande
variavel de ambiente em `headers`, entao la o token fica literal no arquivo.

E o token no ambiente, uma vez so:

```powershell
[Environment]::SetEnvironmentVariable('REDSIS_MCP_TOKEN', '<o token>', 'User')
```

Terminal que ja estava aberto nao enxerga a variavel nova. Abra um novo depois.

**Comece sempre pela `redsis_camada1`** da base que a pergunta pede: e a camada que permite
interpretar qualquer nota. Ler uma nota sem ela leva a conclusao errada, porque as notas
assumem as convencoes como sabidas.

O mesmo servidor tambem compila o exe do chamado (`redsis_exe_*`) e oferece a bancada
(`redsis_bancada_*`): o git e os arquivos do Redsis no servidor, para resolver conflito e
montar integracao sem Delphi nem clone na maquina.

### 2. O texto dos procedimentos

Esta neste repositorio, em `plugins/redsis/`: o indice `AGENTS.md` com a descricao de cada
procedimento e a pasta `skills/` com o texto completo. Aponte o seu agente para essa pasta.

---

## O que esperar, com honestidade

| | |
|---|---|
| As skills de consulta (`cerebro-*`) e o contexto dos agentes | funcionam inteiros: sao puro MCP, uma base por agente |
| Os procedimentos que mexem no clone do Redsis (`redsis-chamado`, `redsis-excluir-branchs-mergeadas`) | precisam do Redsis clonado e das ferramentas git da maquina |
| `Test-Ancoras.ps1` | so serve a quem mantem as skills; o plugin o traz em `scripts/` |

Os especialistas vem como subagentes no Claude Code (`agents/`) e no Codex
(`codex/agents/`), e um pode consultar o outro. Em ferramenta que nao tem subagente, leia a
base do dono direto com `redsis_camada1`.

E um limite que instalador nenhum resolve: os procedimentos foram escritos para as
ferramentas do Claude Code, onde cada skill so enxerga as ferramentas que lista. Outro
agente **le** essas instrucoes e tenta seguir, mas nao tem as mesmas travas. No Codex, a
instalacao compensa em parte: as quatro ferramentas que escrevem fora do servidor pedem
confirmacao antes de rodar.

## Claude Code

Se voce usa Claude Code, ignore tudo acima. Uma linha instala tudo:

```powershell
& ([scriptblock]::Create((irm https://mcp.redsis.com.br/plugin/Instalar.ps1).TrimStart([char]0xFEFF))) -Token '<o token>'
```
