# Padrão de escrita do FAQ de versão

Aprendido de `GET /faq/<n>/anotacoes` em 31/08/2026: FAQs 210, 197, 191 e 158, 108 itens. Há dois
estilos, ligados a quem escreveu (`usuario` do item). **Siga o do 8856.**

## Estilo 8856 — o que esta skill reproduz

Correção (`tipo: C`):

```
Descrição do Problema: <problema>.
Solução: <o que foi feito>.
```

Evolução (`tipo: E`):

```
Solicitação: <pedido>
Implementação: <o que foi feito>.
```

Isso é o **texto-base**, a única parte que você manda. O servidor acrescenta o resto:

- no chamado: `<texto-base>` + nova linha + `ID FAQ: <código do FAQ>`;
- no FAQ: `<árvore de rastreio>:` sozinha na primeira linha, depois `<texto-base> [<chamado>]`
  (formato acertado com o usuário em 01/09/2026; antes a árvore ia na mesma linha do texto).
  Com rastreio 0 o item sai sem a linha da árvore.

Exemplos reais (FAQ 212, release 4.1.15.18), no formato antigo de uma linha só:

```
Com.Exterior > Ct. Câmbio: Descrição do Problema: Ao realizar um contrato de
cambio pela tela nova, ao realizar a conversão do valor e ele entra no banco em
real, o sistema está preenchendo o centro de custo como 'CONTAS A PAGAR'
Solução: Removido informação do centro de custo que ficava de forma fixa dentro
do sistema. [19430127]
```

```
Fiscal > MDF-e > Novo/Editar > Integração CIOT:
Solicitação: Verificar a possibilidade do sistema efetuar o calculo entre a
distância do ponto de carregamento e descarregamento.
Implementação: Implementado dentro do sistema opção de consultar a distancia
entre o ponto de origem e destino utilizado dentro do CIOT, para tal consultar
é necessário ter latitude e longitude de origem e destino. [19430893]
```

O prefixo "tela > submenu" desses exemplos é a árvore de rastreio (`/atendimentos/rastreios`,
subindo por `master` até a raiz) — por isso ele vem do rastreio do chamado, nunca de um caminho
de menu escolhido a mão.

## Como escrever bem o texto-base

- **Descrição do Problema / Solicitação**: o sintoma ou o pedido, na linguagem de quem usa a
  tela. Sem nome de unit, de método ou de tabela.
- **Solução / Implementação**: o que mudou para o usuário. Tirado do que a timeline diz que foi
  feito — anotação do programador, finalização, tarefa concluída. Não invente o que o chamado
  não diz.
- Uma frase ou duas de cada lado. O leitor é o cliente lendo a novidade da versão.
- Correção ou evolução se decide pelo **conteúdo**: o chamado 19434113 estava marcado
  `Evolutivos` e descrevia uma correção de reservas de estoque órfãs.

## Estilo 8405 — NÃO usar (só para reconhecer)

Parágrafo corrido, voz passiva, sem os rótulos e quase sempre sem `[<chamado>]`:

```
Realizada correção no processo de importação de NFS-e própria, eliminando erros
que ocorriam durante a leitura de arquivos XML. O ajuste corrige as
inconsistências identificadas na importação de XMLs, incluindo o tratamento dos
erros relacionados ao UF_PESS, permitindo que a importação seja concluída
corretamente.
```

Na amostra, 67 dos 108 itens não citavam chamado nenhum — quase todos deste estilo. Por isso a
ausência de `[<chamado>]` não prova que o chamado ficou fora do FAQ; o dedup do servidor só
enxerga o que esta skill (ou o 8856) escreveu.

## O vínculo `ID FAQ:` no chamado

Não é invenção da skill: a equipe já anotava chamados à mão no formato `"<texto> Id FAQ: <n>"`
(chamado de teste 19419541). A prévia pula o chamado que já tem `ID FAQ:` em qualquer ponto da
timeline, não só na última entrada.
