---
name: redsis-ftp
description: Acessa o servidor de arquivos da Redsis (arquivos.redsis.com.br/ftp/, o "FTP" das pastas de cada pessoa) pelo servidor MCP — lista qualquer pasta, baixa qualquer arquivo para a máquina e envia para qualquer pasta um pacote gerado no servidor ou um arquivo da máquina de quem pede. Quem pede não precisa de credencial nem de cliente de FTP. Use quando o pedido for "o que tem na pasta da Juliana no FTP", "lista o FTP", "baixa do FTP o arquivo X da pasta do Cordeiro", "sobe esse arquivo para a pasta do Claude no FTP", "manda o pacote da integração para a pasta da Juliana" ou "copia do FTP da pasta A para a pasta B". É também a peça que as outras skills usam para mexer no FTP (a redsis-gerar-integracao entrega o pacote por ela). NAO apaga nem renomeia arquivo no FTP, NAO cria pasta e NAO sobrescreve arquivo sem o "pode" de quem pediu.
argument-hint: "[listar|baixar|enviar] [caminho no FTP] [arquivo]"
allowed-tools: mcp__redsis__redsis_ftp_listar mcp__plugin_redsis_redsis__redsis_ftp_listar mcp__redsis__redsis_ftp_baixar mcp__plugin_redsis_redsis__redsis_ftp_baixar mcp__redsis__redsis_ftp_limpar mcp__plugin_redsis_redsis__redsis_ftp_limpar mcp__redsis__redsis_exe_status mcp__plugin_redsis_redsis__redsis_exe_status
---

# Servidor de arquivos da Redsis

O endereço `https://arquivos.redsis.com.br/ftp/` **não é FTP**: é WebDAV do IIS. Cada pessoa
tem uma pasta na raiz (`JULIANA`, `CORDEIRO`, `CLAUDE`...); o nome não diferencia maiúscula.
Tudo sai do servidor da Redsis, pelo job `Redsis Exe`, porque só a conta do Jenkins abre a
credencial. Quem pede não tem senha nenhuma, e não precisa.

| Ferramenta | Faz | Escreve no FTP? |
|---|---|---|
| `redsis_ftp_listar(caminho)` | subpastas e arquivos, com tamanho e data; `caminho` vazio é a raiz | não |
| `redsis_ftp_baixar(caminho)` | traz o arquivo para o servidor e devolve link, tamanho e `sha256` | não |
| `redsis_ftp_enviar(destino, origem, sha256)` | sobe a `origem` no `destino` | **sim** |
| `redsis_ftp_limpar(identificador)` | apaga do servidor a cópia de um `ftp-<hex>` | não |
| `redsis_exe_status(identificador='ftp-<hex>', pedido)` | acompanha quando a espera de ~45 s não bastou | não |

`caminho` e `destino` são relativos a `/ftp/`, com `/`: `JULIANA`, `CORDEIRO/2026/banco.rar`.
Sem `..`, sem `\ : * ? " < > |`. Na dúvida sobre o nome da pasta, **liste antes**.

## Listar

`redsis_ftp_listar(caminho="JULIANA")`. A resposta já é a tabela: mostre como veio. Pasta
que não existe volta `FALHOU` com o motivo.

## Baixar para a máquina

1. `redsis_ftp_baixar(caminho="CORDEIRO/banco.rar")` — volta `BAIXADO` com o identificador
   `ftp-<hex>`, o `sha256` e o link.
2. Baixe pelo link com o token do MCP, na pasta que a pessoa pediu (sem pasta dita, pergunte):

   ```powershell
   $h = @{ Authorization = "Bearer $env:REDSIS_MCP_TOKEN" }
   Invoke-WebRequest -UseBasicParsing -Headers $h -Uri '<link>' -OutFile '<pasta>\<nome>'
   (Get-FileHash '<pasta>\<nome>' -Algorithm SHA256).Hash
   ```

3. Confira o `sha256`. Igual: `redsis_ftp_limpar('<ftp-hex>')`. Diferente: baixe de novo —
   arquivo cortado não é arquivo baixado.

## Enviar

A `origem` é sempre algo que **já está no servidor**:

| Origem | Como chega ao servidor |
|---|---|
| pacote do exe ou da integração, ex. `Integracao_06` | `redsis_exe_gerar(..., sem_anexar=true)` deixou `PACOTE_PRONTO` |
| arquivo da máquina de quem pede | PUT na rota `/ftp-entrada/<nome>` (abaixo); devolve `ftp-<hex>` |
| arquivo de outra pasta do FTP | `redsis_ftp_baixar` devolveu `ftp-<hex>` |

Arquivo da máquina sobe assim, e a resposta traz `identificador` e `sha256`. Confira o
`sha256` contra o arquivo local antes de seguir:

```powershell
$h = @{ Authorization = "Bearer $env:REDSIS_MCP_TOKEN" }
$r = Invoke-RestMethod -Method Put -Headers $h -InFile '<arquivo>' `
    -Uri "https://mcp.redsis.com.br/ftp-entrada/$([Uri]::EscapeDataString('<nome>'))"
$r; (Get-FileHash '<arquivo>' -Algorithm SHA256).Hash
```

Depois `redsis_ftp_enviar(destino="CLAUDE/", origem="<identificador>")`. `destino` terminado
em `/` usa o nome da origem; com nome, renomeia no destino.

> [!danger] Sobrescrever não se desfaz
> Arquivo **novo** sobe direto e volta `OK`. Se o destino **já existe**, nada sobe: volta
> `DRY_RUN` com tamanho de lá, arquivo e `sha256` daqui. Mostre isso e pergunte. **Só com o
> "pode"** de quem pediu, repita a mesma chamada com `sha256=<o do DRY_RUN>`. "Sobe lá" no
> pedido não é "pode" para sobrescrever: o "pode" vem depois de a pessoa ver o `DRY_RUN`.

**Só `OK` prova o envio**: o servidor confere o tamanho que ficou no FTP. Pasta de destino
que não existe volta `FALHOU` — criar pasta no lugar de alguém não é decisão desta skill.
Terminado o envio de um `ftp-<hex>`, `redsis_ftp_limpar` nele.

## Quando outra skill usa esta

A skill que chama decide **o que** sobe e **para onde**; o procedimento, a trava do
sobrescrever e a conferência são estes. Ela não repete a regra: aponta para cá.

## O que esta skill não faz

Não apaga, não move e não renomeia arquivo no FTP; não cria pasta. Não lê nem escreve no SAC
— anexo de chamado é de `redsis-exe` e `redsis-cenarios`.
