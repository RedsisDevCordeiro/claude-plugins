# O laudo — modelo e regras de marcação

Lido pela `redsis-analise` na Etapa 7. O número do chamado vai na **primeira linha**: o
`redsis_cenarios_anexar` recusa título sem ele.

```markdown
# Laudo de análise — chamado <n> — <assunto>

**Referência do fonte:** origin/<branch> · **Banco:** <nome do arquivo>
**Escopo:** análise de causa. A correção não foi aplicada.

## Sintoma, provado
<o que foi observado, com a consulta e a saída literais>

## Evidência
<a tabela origem × destino>

## O banco foi descartado?
<gatilhos/procedures/views que citam a coluna, e o que cada um faz — ou "nenhum">

## Pontos de escrita examinados
| Local | Condição que grava o valor | Veredito |
|---|---|---|
| `arquivo.pas:120` | ... | **compatível** |
| `outro.pas:88` | ... | incompatível — <a evidência que derruba> |

## Causa
`arquivo.pas:120` — <o mecanismo, em uma frase>  ·  **provado** | **hipótese**

## Correção sugerida (não aplicada)
<trecho atual × trecho sugerido, e o que ela afeta além deste caso>

## O que não foi possível provar
<o que falta: log, banco de antes, versão do exe do cliente>
```

## Provado e hipótese não se misturam

Cada afirmação do laudo carrega uma das duas marcas. **Provado** é o que tem consulta com
saída, ou `arquivo:linha` que qualquer um relê. **Hipótese** vem com o que falta para virar
prova. Laudo que apresenta hipótese como fato manda o programador corrigir o lugar errado — é
pior do que laudo nenhum.

Quando a evidência não fecha, a resposta correta é **dizer o que falta**, não eleger o
suspeito mais plausível.

## O que não entra

- usuário e senha do banco;
- recorte de dado do cliente além do necessário para provar o sintoma — o laudo vai para o
  chamado, não para o Git nem para a base de conhecimento;
- sem chamado, sem número na primeira linha: o laudo fica só nesta máquina.

Na comparação entre duas referências ("já está corrigido na main?"), a seção **Pontos de
escrita examinados** ganha uma coluna por referência, e a **Causa** diz em qual delas o
trecho ainda existe.
