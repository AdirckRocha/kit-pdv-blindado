/* =========================================================================
   KIT PDV BLINDADO - CHECKUP DE BANCO DA LOJA (SQL Server)
   -------------------------------------------------------------------------
   Somente leitura. Nenhum comando altera dados ou configuracao.
   Rode no servidor da loja, conectado ao banco da retaguarda.
   Cada bloco responde uma pergunta que aparece em chamado real.
   ========================================================================= */

SET NOCOUNT ON;

/* -------------------------------------------------------------------------
   1. IDENTIFICACAO - qual instancia estou olhando?
   ------------------------------------------------------------------------- */
SELECT
    'IDENTIFICACAO'                       AS bloco,
    @@SERVERNAME                          AS servidor,
    SERVERPROPERTY('ProductVersion')      AS versao,
    SERVERPROPERTY('Edition')             AS edicao,
    SERVERPROPERTY('ProductLevel')        AS serviceplack,
    DATEDIFF(HOUR, sqlserver_start_time, GETDATE()) AS horas_no_ar
FROM sys.dm_os_sys_info;

/* -------------------------------------------------------------------------
   2. BACKUP - a pergunta mais importante depois de "o PDV caiu".
      Vermelho: qualquer base sem backup FULL nas ultimas 24h.
   ------------------------------------------------------------------------- */
SELECT
    'BACKUP' AS bloco,
    d.name                                                  AS banco,
    d.recovery_model_desc                                   AS modelo_recuperacao,
    MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS ultimo_full,
    MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS ultimo_log,
    DATEDIFF(HOUR,
        MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END),
        GETDATE())                                          AS horas_desde_full,
    CASE
        WHEN MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) IS NULL THEN 'CRITICO - NUNCA TEVE BACKUP'
        WHEN DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) > 48 THEN 'CRITICO'
        WHEN DATEDIFF(HOUR, MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END), GETDATE()) > 24 THEN 'ATENCAO'
        ELSE 'OK'
    END                                                     AS status
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON b.database_name = d.name
WHERE d.database_id > 4
GROUP BY d.name, d.recovery_model_desc
ORDER BY horas_desde_full DESC;

/* -------------------------------------------------------------------------
   3. ESPACO EM DISCO POR ARQUIVO - disco cheio = PDV parado.
      Atencao a arquivo com autogrowth desligado ou crescimento em percentual.
   ------------------------------------------------------------------------- */
SELECT
    'ARQUIVOS' AS bloco,
    DB_NAME(f.database_id)                                       AS banco,
    f.name                                                       AS arquivo_logico,
    f.type_desc                                                  AS tipo,
    CAST(f.size / 128.0 AS DECIMAL(10,1))                        AS tamanho_mb,
    CAST(f.max_size / 128.0 AS DECIMAL(18,1))                    AS max_mb,
    CASE WHEN f.is_percent_growth = 1
         THEN CAST(f.growth AS VARCHAR(10)) + ' %'
         ELSE CAST(CAST(f.growth / 128.0 AS DECIMAL(10,1)) AS VARCHAR(20)) + ' MB'
    END                                                          AS crescimento,
    f.physical_name                                              AS caminho
FROM sys.master_files f
WHERE f.database_id > 4
ORDER BY f.size DESC;

/* -------------------------------------------------------------------------
   4. BLOQUEIOS AGORA - se o caixa "travou", comece por aqui.
      Sessao com blocking_session_id preenchido esta esperando outra.
   ------------------------------------------------------------------------- */
SELECT
    'BLOQUEIOS' AS bloco,
    r.session_id                       AS sessao,
    r.blocking_session_id              AS bloqueada_por,
    r.wait_type,
    r.wait_time / 1000.0               AS espera_seg,
    r.status,
    DB_NAME(r.database_id)             AS banco,
    s.login_name,
    s.host_name                        AS terminal,
    s.program_name                     AS aplicacao,
    SUBSTRING(t.text, 1, 300)          AS comando
FROM sys.dm_exec_requests r
JOIN sys.dm_exec_sessions s ON s.session_id = r.session_id
OUTER APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.blocking_session_id <> 0 OR r.session_id IN (
        SELECT blocking_session_id FROM sys.dm_exec_requests WHERE blocking_session_id <> 0)
ORDER BY r.wait_time DESC;

/* -------------------------------------------------------------------------
   5. SESSOES POR TERMINAL - quantos PDVs estao realmente conectados?
      Util para provar que a loja X nao esta sincronizando.
   ------------------------------------------------------------------------- */
SELECT
    'SESSOES' AS bloco,
    s.host_name                        AS terminal,
    s.program_name                     AS aplicacao,
    s.login_name,
    COUNT(*)                           AS sessoes,
    MAX(s.last_request_end_time)       AS ultima_atividade
FROM sys.dm_exec_sessions s
WHERE s.is_user_process = 1
GROUP BY s.host_name, s.program_name, s.login_name
ORDER BY sessoes DESC;

/* -------------------------------------------------------------------------
   6. JOBS DO AGENT QUE FALHARAM NAS ULTIMAS 24H
      Integracao noturna quebrada aparece aqui antes de virar chamado.
   ------------------------------------------------------------------------- */
SELECT
    'JOBS' AS bloco,
    j.name                             AS job,
    h.run_date,
    h.run_time,
    h.run_duration,
    h.message
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE h.run_status = 0                             /* 0 = falhou */
  AND h.step_id    = 0                             /* resultado final do job */
  AND h.run_date  >= CONVERT(INT, CONVERT(VARCHAR(8), DATEADD(DAY,-1,GETDATE()), 112))
ORDER BY h.run_date DESC, h.run_time DESC;

/* -------------------------------------------------------------------------
   7. INDICES MAIS FRAGMENTADOS - lentidao progressiva no PDV.
      Somente diagnostico. NAO reconstrua indice em horario de loja.
      > 30% = candidato a REBUILD ; 10-30% = REORGANIZE.
   ------------------------------------------------------------------------- */
SELECT TOP 20
    'INDICES' AS bloco,
    OBJECT_NAME(ips.object_id)                        AS tabela,
    i.name                                            AS indice,
    CAST(ips.avg_fragmentation_in_percent AS DECIMAL(5,1)) AS fragmentacao_pct,
    ips.page_count                                    AS paginas,
    CASE WHEN ips.avg_fragmentation_in_percent > 30 THEN 'REBUILD'
         WHEN ips.avg_fragmentation_in_percent > 10 THEN 'REORGANIZE'
         ELSE 'OK' END                                AS sugestao
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
WHERE ips.page_count > 1000
  AND i.name IS NOT NULL
ORDER BY ips.avg_fragmentation_in_percent DESC;
