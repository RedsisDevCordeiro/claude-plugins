# As ferramentas do servidor `redsis`

Assinaturas conferidas em `C:\Agentes\mcp\servidor.py`. Estas **têm** parâmetro de
verdade — ao contrário das skills, que recebem frase e não argumento posicional.

`base` é o nome de um agente ou de um vault, sempre minúsculo (o servidor faz
`.strip().lower()`):

| Base | O que tem |
|---|---|
| `coder` | o código: Delphi/UniGUI, Desktop, form, action, dataset, execução do chamado no fonte |
| `arquitetura` | onde a lógica mora: camadas, convenções, legado, configuração, impacto estrutural |
| `firebird` | Firebird e SQL na aplicação: dialeto, transação, dataset, consulta, parâmetro, performance |
| `qa` | risco, cenário de teste, auditoria pré-release |
| `sac` | o chamado como pedido do cliente, e a API do SAC: rotas, setor, coluna, status, armadilhas e a regra de escrita no chamado |
| `git` | branch, worktree, conflito, commit, Pull Request, integração |
| `fiscal`, `estoque`, `financeiro`, `comercial-rochas` | a regra de negócio da área |
| `curador` | o que entra na base de conhecimento |
| `dba` | o banco DBCOM.RED |
| `regras` | as fichas BR do vault de regras |

A camada 1 de toda base de agente vem com a **camada comum**: o índice geral que diz quem é
dono de cada assunto, os gatilhos e o roteamento. O repositório `AGENTS_CONTEXTS_REDSIS`,
que era a fonte do contexto, está congelado — nada mais é lido de lá.

| Ferramenta | Parâmetros | Obrigatório | Devolve |
|---|---|---|---|
| `redsis_camada1` | `base` | `base` | a camada comum dos agentes + o perfil do agente + o índice da base, concatenados |
| `redsis_ler` | `base`, `alvo` | os dois | uma nota inteira, precedida do caminho relativo |
| `redsis_buscar` | `base`, `termo`, `limite` | `base`, `termo` | as notas que casam, com um trecho de cada |
| `redsis_listar` | `base`, `sob` | `base` | nomes, sem ler conteúdo |

## `redsis_camada1(base)`

**Sempre a primeira chamada** de qualquer pergunta sobre uma base. É a camada que permite
interpretar as demais notas; sem ela, nota específica é lida fora de convenção e a
resposta sai errada com cara de certa.

Resposta grande de propósito (teto próprio, maior que o das outras três).

## `redsis_ler(base, alvo)`

`alvo` é o nome que a base usa. O servidor normaliza antes de resolver — aceita
`[[wikilink]]`, wikilink com alias (`[[DOC|a tabela DOC]]`), caminho relativo, nome puro,
com ou sem `.md`. Formas válidas:

| Forma | Exemplo | Base |
|---|---|---|
| tabela | `DOC` | dba |
| coluna qualificada | `DOC.ALIQAUTO_DOC` | dba |
| view | `VW_...` | dba |
| ficha de regra | `BR-CRO-0007` | regras |
| nota de convenção | `Tipos e Dialeto` | dba |
| wikilink copiado de outra nota | `[[DOCIT.COD_DOC]]` | qualquer |

`alvo` vazio é erro de uso, com mensagem — não stack trace.

## `redsis_buscar(base, termo, limite=20)`

Para quando **não se sabe o nome exato** da nota. Se o nome é conhecido, `redsis_ler` é o
caminho: buscar primeiro só gasta contexto.

`limite` é preso em `[1, 60]` — pedir 500 devolve 60. A ordenação é por pontuação: nome do
arquivo casa vale 3, casamento nos primeiros 400 caracteres (frontmatter) vale 2, menção
solta no corpo vale 1. Nada casando é erro de uso, não lista vazia.

## `redsis_listar(base, sob="")`

Enumera **sem ler**, que é o barato quando a pergunta é "o que existe aqui".

| `sob` | Devolve |
|---|---|
| vazio | as seções (pastas) da base |
| `"DOC"` | as colunas da tabela DOC |
| `"03 - Views"` | as notas daquela pasta |

## O que nenhuma delas faz

Escrever. As quatro das bases são somente leitura, com allowlist por construção: caminho
que escape da raiz, link para fora, arquivo que não seja `.md` ou pasta ignorada não é
servido.

## As do exe (skills `redsis-exe` e `redsis-gerar-integracao`)

Quem pede o exe não tem Delphi: o servidor compila. Estas **não** leem base — enfileiram o
job Jenkins `Redsis Exe` no servidor, que compila `origin/<branch>` como está (sem merge)
num worktree dedicado.

| Ferramenta | Parâmetros | Obrigatório | Devolve |
|---|---|---|---|
| `redsis_exe_gerar` | `chamado`, `branch`, `config`, `versao`, `sem_anexar` | `chamado`, ou `branch` com `sem_anexar=true` | `identificador` e `pedido` para acompanhar |
| `redsis_exe_status` | `identificador`, `pedido`, `aguardar_segundos` | `identificador` | `DRY_RUN`, `PACOTE_PRONTO`, `COMPILADO`, `COLETADO`, `OK`, `FALHOU`, ou `EM_ANDAMENTO`/`NA_FILA` |
| `redsis_exe_anexar` | `chamado`, `sha256` | os dois | o pedido do anexo — só `OK` no status prova o envio |
| `redsis_exe_enviar` | `identificador`, `sha256` | `identificador` | sem `sha256`, o dry-run do envio à pasta da Juliana; com ele, o envio |

`config` é `Debug` (padrão) ou `Release`; `versao` só com Release, `x.y.z.w`.
`aguardar_segundos` é preso em `[0, 50]`: cada chamada já espera, não é preciso dormir
entre elas. `redsis_exe_status` acompanha **todo** pedido ao job — exe, bancada, cenários
(`identificador='cenarios-<n>'`) e envio (`identificador='envio-<id>'`).

`redsis_exe_anexar` e `redsis_exe_enviar` escrevem fora do servidor — no chamado que o
cliente lê e na pasta de outra pessoa — e só aceitam o `sha256` completo do dry-run atual:
se o pacote foi regerado, nada sobe. O destino do envio é fixo, a pasta `Juliana` de
`arquivos.redsis.com.br`, e a credencial dele mora no servidor.

## `redsis_git` (skills `redsis-qa`, `redsis-auditoria` e `redsis-cenarios`)

Git **somente de leitura** no repositório do Redsis do servidor, sem bancada e sem trava —
auditoria de uma hora não segura a vez de ninguém.

| Parâmetro | O que é |
|---|---|
| `argumentos` | a linha já separada: `['log','--oneline','-20','origin/main']` |
| `inicio`, `linhas` | paginação da saída (padrão 1 e 1500, teto 5000) |

Permitidos: `log`, `show`, `diff`, `diff-tree`, `blame`, `grep`, `ls-tree`, `rev-parse`,
`rev-list`, `merge-base`, `cherry`, `for-each-ref`, `describe`, `name-rev`, `shortlog`,
`cat-file` e `fetch` (sempre `fetch --prune origin`). **Não há HEAD nem árvore de trabalho**:
toda chamada leva a referência — `origin/main`, `origin/<branch>`, TAG ou hash —, inclusive
`grep` (`['grep','-n','-e','Texto','origin/main','--','*.pas']`) e `blame`
(`['blame','-L','10,40','origin/main','--','Model/uModel_DOC.pas']`). Sem referência, o git
falha em voz alta em vez de responder vazio. Opção que leria arquivo do servidor ou
executaria programa (`--no-index`, `--contents`, `grep -f`, `-O`...) é recusada.

## A área de trabalho (skills `redsis-qa`, `redsis-auditoria`, `redsis-cenarios`, `redsis-conflitos`)

O que precisa sobreviver à sessão e ser o mesmo para todo mundo mora no servidor.

| Área | O que guarda |
|---|---|
| `qa` | `QA_AAAA-MM-DD_alteracoes_do_dia.md`, relatórios da cópia estável e de treinamento |
| `auditoria` | a fila `bug-estavel-para-main`: `estado.md`, `auditorias/`, `P0`..`P3/` |
| `cenarios` | `<chamado>/`: material coletado e `cenarios-de-teste-<n>.md` |
| `conflitos` | `<branch com - no lugar de />/`: `arquivos.md` e `sugestoes-para-testes.md` |

| Ferramenta | Parâmetros | Devolve |
|---|---|---|
| `redsis_trabalho_listar` | `area`, `sob` | os arquivos, com tamanho e data |
| `redsis_trabalho_ler` | `area`, `caminho`, `inicio`, `linhas` | o arquivo numerado **e o `sha256`** |
| `redsis_trabalho_gravar` | `area`, `caminho`, `conteudo`, `sha256_anterior` | tamanho e `sha256` gravados |

Grava só `.md` e `.txt`, em UTF-8. **Nunca sobrescreve às cegas**: arquivo que já existe só
é substituído com `sha256_anterior` igual ao da leitura — sem ele, ou se alguém mudou o
arquivo no meio, nada é gravado.

## As dos cenários (skill `redsis-cenarios`)

| Ferramenta | Parâmetros | Obrigatório | Devolve |
|---|---|---|---|
| `redsis_cenarios_coletar` | `chamado`, `branch`, `base` | `chamado` | o intervalo, os commits do chamado, os alheios, e o `pedido` da leitura do SAC |
| `redsis_cenarios_anexar` | `chamado`, `sha256` | os dois | o pedido do anexo — só `OK` no status prova o envio |

A coleta resolve a branch no `origin`, delimita a alteração pelos commits que citam
`[<chamado>]` e grava `commits.txt`, `arquivos.txt`, `arquivos-status.txt` e `diff.patch` na
área `cenarios`; o job lê o chamado no SAC e grava `ticket.md` (status `COLETADO`). O anexo
só aceita o `cenarios-de-teste-<n>.md` gravado, com o `sha256` da gravação e o número do
chamado no título.

As duas escritas possíveis no SAC são de anexo — `redsis_exe_anexar` e
`redsis_cenarios_anexar` —, e as duas obedecem à regra do agente `SAC`
(`sac.escrita` § "A regra das duas fases"). Não existe ferramenta para anotar, movimentar,
direcionar ou finalizar chamado: essas rotas existem na API (`sac.api`) e não estão ligadas a
nenhum agente.

## As da consulta ao SAC (skill `redsis-sac`)

Somente leitura, com o usuário de serviço `CLAUDE`, pelo job `Redsis Exe` — a credencial do
SAC só abre na conta do Jenkins. Cada ferramenta espera até ~45 s; se o job estiver ocupado com
um exe, devolve `NA_FILA` e o `identificador` para `redsis_exe_status`.

| Ferramenta | Parâmetros | Obrigatório | Devolve |
|---|---|---|---|
| `redsis_sac_consultar` | `rota`, `parametros`, `corpo`, `campos`, `nome`, `aguardar_segundos` | `rota` | tabela de até 40 linhas; a resposta crua em `<nome>/resposta.json` na área `sac` |
| `redsis_sac_chamados` | `codigos` (até 60), `nome`, `aguardar_segundos` | `codigos` | quem atendeu, quem finalizou e o texto da finalização; `<codigo>.json`, `<codigo>.md` e `indice.tsv` na área `sac` |

`rota` vai sem query string — os filtros vão em `parametros` (ex. `{'setor': 'AN'}`). `corpo`
só existe para `POST /atendimentos/pesquisar`, a rota que lista finalizados, com os campos
`cliente`, `assunto`, `atendente`, `setor`, `situacao`, `data_inicial`, `data_final`, `filtro`,
`pesquisa` e `grupo`. A allowlist de leitura está no servidor e no job; rota de escrita é
recusada nos dois. Sem `nome`, a pasta ganha um nome aleatório; repetir um `nome` apaga a
consulta anterior com esse nome. Em `pesquisar`, `atendente` e `cliente` são códigos
(`codatendpref`, `codpessoa`): nome é recusado, porque o SAC o ignora e devolve tudo. A área
`sac` apaga sozinha a consulta com mais de 7 dias.

## `redsis_skills` (skill `redsis-ajuda`)

| Parâmetro | O que é |
|---|---|
| `skill` | filtra pelo nome da pasta ou pelo `name:`; vazio traz o catálogo |
| `completo` | `true` traz o `SKILL.md` inteiro |

Lê o zip do plugin **publicado** — o que o auto-update entrega —, não o disco de quem pergunta.

## As da bancada (skills `redsis-conflitos` e `redsis-gerar-integracao`)

A **bancada** é a cópia de trabalho do servidor. Quem resolve conflito ou monta integração
pode não ter Delphi **nem o Redsis clonado**: o git e os arquivos são os de lá, e quem decide
continua sendo o Claude da pessoa. É **uma bancada por vez no servidor inteiro** — o disco não
comporta duas cópias —, e por isso existe a `sessao`, que é a trava.

| Ferramenta | Parâmetros | Devolve |
|---|---|---|
| `redsis_bancada_estado` | — | se a vez está livre, e de quem é a sessão aberta |
| `redsis_bancada_abrir` | `branch`, `base`, `chamado`, `forcar`, `criar_de` | a `sessao` e a branch temporária de trabalho |
| `redsis_bancada_git` | `sessao`, `argumentos` (lista) | a saída do git, mais o HEAD depois dele |
| `redsis_bancada_ler` | `sessao`, `caminho`, `inicio`, `linhas` | o arquivo numerado, decodificado |
| `redsis_bancada_editar` | `sessao`, `caminho`, `antigo`, `novo`, `ocorrencias` | troca o trecho gravando em bytes |
| `redsis_bancada_duplicidade` | `sessao`, `referencia` | campo/componente repetido que a integração criou |
| `redsis_bancada_compilar` | `sessao`, `config` | pedido de `Debug/Win32` da árvore como está |
| `redsis_bancada_exe` | `sessao`, `chamado`, `config`, `versao` | o exe do merge resolvido, em dry-run |
| `redsis_bancada_publicar` | `sessao`, `destino`, `confirmar` | dry-run do `push`; publica só com `confirmar=true` |
| `redsis_bancada_fechar` | `sessao`, `apagar_branch` | libera a vez; a branch temporária é mantida por padrão |

`criar_de` serve para a branch que **ainda não existe** no remoto — o caso da integração de
release, que nasce da `main`. `redsis_bancada_editar` grava em **bytes**, preservando
Windows-1252 e CRLF nos `.pas` e `.dfm`: é o que torna seguro editar por ali onde a tool
`Edit` corromperia todo acento do arquivo. `git push` **não** passa por `redsis_bancada_git`;
publicar é `redsis_bancada_publicar`, com confirmação.

## Numa máquina cliente o vault não existe

Os ~41 MB de notas ficam no servidor. `Grep` ou `Read` sobre a pasta de uma base **não é
caminho alternativo** — é sinal de que a ferramenta certa não foi usada. Se o servidor não
responder, a resposta correta é dizer isso e parar; regra de negócio respondida de memória
é exatamente o que a base existe para impedir.
