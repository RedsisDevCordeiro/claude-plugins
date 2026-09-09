# Integrações especiais — `Integracoes/Integracao_<versão>`

Leia isto **antes de qualquer etapa** quando a branch de destino começar com `Integracoes/`.
Não é gatilho de frase: é a categoria da branch que muda o fluxo.

A fonte canônica é `projeto.chamados` § "Integrações especiais (`Integracoes/`)". Este
arquivo lista só os **deltas** em relação ao ciclo comum — o resto do fluxo continua valendo.

## Identidade

O identificador é `Integracao_<major.minor.release.build>` — quatro componentes — e é o mesmo
na pasta, na branch `codex/` e na mensagem de commit.

Origem padrão: `Tags/<major.minor.release>` (três componentes). Confirmar que ela existe e
está sincronizada com o remoto. Origem explícita informada pelo programador prevalece.
**Não inventar referência ausente.**

## Resolução de conflito

Criar `codex/Integracao_<versão>` a partir da branch de destino e integrar a origem nela.
Antes de decidir conflito semântico: comparar ancestral comum, commits exclusivos e histórico
dos trechos.

- **Não** resolver o arquivo inteiro com `ours` ou `theirs`.
- Preservar correção independente dos dois lados.
- Usar histórico, consumidores atuais e compilação para achar a intenção compatível.
- Registrar decisão funcional relevante no `solucao.md`.

> [!danger] Componente duplicado em `.dfm` só aparece em execução
> Em DFM alterado pela integração, comparar nomes de componente com **os dois pais**. A
> compilação aceita a duplicidade; o streaming do formulário estoura em execução com
> `EComponentError`. Antes de considerar a integração estável, fazer ao menos o teste de
> inicialização em Debug.

## Banco

A ausência do `DBCOM.RED` **não impede** resolver conflito nem fazer revisão estática:
informar a ausência e seguir só nas etapas independentes do banco. O arquivo passa a ser
obrigatório quando o programador pedir a preparação do teste.

## Teste e Release

Primeiro teste em `Debug`/`Win32`, com banco copiado e validado, usando o executável canônico
do checkout principal.

A Release versionada sai **somente** depois de o programador confirmar o sucesso do teste em
Debug **e** pedir. Então: validar que os quatro componentes coincidem com o identificador,
ajustar o version info temporariamente, compilar `Release`/`Win32`, conferir nos metadados do
executável que `FileVersion` **e** `ProductVersion` batem com o pedido, copiar para a pasta do
chamado, comparar tamanho e SHA-256, e **restaurar exatamente** o `.dproj` e a configuração de
trabalho. A alteração temporária de versão **não** é comitada.

Existência do arquivo e sucesso do compilador **não** substituem a conferência dos metadados.

Gerar a cópia Release **não** cria `texto_finalizacao_chamado.txt` nem encerra o chamado.

## Inventário Git no `solucao.md` — exclusivo desta categoria

O `solucao.md` de uma integração carrega, além do conteúdo comum, um inventário que o
atendimento comum não tem:

- o intervalo efetivamente incorporado, e as referências exatas usadas para calculá-lo;
- por commit funcional: código do chamado extraído da mensagem, hash abreviado,
  programador/autor, data e resumo;
- commits funcionais **separados** de merges e sincronizações técnicas, com as quantidades de
  cada grupo — **sem atribuir alteração funcional a quem apenas integrou branches**;
- alias de autor consolidado só com evidência inequívoca (mesmo e-mail);
- `não informado` marcado explicitamente onde faltar o código do chamado.
