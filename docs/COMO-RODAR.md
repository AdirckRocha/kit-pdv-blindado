# Como rodar em um terminal

Guia para executar o diagnóstico num terminal Windows de ponto de venda, do zero.

---

## Antes de começar

| Requisito | Como conferir |
|---|---|
| Windows 8 ou superior | `winver` |
| PowerShell 5.1 ou superior | `$PSVersionTable.PSVersion` |
| Nada mais | Sem instalação, sem dependência, sem internet obrigatória |

> **Windows 7 / PowerShell 2.0:** a seção de rede usa comandos que não existem nessas versões e vai falhar. O resto do diagnóstico continua funcionando.

Nenhum modo exige administrador, **exceto** `-Corrigir`.

---

## Passo 1 — Levar o kit até o terminal

Escolha o que funcionar no seu ambiente. As três dão no mesmo.

**A. Um arquivo só** (recomendado)

Baixe `Rodar-Diagnostico.bat` do repositório e dê duplo clique no terminal. Ele baixa a versão atual, descobre o ambiente e gera o relatório. Se a rede da loja bloquear o GitHub, ele avisa e explica a alternativa.

**B. Baixar pelo PowerShell** (se preferir controlar cada passo)

```powershell
$dest = "$env:TEMP\KitPDV"
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$url = "https://raw.githubusercontent.com/AdirckRocha/kit-pdv-blindado/main/scripts/Diagnostico-PDV.ps1"
Invoke-WebRequest -Uri $url -OutFile "$dest\Diagnostico-PDV.ps1" -UseBasicParsing
```

Se a rede da loja usa proxy, ou se a saída HTTPS é filtrada, este passo falha. Use C ou D.

**C. Baixar o ZIP pelo navegador**

Abra `github.com/AdirckRocha/kit-pdv-blindado`, botão verde **Code** → **Download ZIP**, e extraia numa pasta temporária.

**D. Copiar de um compartilhamento de rede**

```powershell
Copy-Item "\\servidor\ti\KitPDV\*" "$env:TEMP\KitPDV\" -Recurse -Force
```

---

## Passo 2 — Executar

Rode como diagnóstico puro primeiro. Ele não altera nada.

```powershell
cd "$env:TEMP\KitPDV"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Diagnostico-PDV.ps1" -ServidorLoja 192.168.0.10
```

Troque `192.168.0.10` pelo IP ou nome do servidor da loja. Sem esse parâmetro, os testes de porta 1433, 445 e 135 não são executados.

Informe também os serviços do seu PDV, se souber os nomes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Diagnostico-PDV.ps1" `
    -ServidorLoja SRVLOJA01 `
    -ServicosCriticos "Spooler","W32Time","<servico-do-seu-pdv>"
```

Para descobrir o nome exato do serviço:

```powershell
Get-Service | Where-Object DisplayName -like "*<nome do sistema>*"
```

---

## Passo 3 — Ler o resultado

O relatório HTML abre sozinho e fica na área de trabalho. No console aparece o resumo:

```
Veredito: CRITICO  (1 falha(s), 2 atencao)
Relatorio: C:\Users\...\Desktop\Diagnostico_<TERMINAL>_<data>.html
```

| Veredito | Significa |
|---|---|
| **SAUDÁVEL** | Nenhuma verificação falhou |
| **ATENÇÃO** | Nada quebrado agora, mas algo vai quebrar |
| **CRÍTICO** | Pelo menos uma verificação falhou |

Cada linha em falha traz, logo abaixo, o que fazer a seguir.

Para gravar num compartilhamento em vez da área de trabalho:

```powershell
-Saida "\\servidor\diagnosticos"
```

---

## Modos de execução

| Modo | O que faz | Precisa de admin |
|---|---|---|
| *(padrão)* | Só diagnostica. Não altera nada. | Não |
| `-Simular` | Mostra o que a correção faria. Não altera nada. | Não |
| `-Corrigir` | Executa as correções da lista branca. | **Sim** |
| `-Anonimizar` | Mascara máquina, usuário, serial, servidor e IPs privados. | Não |

### O que `-Corrigir` pode fazer

Apenas duas ações, escolhidas por um critério: **o dano possível tem que ser menor que o dano existente.**

- **Subir serviço crítico parado** — já está parado, não há o que piorar.
- **Destravar fila de impressão** — para o spooler, limpa a fila, sobe de novo.

Tudo o mais o relatório apenas sugere; nada é executado sozinho.

O estado anterior de cada alteração vai para `C:\ProgramData\KitPDV\logs`, com a marca `ROLLBACK-INFO`. É o que permite desfazer e é o que você mostra quando perguntarem o que foi mexido.

> Rode `-Simular` antes de `-Corrigir`. Sempre.

### Anonimizar antes de compartilhar

Para anexar o relatório em chamado de fornecedor sem expor a rede:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ".\Diagnostico-PDV.ps1" -ServidorLoja SRVLOJA01 -Anonimizar
```

O arquivo sai como `Diagnostico_ANONIMO_<data>.html`. Nome da máquina vira `TERMINAL-XX`, o servidor vira `SERVIDOR-XX`, o serial vira `********` e IPs privados perdem os dois últimos octetos. Resolvedores públicos como `8.8.8.8` continuam legíveis, porque escondê-los só atrapalharia a leitura.

---

## Quando dá errado

| Mensagem | Causa | Saída |
|---|---|---|
| `não pode ser carregado porque a execução de scripts foi desabilitada` | Política de execução | Use `powershell -ExecutionPolicy Bypass -File ...` como acima. Se a política vier de GPO do domínio, peça exceção ao time de segurança — não contorne. |
| `O termo 'Get-NetAdapter' não é reconhecido` | Windows 7 ou PowerShell 2.0 | A seção de rede não roda nessa versão. O resto do relatório continua válido. |
| Antivírus bloqueia o script | Política de endpoint | Não desative o antivírus. Peça liberação do caminho, ou rode de um compartilhamento já autorizado. |
| `Acesso negado` com `-Corrigir` | Sem privilégio | Abra o PowerShell como Administrador. Sem admin ele recusa e diz por quê, em vez de falhar pela metade. |
| Porta 1433 `fechada/filtrada` num roteador | Comportamento correto | Roteador não é SQL Server. Só é falha real se o alvo for mesmo o servidor da loja. |

---

## Checkup do banco da loja

`sql/Checkup-Loja.sql` roda no servidor, não no terminal. Abra no SSMS conectado ao banco da retaguarda e execute. São sete blocos somente leitura: identificação, idade do backup, arquivos, bloqueios no momento, sessões por terminal, jobs que falharam e fragmentação de índice.

> Nunca rode `REBUILD` de índice, `CHECKDB` pesado ou reinício do SQL em horário de loja. O bloco 7 aponta o que reconstruir; **quando** reconstruir é decisão sua.

---

## Deixar rodando todo dia

```powershell
$acao = New-ScheduledTaskAction -Execute "powershell.exe" `
        -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\KitPDV\Diagnostico-PDV.ps1" -ServidorLoja 192.168.0.10 -Saida "\\servidor\diagnosticos"'
$gatilho = New-ScheduledTaskTrigger -Daily -At 7:00am
Register-ScheduledTask -TaskName "KitPDV-Diagnostico" -Action $acao -Trigger $gatilho -RunLevel Highest
```

Agende antes de a loja abrir. O relatório vai estar pronto quando o primeiro caixa ligar.
