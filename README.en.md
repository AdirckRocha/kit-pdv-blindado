# Kit PDV Blindado — Retail POS Diagnostics Toolkit

Diagnostic and maintenance tooling for Windows point-of-sale terminals in retail environments.

Written from the perspective of the person who answers the store's support call: the goal is to **locate the fault in minutes**, not to produce another report nobody reads. Read-only by default, no installation, no internet access required.

**[→ Sample report](docs/exemplo-relatorio.html)** · **[→ Triage runbook (Portuguese)](docs/RUNBOOK.md)** · [Português](README.md)

![Diagnostic report produced by the toolkit](docs/exemplo-relatorio.png)

*Report produced by `Diagnostico-PDV.ps1`. Sample data is fictional.*

---

## Contents

| File | What it does | Modifies anything? |
|---|---|---|
| [`scripts/Diagnostico-PDV.ps1`](scripts/Diagnostico-PDV.ps1) | Full terminal health check, HTML report with a traffic-light verdict | No |
| [`scripts/Teste-Rapido-Loja.bat`](scripts/Teste-Rapido-Loja.bat) | Quick test store staff run themselves before opening a ticket | No |
| [`scripts/Coletar-Evidencias.ps1`](scripts/Coletar-Evidencias.ps1) | Packages evidence into a `.zip` to attach to a ticket | No |
| [`scripts/Recuperar-Servicos.ps1`](scripts/Recuperar-Servicos.ps1) | Starts stopped services, with typed confirmation and a rollback log | **Yes** — asks for confirmation |
| [`sql/Checkup-Loja.sql`](sql/Checkup-Loja.sql) | 7 SQL Server checks: backup age, blocking, failed jobs, index fragmentation | No |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | Elimination order for a dead POS terminal | — |

## What the diagnostic checks

Machine identity and uptime · memory and disk space · critical services · printers, print queue and COM ports (fiscal printer, scale, cash drawer) · network interface, IP, gateway and DNS · internet reachability · store server reachability on ports 1433 / 445 / 135 · time synchronisation · critical event log entries grouped by source.

Output is a single HTML file with a **HEALTHY / WARNING / CRITICAL** verdict and, for every failed check, the next action to take.

## Quick start

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\scripts\Diagnostico-PDV.ps1 -ServidorLoja 192.168.0.10

.\scripts\Diagnostico-PDV.ps1 -ServidorLoja SRVLOJA01 `
    -ServicosCriticos "Spooler","W32Time","<your-pos-service>"
```

## Requirements

Windows 10/11 or Windows Server · PowerShell 5.1+ · administrator rights for `Recuperar-Servicos.ps1` only · no external dependencies.

## Safety

Every script except `Recuperar-Servicos.ps1` is **read-only**. No script collects passwords, card data or sales data. `Recuperar-Servicos.ps1` requires typed confirmation, supports `-WhatIf`, and records each service's previous state to `C:\ProgramData\KitPDV\logs` so changes can be audited and reversed.

> Documentation and code comments are in Brazilian Portuguese, since the tooling targets Brazilian retail operations.

## License

MIT — see [LICENSE](LICENSE).
