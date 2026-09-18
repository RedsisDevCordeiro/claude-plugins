# Redsis — conhecimento e procedimentos

<!-- Gerado por scripts/Publicar-Plugin.ps1 a partir das pastas de skill.
     Nao edite a mao: a proxima publicacao sobrescreve. -->

## As bases de conhecimento

O conhecimento do Redsis nao esta neste repositorio: e servido ao vivo pelo servidor
MCP da Redsis, **uma base por agente especialista**, em
`https://mcp.redsis.com.br/mcp`. Configure-o no seu cliente antes de usar qualquer
procedimento abaixo — o passo a passo por ferramenta esta em `CLIENTES-MCP.md`.

Quatro ferramentas de leitura das bases, tres do exe, as da bancada e as de consulta ao SAC, todas no servidor:

| Ferramenta | Para que serve |
|---|---|
| `redsis_camada1` | **Comece sempre por aqui.** Convencoes que permitem interpretar qualquer nota da base. |
| `redsis_buscar` | Procura notas por termo. |
| `redsis_ler` | Le uma nota especifica. |
| `redsis_listar` | Lista o que existe numa pasta da base. |
| `redsis_exe_gerar` | Compila no servidor o exe da branch do chamado (dry-run, nada enviado). |
| `redsis_exe_status` | Acompanha o pedido de exe ate o fim. |
| `redsis_exe_anexar` | **Escreve no SAC:** anexa o pacote conferido. So com o "pode" do programador. |
| `redsis_bancada_*` | A copia de trabalho do servidor: git, ler, editar, duplicidade, compilar e publicar, sem Delphi nem clone na maquina de quem pede. |
| `redsis_sac_consultar` | Consulta SOMENTE LEITURA ao SAC com o usuario de servico: fila, chamado, finalizados (POST /atendimentos/pesquisar), cadastros. |
| `redsis_sac_chamados` | Le ate 60 chamados de uma vez: quem atendeu, quem finalizou e o texto da finalizacao. |

Ler uma nota sem ter lido a camada 1 da base correspondente leva a conclusao errada:
as notas assumem as convencoes como sabidas.

### Uma base por agente

| Base | Agente dono |
|---|---|
| `coder` | o codigo: Delphi/UniGUI, Desktop, form, action, dataset, execucao do chamado no fonte |
| `arquitetura` | onde a logica mora: camadas, convencoes, legado, configuracao, impacto estrutural |
| `firebird` | Firebird e SQL na aplicacao: dialeto, transacao, dataset, consulta, performance |
| `qa` | risco, cenario de teste, auditoria pre-release |
| `sac` | o chamado como pedido do cliente, e a API do SAC onde ele vive |
| `git` | branch, worktree, conflito, commit, Pull Request, integracao |
| `fiscal`, `estoque`, `financeiro`, `comercial-rochas` | a regra de negocio da area |
| `curador` | o que entra na base de conhecimento |
| `dba`, `regras` | os dois vaults: banco DBCOM.RED e fichas BR |

A camada 1 de toda base de agente traz o indice geral, que diz **quem e dono de que**,
mais os gatilhos e o roteamento. Na duvida sobre o dono, leia `redsis_camada1('coder')`.
No Claude Code (`agents/`) e no Codex (`codex/agents/`) os agentes tambem vem como
subagentes, e um pode consultar o outro; em outras ferramentas, leia a base do dono direto.

## Procedimentos

Cada item abaixo e um procedimento completo, com regras e limites proprios. O resumo
serve para voce **escolher** qual se aplica; ele nao basta para executar.

**Antes de executar qualquer um, abra e leia o `SKILL.md` inteiro dele.** Boa parte do
que esta la sao proibicoes — o que o procedimento NAO deve fazer — e elas nao cabem
no resumo.

### cerebro-dba

Responde o que é cada tabela, coluna e view do banco DBCOM.RED (ERP Redsis, Firebird), como as tabelas se ligam sem FK, o que cada valor de campo codificado significa, e monta SELECT que já nasce com as armadilhas do banco tratadas. Use sempre que a pergunta citar uma tabela, coluna ou view desse banco, pedir um SELECT sobre ele, perguntar como juntar duas tabelas, ou perguntar o que um código guardado num campo quer dizer.

Texto completo: `skills/cerebro-dba/SKILL.md`

### cerebro-redsis

Argumentos: `[assunto ou tabela ou tela]`

Diz qual contexto da base Redsis ler para a tarefa em mãos, qual procedimento canônico responde a um pedido, e qual fonte vence quando duas se contradizem. Use sempre que a pergunta for "onde está documentado X", "qual contexto preciso ler para mexer em Y", "qual o procedimento para Z", "que regra vale aqui", ou antes de mexer no fonte do Redsis sem saber o que a base já decidiu. NAO responde estrutura de tabela (isso é cerebro-dba) nem qual regra de negócio o sistema aplica (isso é cerebro-regras).

Texto completo: `skills/cerebro-redsis/SKILL.md`

### cerebro-regras

Responde qual regra de negocio o ERP Redsis aplica — o que ele exige, calcula, impede, quem pode fazer, e por que — com a ficha e o arquivo:linha que sustentam a resposta. Use sempre que a pergunta for "o sistema deixa fazer X", "por que o Redsis bloqueia Y", "como e calculado Z", "qual regra vale para o documento tipo W", ao revisar PR que muda comportamento, ou antes de refatorar rotina do modulo. NAO responde estrutura de tabela (isso e cerebro-dba) nem onde fica a tela (isso e redsis-sistema).

Texto completo: `skills/cerebro-regras/SKILL.md`

### redsis-acbr

Argumentos: `[revisao|HEAD] [so-reinstalar]`

Atualiza o ACBr DESTA máquina — `svn update` na pasta do ACBr e reinstalação pelo `ACBrInstall_Trunk2.exe` conduzida sozinha, sem clicar no assistente — e só declara pronto quando o log do instalador confirma os pacotes compilados e instalados. Use quando o pedido for "atualiza o ACBr", "dá update no ACBr e reinstala", "roda o ACBrInstall", "reinstala o ACBr", "o ACBr está desatualizado", "o Redsis não compila por causa do ACBr", "o Delphi perdeu os componentes do ACBr" ou "volta o ACBr para a revisão N". NAO compila nem corrige o Redsis (isso é redsis-chamado), NAO gera exe no servidor (isso é redsis-exe) e NAO mexe no ACBr de outra máquina.

Texto completo: `skills/redsis-acbr/SKILL.md`

### redsis-ajuda

Argumentos: `[nome da skill ou o que você quer fazer]`

Explica o que cada skill do plugin Redsis faz quando é chamada, o que a dispara, o que ela autoriza e o que ela recusa, quais argumentos aceita, e quais parâmetros as ferramentas do servidor MCP recebem — as das bases, as do git por referência, as da área de trabalho, as do exe e as da bancada. Use quando o pedido for "quais skills eu tenho", "o que essa skill faz", "como eu chamo a redsis-chamado", "que parâmetros a redsis-exe aceita", "qual skill usar para X", "ajuda", "help" ou "me explica o plugin da Redsis". NAO executa nenhuma dessas skills nem o trabalho delas — só descreve.

Texto completo: `skills/redsis-ajuda/SKILL.md`

### redsis-auditoria

Argumentos: `[TAG ou modo]`

Conduz a auditoria pré-release do ERP Redsis entre a TAG estável e a `main` — intervalo por checkpoint, provar ou refutar cada achado, pré-chamados com `problema.txt`, `solucao.md` e `teste.md`, revalidação e fechamento do ciclo. Tudo pelo servidor MCP da Redsis: o git é o do servidor e a fila de pré-chamados mora lá, sem nada instalado em quem pede. Use quando o pedido for "faça uma auditoria na main", "audite a TAG 4.1.15 contra a main", "valide e feche a auditoria estavel-para-main" ou "faça a próxima auditoria estavel-para-main". NAO faz o QA do que foi puxado nem da cópia estável (isso é redsis-qa) e NAO altera código.

Texto completo: `skills/redsis-auditoria/SKILL.md`

### redsis-cenarios

Argumentos: `[numero-do-chamado]`

Monta os cenários de teste de um chamado já corrigido — lê o relato no SAC, lê a alteração real da branch do chamado, cruza com o impacto em cascata e entrega `cenarios-de-teste-<número>.md` anexado no próprio chamado, para quem vai testar. Tudo pelo servidor MCP da Redsis — quem pede não precisa de Delphi, git, clone do Redsis nem credencial do SAC. Use quando o pedido for "gera os cenários de teste do chamado 19436169", "o que precisa ser testado nesse chamado", "monta o roteiro de teste dessa branch", "anexa os cenários no chamado" ou "quero ter certeza do que testar antes de liberar". NAO corrige o chamado nem prepara o ambiente de teste (isso é redsis-chamado), NAO compila nem anexa executável (isso é redsis-exe) e NAO escreve script do TestComplete.

Texto completo: `skills/redsis-cenarios/SKILL.md`

### redsis-chamado

Argumentos: `[numero-do-chamado]`

Conduz o chamado do ERP Redsis dentro de uma worktree isolada — triagem, correção sob as regras do agente Coder, `solucao.md` e preparação do ambiente de teste — e entrega a alteração EM ABERTO para o programador conferir e comitar. NAO comita, NAO faz merge, NAO da push e NAO cria Pull Request. Use quando o pedido for "preciso resolver o chamado 19427930", "vou testar", "quero testar", "me mostra o que mudou", "terminei esse chamado" ou "finalizar em Release". NAO integra a main em lote nas branches (isso é redsis-conflitos) e NAO revisa PR alheio (isso é bitbucket-pr-review).

Texto completo: `skills/redsis-chamado/SKILL.md`

### redsis-conflitos

Argumentos: `[branch...]`

Integra a `main` nas branches de chamado do Redsis resolvendo os conflitos por significado, na bancada do servidor — sem Delphi e sem clone na máquina de quem pede —, compila cada resolução, publica a branch integrada de volta no Bitbucket, entrega `arquivos.md` e `sugestoes-para-testes.md` e gera o executável de cada chamado para anexar no chamado do SAC. Use quando o pedido for "quero resolver os conflitos das branches", "atualiza as branches com a main", "resolve os conflitos de Corretivos/X e Evolutivos/Y", "gera os exes das branches que você integrou" ou "anexa os exes nos chamados do lote". NAO cria Pull Request, NAO mescla na main e NAO atende um chamado do zero (isso é redsis-chamado).

Texto completo: `skills/redsis-conflitos/SKILL.md`

### redsis-excluir-branchs-mergeadas

Argumentos: `[--apagar]`

Lista as branches locais do clone do Redsis cujo conteúdo já entrou na `main` ou na TAG estável e apaga essas branches SOMENTE do local, depois de você confirmar. Use quando o pedido for "quais branches já foram mergeadas", "limpa as branches locais", "apaga as branches que já entraram na main", "poda as branches do local", "exclui as branches mergeadas do local". NAO apaga nada no remoto, NAO dá push e NAO integra a main nas branches (isso é redsis-conflitos).

Texto completo: `skills/redsis-excluir-branchs-mergeadas/SKILL.md`

### redsis-exe

Argumentos: `[numero-do-chamado] [debug|release] [versao]`

Gera o executável do ERP Redsis a partir da branch de um chamado — compila NO SERVIDOR a branch como está no remoto, em Debug ou Release, compacta em `Redsis_<número>.rar`, anexa no chamado do SAC e apaga a cópia do servidor depois. Quem pede não precisa de Delphi. Use quando o pedido for "gera o exe do chamado 19436169", "compila o chamado 19436169 em release", "manda o exe pro chamado", "anexa o executável no chamado" ou "preciso do exe dessa branch para os testes". NAO atende o chamado nem prepara o ambiente de teste na worktree (isso é redsis-chamado) e NAO integra a main nas branches (isso é redsis-conflitos).

Texto completo: `skills/redsis-exe/SKILL.md`

### redsis-gerar-integracao

Argumentos: `[versao] [chamado...]`

Monta a próxima branch `Integracoes/Integracao_NN` a partir da main na bancada do servidor — sem Delphi, sem clone e sem credencial nenhuma na máquina de quem pede —, puxa por cherry-pick o pull request de cada chamado aprovado, resolve os conflitos, varre duplicidade, publica com autorização, compila o Release na versão informada e envia o pacote, do próprio servidor, para a pasta da Juliana. Use quando o pedido for "gera a integração com esses chamados", "monta a próxima integração", "gera a Integracao_06 na versão 4.1.16.0" ou "sobe o exe da integração pra Juliana". NAO atende chamado do zero (isso é redsis-chamado) e NAO integra a main nas branches de chamado (isso é redsis-conflitos).

Texto completo: `skills/redsis-gerar-integracao/SKILL.md`

### redsis-qa

Argumentos: `[intervalo git ou branch]`

Faz o tour de QA do ERP Redsis sobre o que foi puxado — intervalo pelo reflog, crítica de código com trecho atual e trecho sugerido, trava de assinaturas, colheita de conhecimento — e grava o relatório no servidor da Redsis. O modo diário usa o git da própria pessoa (é o que ela puxou); a cópia estável e as branches publicadas rodam só pelo servidor. Use quando o pedido for "o que puxei hoje", "as atualizações de hoje", "as correções puxadas", "analise esse pull/branch/diff", "faça uma auditoria na cópia estável", ou "treinamento". NAO audita a main contra a TAG estável (isso é redsis-auditoria) e NAO altera código.

Texto completo: `skills/redsis-qa/SKILL.md`

### redsis-sac

Argumentos: `[o que consultar: numero, setor, periodo, cliente]`

Consulta o SAC da Redsis, somente leitura, pelo servidor MCP — fila de um setor, ficha e timeline de um chamado, quem atendeu, quem finalizou e o que escreveu, finalizados por período, chamados de um cliente, cadastros de setor, coluna, assunto e tag — e varre lotes de chamados para achar finalização vazia ou mal descrita. Usa o usuário de serviço CLAUDE; quem pede não precisa de credencial do SAC. Use quando o pedido for "quem atendeu o chamado 19436169", "como foi finalizado o 19436169", "me mostra a fila do AN", "quais chamados o setor AN finalizou esta semana", "chamados abertos do cliente X", "tem finalização mal descrita no AN em setembro?" ou "consulta o SAC". NAO escreve no chamado — não anota, não move, não direciona, não finaliza e não anexa (anexo é de redsis-exe e redsis-cenarios) — e NAO corrige nem testa chamado.

Texto completo: `skills/redsis-sac/SKILL.md`

## Limites

- As bases sao **somente leitura**. Nenhum procedimento aqui escreve nelas.
- O exe do chamado e compilado no servidor: ninguem precisa de Delphi para pedi-lo.
- Os procedimentos foram escritos para o clone do Redsis numa maquina de
  desenvolvimento. Fora desse contexto, varios nao fazem sentido.
- Nenhum deles da push nem abre Pull Request. Isso e sempre decisao de gente.
