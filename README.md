# redsis-tools — ponteiro do marketplace

Este repositorio **nao** contem as skills nem as bases de conhecimento da Redsis. Ele tem
um arquivo so, de menos de 1 KB: `.claude-plugin/marketplace.json`.

Ele existe por um motivo unico: a aba de plugins do Claude Code aceita marketplace apenas
de `github.com`. Colar a URL do servidor da Redsis direto na aba devolve *"este host nao e
suportado"*. Pelo CLI a URL do servidor funciona normalmente — a restricao e da interface.

O plugin em si (`redsis-<versao>.zip`, com as skills) e as duas bases de conhecimento
continuam saindo do servidor da Redsis, autenticados pelo token. Nada disso passa pelo
GitHub.

## Instalar

Cole na aba de plugins do Claude Code:

```
RedsisDevCordeiro/claude-plugins
```

Depois abra o `redsis-tools`, clique em **Install** no plugin `redsis` e, no menu do
marketplace, em **Enable auto-update**.

Ou, se preferir uma linha so e sem aba nenhuma:

```powershell
& ([scriptblock]::Create((irm https://mcp.redsis.com.br/plugin/Instalar.ps1).TrimStart([char]0xFEFF))) -Token '<o token>'
```

Essa forma tambem grava o token, liga o auto-update e pre-aprova as ferramentas do MCP.

## Manutencao

O `marketplace.json` daqui e **gerado**, nao editado a mao: ele espelha o catalogo que o
`scripts/Publicar-Plugin.ps1` produz, e muda a cada publicacao, porque a versao e o sha256
do zip mudam junto. Editar a mao so cria divergencia.
