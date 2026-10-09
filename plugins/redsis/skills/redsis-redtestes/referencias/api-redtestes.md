# O que o executor do RedTestes aceita

Resumo do que o RedTestes (Central de Testes) executa, levantado do fonte em 08/10/2026,
branch `Automacao/redtestes`. **Quando divergir do fonte, vale o fonte**:

- API declarada: `Projects/Extras/RedTestes/Studio.AI.pas`, constante `ApiDeclarations` (é
  o mesmo texto que o editor do RedTestes usa para completar código);
- comportamento real: `Projects/Extras/RedRoutineHost/runtime/runtime-core.mjs`,
  `testcomplete-values.mjs`, `host-services.mjs` e `ado-adapter.mjs`;
- importação e metadados: `Projects/Extras/RedTestes/Studio.Repository.pas`
  (`ScriptMetadata`, `DetectEntry`, `IsRoutineSource`, `ImportScript`, `ScanProject`).

## O script

JavaScript ES2017 compatível com o TestComplete, executado em QuickJS. Não há Node.js, DOM
nem rede. CommonJS: `require("UTEIS")` resolve `UTEIS.js` **da mesma pasta**, sem caminho.
Tudo síncrono: `async`, `Promise` e `await` são recusados.

Na importação o RedTestes **lê o texto, sem executar**:

| Lê | De onde | Para quê |
|---|---|---|
| base e módulo | primeira chamada literal `funcoesIniciais("NOME", "REDSISnn", "Modulo")` não comentada | escolhe o ambiente (`REDSISnn`) e o grupo (módulo) |
| descrição | primeiro `//@descricao: ...` (até 400 caracteres) | texto da rotina na biblioteca |
| função inicial | `module.exports.X = X`, preferindo `X` igual ao nome do arquivo | o que roda |
| rotina ou helper | tem `funcoesIniciais` literal, ou exporta o próprio nome com até 2 exports | helper não aparece como rotina |

Nome do arquivo: `^[A-Za-z0-9_$-]+\.js$`, e para virar função inicial precisa ser
identificador JavaScript (começar por letra). A base precisa casar `^[A-Z][A-Z0-9_]{0,63}$`.

## Aprovada, Concluída ou Falhou

- **Falhou**: qualquer `Log.Error`, exceção não tratada ou checkpoint que não passou.
- **Concluída**: terminou sem erro e **sem nenhum checkpoint contado**.
- **Aprovada**: terminou sem erro com pelo menos um checkpoint contado.

Só conta `aqObject.CheckProperty` chamado **no arquivo principal da rotina**. `Log.Checkpoint`
e as verificações feitas dentro de helpers (`uteis.*`) **não contam**. Um script gerado que
só usa `Log.Checkpoint` nunca sai "Aprovada".

Depois da primeira falha, toda ação de tela lança "Acao interrompida apos uma falha": o
`finally` só registra log, não clica.

## Verificações

```js
aqObject.CheckProperty(objeto, "Propriedade", cmpEqual, esperado [, caseSensitive]);
```

Condições: `cmpEqual 0, cmpNotEqual 1, cmpGreater 2, cmpLess 3, cmpGreaterOrEqual 4,
cmpLessOrEqual 5, cmpContains 6, cmpNotContains 7, cmpStartsWith 8, cmpNotStartsWith 9,
cmpEndsWith 10, cmpNotEndsWith 11`. Não há expressão regular.

- O **tipo do esperado** manda na conversão: esperado número lê `"1.234,56"` como pt-BR;
  esperado texto de data (`"23/09/2026"`) compara como data; esperado `null` nunca passa.
- Propriedade indexada vale como texto: `"wCellText(0,\"TOTAL\")"`, `"wValue(0,\"COD\")"`.
- **Valor do banco** também vira checkpoint contado — o alvo pode ser objeto JavaScript
  simples, e a propriedade é lida direto dele:

```js
var total = sql.totalDocumento(cod); // helper existente, ou consulta ADO
aqObject.CheckProperty({TOTALG_DOC: total}, "TOTALG_DOC", cmpEqual, 1234.56);
```

## Controles da tela

Endereço pelo NameMapping do TestComplete: `Aliases.Redsis.<Formulario>.<...>.<Controle>`.
Alias desconhecido: o executor tenta o par equivalente `FormMenu.Painel_Central.pcPrincipal`
⇄ `wndMenu.Panel.PageControl`, depois o nome exato do componente VCL sob um pai visível (com
aviso "Alias fora do mapa"), e só então falha. `pai.VCLObject("NomeDoComponente")` e
`pai.WaitVCLObject("Nome", ms)` endereçam pelo `Name` do componente Delphi — o nome que
está no `.dfm`.

Propriedades lidas: `Visible, VisibleOnScreen, Enabled, Focused, Text, wText, Caption,
WndCaption, Name, ClassName, Checked, wChecked, wState, ItemIndex, wItemIndex, wItemCount,
wItemList, ImageIndex, ReadOnly, Handle, wButtonCount, wTabCount, wFocusedTab, wPosition,
wDate, Width, Height, Left, Top, GridColumns, GridSelection, wRowCount, wColumnCount`;
indexadas `wButtonText(i), wEnabled(i), wVisible(i), wValue(l,c), wCellText(l,c),
wColumnText(c), CellTextByValue(campo,valor,coluna)`.

Métodos: `Click, ClickR, DblClick, ClickButton, SetText, Keys, ClickItem, ClickItemXY,
ClickTab, Drag, MouseWheel, ClickCell, ClickCellByValue, DblClickCellByValue, ClickColumn,
Exists, Close, WaitProperty(nome, valor, ms=10000), WaitAliasChild(nome, ms),
VCLObject, WaitVCLObject, PopupMenu.Click(caminho), MainMenu.Click(caminho)`.

- Atribuição só em `wPosition` e `wDate` (`campo.wDate = "23/09/2026"`); o resto é
  `SetText`/`Keys`. `SetText` exige texto: `undefined` vindo de helper que não achou linha
  falha com "SetText recebeu valor ausente".
- `Keys`: `[Enter] [Tab] [Esc] [BS] [Del] [Ins] [Home] [End] [Left] [Right] [Up] [Down]
  [PgUp] [PgDn] [F1]..[F12]`; `^` Ctrl, `!` Shift, `~` Alt (`"^a"`).
- Menu: `menu.MainMenu.Click("Ferramentas|[4]")` — `|` separa níveis, `[n]` é o item visível
  de índice n (separador conta), legenda sem o `&`; legenda ambígua é erro.
- Grade: linha base zero entre as linhas carregadas; `ClickCellByValue(campo, texto,
  coluna)` exige valor único entre as visíveis. **Nunca** trocar ambiguidade por clique em
  coordenada.
- Espera automática de 10 s por controle, estendida enquanto o Redsis está ocupado.

## Banco

ADO do TestComplete, pelos helpers de `SQL.js` (143 funções: `cliente()`, `fornecedores()`,
`material(tipo)`, `estabelecimento(cod, tipo)`, `chapasDisponiveis()`, `versaoERP()`...) e
`uteis.comandoSQL(sql)` para escrita. Consulta crua:

```js
// o mesmo padrão dos helpers de SQL.js: conexaoBD já abre a conexão
var con = uteis.conexaoBD("C:\\TESTES\\BANCOS\\" + Project.Variables.firebird + "\\" +
  Project.Variables.empresa + ".RED;");
var rs = con.Execute_("SELECT TOTALG_DOC FROM DOC WHERE COD_DOC = " + cod);
var total = rs.EOF ? undefined : rs.Fields.Item("TOTALG_DOC").Value;
con.Close();
```

`Project.Variables.empresa` é a base passada em `funcoesIniciais`; `firebird` vem do
ambiente. Valor interpolado na SQL é só número ou texto que o próprio script gerou.

Cada execução trabalha numa **cópia nova** da base do ambiente; o caminho
`C:\TESTES\BANCOS\5_0\REDSISnn.RED` é redirecionado para a cópia. Base fora da lista é
recusada ("Banco fora da lista de copias permitidas"). Limites: 100 mil linhas, 1 milhão de
células, 120 s por comando (até 300 s). Charset NONE, bytes Windows-1252.

## Valores e utilidades

- `aqString`: só `Find, GetLength, Compare, Remove, Replace`.
- `aqConvert`: `StrToFloat, FloatToStr, CurrencyToStr, DateTimeToFormatStr, DateTimeToStr,
  IntToStr, StrToDateTime, TimeIntervalToStr`.
- `aqDateTime`: `Now, Today, Get*, SetDate*Elements, Compare, TimeInterval, AddDays,
  AddMonths, AddHours, AddMinutes, AddSeconds`.
- `Log.Message/Warning/Error/Checkpoint/Picture`, `Delay(ms)`,
  `RedsisAutomation.step(id, rotulo, () => {...})` (passo nomeado na linha do tempo; id até
  128, rótulo até 256 caracteres, callback síncrono).
- Qualquer outro membro lança **"API nao suportada nesta entrega: X.Y"**.
  `aqEnvironment, aqUtils, DDT, Regions, NameMapping, Runner, WScript` não existem.
- `BuiltIn.InputBox` só responde com o que o ambiente configurou; não há pausa para um humano.

## O que não cabe num script

- passo que depende de olho humano: conferir impressão, PDF, e-mail recebido, retorno da
  SEFAZ em homologação, certificado digital;
- `alterarDLL()`, reiniciar o computador, escrever em Program Files ou na base original;
- HTTP e `Sys.Restart` sem o ambiente liberar;
- senha no JavaScript — login vem do ambiente (`UsuarioTeste`, `Password2`).

O "Testar na mão" do RedTestes abre o Redsis numa cópia da base para uma pessoa; ele não
executa passos escritos. Cenário de natureza manual fica fora do script, listado na entrega.
