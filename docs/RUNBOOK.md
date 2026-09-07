# Runbook — PDV parado na loja

> Ordem de eliminação para terminal Windows de ponto de venda.
> A regra é: **isolar antes de mexer.** Cada passo elimina uma camada.
> Nunca comece reinstalando. Reinstalar é o último recurso, não o primeiro.

---

## Passo 0 — Antes de tocar em qualquer coisa (2 min)

Pergunte à loja, nesta ordem:

1. **Quantos caixas estão com problema?** Um só → terminal. Todos → rede ou servidor.
2. **Desde quando?** Se começou num horário exato, algo mudou naquele horário.
3. **O que mudou?** Queda de energia, atualização, troca de equipamento, chuva forte.
4. **Dá pra vender de algum jeito?** Se sim, o chamado é grave; se não, é crítico — muda a prioridade.

Rode o `Teste-Rapido-Loja.bat` **pelo pessoal da loja** enquanto você ainda está a caminho ou conectando.
Você ganha 10 minutos de diagnóstico sem gastar os seus.

---

## Passo 1 — O terminal enxerga a própria rede? (3 min)

```powershell
.\Diagnostico-PDV.ps1 -ServidorLoja <ip-do-servidor>
```

Leia o relatório de cima para baixo. O bloco **Rede** responde:

| Sintoma no relatório | Onde está o problema |
|---|---|
| Interface caída / sem IP | Cabo, porta do switch, placa. Físico. |
| IP `169.254.x.x` | Não pegou DHCP. Roteador ou servidor DHCP. |
| IP ok, ping no gateway falha | Switch ou cabeamento entre terminal e roteador. |
| Ping no gateway ok, ping em `8.8.8.8` falha | Link da operadora. Não é você. |
| Ping em `8.8.8.8` ok, DNS falha | Configuração de DNS. Não é o link. |

> **A distinção que mais economiza tempo:** ping por IP funciona e por nome não → é DNS.
> Nunca abra chamado com a operadora antes de descartar isso.

---

## Passo 2 — O terminal enxerga a retaguarda? (3 min)

O relatório testa `tcp/1433` (SQL), `tcp/445` (SMB) e `tcp/135` (RPC) contra o servidor.

- **Ping responde mas 1433 fechada** → o servidor está no ar, o SQL não.
  Vá até o servidor: serviço `MSSQLSERVER` (ou instância nomeada), firewall, SQL Browser.
- **Ping não responde** → o servidor caiu ou está isolado. Trate como incidente de loja inteira.
- **Tudo aberto mas o PDV reclama de conexão** → o problema é credencial, string de conexão ou instância errada, não rede.

No servidor, rode `Checkup-Loja.sql`, blocos **4 (bloqueios)** e **5 (sessões)**.
Se há bloqueio com espera alta, um caixa travou o outro — o PDV não está "lento", está esperando.

---

## Passo 3 — O terminal está saudável por dentro? (5 min)

Blocos **Hardware**, **Serviços** e **Eventos** do relatório.

**Disco cheio** é a causa silenciosa mais comum de PDV corrompido.
Abaixo de 3 GB livres, trate como crítico mesmo que o caixa ainda esteja vendendo.

**Serviço parado:**

```powershell
.\Recuperar-Servicos.ps1 -Servicos "Spooler","<servico-do-pdv>" -WhatIf   # simula
.\Recuperar-Servicos.ps1 -Servicos "Spooler","<servico-do-pdv>"           # executa após confirmar
```

O script grava log em `C:\ProgramData\KitPDV\logs` com o estado anterior de cada serviço.
Esse log é a sua defesa quando perguntarem o que foi alterado.

> **Serviço que sobe e cai de novo em minutos não é problema de serviço.**
> É dependência: banco, licença, disco ou permissão. Vá ao Visualizador de Eventos.

---

## Passo 4 — Cupom não sai (3 min)

Bloco **Impressão** do relatório.

1. Impressora `OFFLINE` → físico primeiro: cabo, energia, papel, tampa.
2. Fila com trabalhos travados → pare o Spooler, limpe, suba:

```powershell
Stop-Service Spooler
Remove-Item "C:\Windows\System32\spool\PRINTERS\*" -Force
Start-Service Spooler
```

3. Impressora fiscal em porta COM → confira o bloco **Periféricos**.
   Porta COM que sumiu geralmente é driver ou o conversor USB-Serial que soltou.

---

## Passo 5 — Ainda não achou

Empacote tudo e escale com evidência, não com narrativa:

```powershell
.\Coletar-Evidencias.ps1 -Chamado INC0012345
```

O `.zip` na área de trabalho contém rede, serviços, eventos, impressoras, discos e programas.
Anexe no chamado. **Chamado com evidência anexada volta menos.**

---

## Manutenção preventiva — o que evita 80% desses chamados

| Frequência | Ação |
|---|---|
| Diária | `Diagnostico-PDV.ps1` agendado, relatório num compartilhamento |
| Semanal | Revisar terminais com disco < 15 GB e uptime > 15 dias |
| Semanal | `Checkup-Loja.sql` bloco 2 — nenhuma base sem backup em 24h |
| Mensal | `Checkup-Loja.sql` bloco 7 — índices, **rebuild fora do horário de loja** |
| Sempre | Sincronismo de hora. Hora errada quebra fiscal e conciliação. |

### Agendar o diagnóstico diário

```powershell
$acao    = New-ScheduledTaskAction -Execute "powershell.exe" `
           -Argument '-NoProfile -ExecutionPolicy Bypass -File "C:\KitPDV\Diagnostico-PDV.ps1" -ServidorLoja 192.168.0.10 -Saida "\\servidor\diagnosticos"'
$gatilho = New-ScheduledTaskTrigger -Daily -At 7:00am
Register-ScheduledTask -TaskName "KitPDV-Diagnostico" -Action $acao -Trigger $gatilho -RunLevel Highest
```

---

## Regras da casa

- **Nunca** rode `REBUILD` de índice, `CHECKDB` pesado ou reinício de SQL em horário de loja.
- **Nunca** apague log ou base "pra liberar espaço" sem backup confirmado.
- **Sempre** registre o estado anterior antes de alterar. O log é o rollback.
- **Sempre** teste em um terminal antes de aplicar em todos.
