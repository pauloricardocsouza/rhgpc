# Spec D4 · Backups, Retenção e Disaster Recovery

**Status**: especificação · pré-implementação
**Versão**: 1.0 · 17 de maio de 2026
**Escopo**: estratégia de backup, restore point-in-time, política de retenção LGPD, runbook de DR
**Depende de**: Supabase Postgres 16, schema v10, política de retenção CLT 5 anos

---

## 1. Objetivos

1. **Zero perda de dados** (RPO ≤ 5 min) para dados transacionais críticos (folha, atestados, movements).
2. **Retorno operacional rápido** (RTO ≤ 4 h) após incidente catastrófico (perda de região, corrupção lógica, ransomware).
3. **Compliance LGPD** · backups respeitam as mesmas regras de retenção dos dados originais.
4. **Auditabilidade** · cada restore é logado em `dr_events` e revisado pelo DPO.

### 1.1 RPO/RTO por classe de dado

| Classe | Exemplo | RPO | RTO | Tier |
|---|---|---|---|---|
| Transacional crítico | folha, movements, atestados | ≤ 5 min | ≤ 4 h | T0 |
| Operacional | comunicados, OKRs, 1:1s | ≤ 1 h | ≤ 8 h | T1 |
| Analítico/derivado | relatórios cache, métricas | ≤ 24 h | ≤ 24 h | T2 |
| Cold (arquivado) | folhas > 2 anos | ≤ 7 dias | ≤ 7 dias | T3 |

---

## 2. Estratégia de backup multi-camada

### 2.1 PITR (Point-in-Time Recovery) · Supabase Pro

- **WAL streaming contínuo** para storage gerenciado Supabase.
- **Janela**: 7 dias para Pro, 28 dias para Team (recomendado upgrade).
- **Granularidade**: segundo a segundo dentro da janela.
- **Custo**: incluso no plano.

### 2.2 Snapshots lógicos diários (pg_dump)

- Job cron diário (03:00 BRT) gera `pg_dump --format=custom` por tenant.
- Armazenamento: bucket S3-compatível (Backblaze B2 região eu-central) **fora** da AWS.
- **Criptografia**: AES-256 client-side antes do upload (chave em Vault).
- **Naming**: `{tenant_slug}_{YYYYMMDD}_{schema_version}.dump.enc`
- **Verificação**: restore automático para banco shadow toda madrugada (smoke test).

### 2.3 Backup de Storage (atestados, fotos, docs)

- Buckets Supabase Storage replicados para B2 via rclone diário.
- Versionamento ativado no destino (mantém 30 dias de versões).
- Hash SHA-256 de cada blob registrado em `storage_backup_log` para detecção de bit-rot.

### 2.4 Backup de configuração e segredos

- `secrets_vault.yaml` exportado encriptado para repositório privado separado.
- Inclui: connection strings, JWT secrets, SMTP, webhook signing keys.
- Rotação obrigatória após qualquer restore que envolva esse arquivo.

---

## 3. Política de retenção (alinhada à LGPD + CLT)

| Categoria | Janela quente (online) | Frio (arquivo) | Hard delete | Base legal |
|---|---|---|---|---|
| Atestados, CID, prontuário | 5 anos pós-término | até 20 anos | após DSAR-erase autorizado | CLT 11 § Lei 8.213 |
| Folha de pagamento | 5 anos pós-término | 30 anos | nunca (obrigação fiscal) | DL 5452 art 462, IN RFB |
| Cadastro pessoal | enquanto vínculo ativo | 5 anos pós-término | DSAR-erase | LGPD art 16 |
| Avaliações, 1:1s | 5 anos | descarte | DSAR-erase ou descarte | LGPD art 15 §3º |
| Login audit, action_log | 2 anos | 5 anos comprimido | nunca (compliance) | LGPD art 37 |
| Notificações | 90 dias | 1 ano | descarte automático | n/a |

A função `archive_old_records()` roda mensalmente e move dados quentes → tabelas `_archive` no mesmo schema (com índices reduzidos). Movimento para frio (S3 Glacier) é semestral.

---

## 4. Runbook · cenários de DR

### 4.1 Cenário A · Corrupção lógica em tabela (DROP acidental, UPDATE sem WHERE)

1. **Detectar**: alerta automático de queda de row count > 10 % em tabelas T0.
2. **Isolar**: marcar tenant como `under_maintenance = true`, parar workers.
3. **PITR restore para banco shadow**: `pg_restore` no momento T - 5min do incidente.
4. **Validar**: comparar `SELECT count(*)` e checksums das tabelas afetadas.
5. **Copiar diff**: `INSERT ... ON CONFLICT DO NOTHING` do shadow para prod.
6. **Pós-mortem**: registrar em `dr_events`, comunicar DPO em 24 h, possível Art. 48 LGPD se dado pessoal vazou.

**RTO esperado**: 1-2 h para uma tabela isolada.

### 4.2 Cenário B · Perda total da região (Supabase down ≥ 1 h)

1. **Decisão de failover**: SLA de espera = 30 min. Após isso, restore em região secundária.
2. **Provisionar Postgres em região reserva** (Neon ou outro Supabase europeu) via Terraform.
3. **Restore do último snapshot lógico** (≤ 24 h antigo) + replay de WAL se disponível.
4. **DNS swap**: `app.rh.solucoesr2.com.br` aponta para novo backend.
5. **Comunicar clientes**: banner amarelo "Operando em modo recuperação".
6. **Eventos T-RPO** (últimas 5 min/1h dependendo do tier) precisam ser reenviados pelo cliente — comunicar isso explicitamente.

**RTO esperado**: 4 h.

### 4.3 Cenário C · Ransomware / comprometimento

1. **Isolar imediatamente**: revogar todas as JWTs (`SELECT * FROM session_revocations`), trocar JWT secret.
2. **Restore de snapshot lógico anterior à intrusão** (não usar PITR pois pode estar contaminado).
3. **Auditoria forense**: dump completo do `login_audit` + `action_log` para análise externa.
4. **Notificação ANPD em 48 h** se houve vazamento confirmado (LGPD art 48).
5. **Comunicação aos titulares** afetados se categoria 1 (sensíveis: atestados, CID).
6. **Rotação completa de segredos** (todos os webhooks, api_keys, JWT).

**RTO esperado**: 8-24 h dependendo do escopo.

### 4.4 Cenário D · DSAR-erase irreversível solicitado por engano

- DSAR-erase é **soft delete** com janela de 30 dias antes do hard-delete.
- Se o titular voltar atrás em < 30 dias: restore via `UPDATE ... SET deleted_at = NULL`.
- Após 30 dias: dados foram zerados via `pg_repack`, não recuperáveis. Restore só via PITR para antes da janela.

---

## 5. Tabelas de controle

```sql
-- Eventos de DR (cada restore, cada falha, cada smoke test)
CREATE TABLE dr_events (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type    text NOT NULL CHECK (event_type IN ('pitr_restore','logical_restore','smoke_test','failover','manual_drill')),
  tenant_id     uuid REFERENCES tenants(id),
  triggered_by  uuid REFERENCES auth.users(id),
  reason        text NOT NULL,
  target_pit    timestamptz,           -- ponto no tempo restaurado
  started_at    timestamptz NOT NULL DEFAULT now(),
  finished_at   timestamptz,
  success       boolean,
  data_loss_seconds int,               -- gap entre target_pit e último commit pré-incidente
  affected_tables text[],
  notes         text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Log de smoke test (restore automático madrugada)
CREATE TABLE backup_smoke_tests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at          timestamptz NOT NULL DEFAULT now(),
  dump_filename   text NOT NULL,
  dump_size_bytes bigint,
  restore_ms      int,
  row_count_diff  jsonb,                -- por tabela: { "employees": -2, "movements": 0 }
  success         boolean NOT NULL,
  error_msg       text
);

-- Log de integridade de Storage (hashes)
CREATE TABLE storage_backup_log (
  bucket          text NOT NULL,
  object_key      text NOT NULL,
  sha256          text NOT NULL,
  size_bytes      bigint NOT NULL,
  backed_up_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (bucket, object_key, sha256)
);
```

---

## 6. Smoke test automatizado (madrugada)

```bash
# Cron diário 04:00 BRT (após o dump de 03:00)
#!/bin/bash
set -euo pipefail
DUMP=$(ls -t /backups/${TENANT_SLUG}_*.dump.enc | head -1)
DECRYPTED=/tmp/restore_$$.dump
openssl enc -d -aes-256-cbc -in "$DUMP" -out "$DECRYPTED" -pass file:/vault/backup.key

# Banco shadow descartável
psql -c "DROP DATABASE IF EXISTS shadow_${TENANT_SLUG};"
psql -c "CREATE DATABASE shadow_${TENANT_SLUG};"

START=$(date +%s%3N)
pg_restore -d shadow_${TENANT_SLUG} "$DECRYPTED"
END=$(date +%s%3N)

# Verifica counts vs prod
DIFF=$(psql -t -A -c "
  SELECT json_object_agg(t, diff) FROM (
    SELECT table_name AS t, prod_count - shadow_count AS diff
    FROM compare_table_counts('${TENANT_SLUG}', 'shadow_${TENANT_SLUG}')
    WHERE prod_count - shadow_count > 0
  ) s
")

psql -c "
  INSERT INTO backup_smoke_tests (dump_filename, dump_size_bytes, restore_ms, row_count_diff, success)
  VALUES ('$DUMP', $(stat -c%s "$DUMP"), $((END-START)), '${DIFF:-{}}'::jsonb, true)
"

rm -f "$DECRYPTED"
psql -c "DROP DATABASE shadow_${TENANT_SLUG};"
```

---

## 7. Drills programados (exercício de DR)

- **Trimestral**: equipe de plantão executa cenário A em ambiente staging com cronômetro.
- **Semestral**: cenário B completo (failover de região) em janela noturna com aviso prévio aos clientes.
- **Anual**: exercício de cenário C (ransomware simulado) com auditoria externa.
- Cada drill é registrado em `dr_events` com `event_type = 'manual_drill'` e gera relatório PDF assinado pelo CTO.

---

## 8. Monitoramento e alertas

| Métrica | Threshold | Ação |
|---|---|---|
| WAL lag (PITR) | > 30 s | PagerDuty WARN |
| WAL lag | > 5 min | PagerDuty CRITICAL → failover |
| Dump diário não concluído até 06:00 | atraso | Slack + email DPO |
| Smoke test falhou | qualquer falha | Bloquear deploy do dia |
| Hash storage divergente | > 0 | Restaurar do versionamento B2 + auditoria |
| `dr_events.success = false` últimas 24h | > 0 | Reunião emergencial |

---

## 9. Responsabilidades (RACI)

| Atividade | R | A | C | I |
|---|---|---|---|---|
| Operação diária de backup | DevOps | CTO | DBA | DPO |
| Definição de retenção | DPO | CEO | Jurídico | DevOps |
| Execução de DR cenário A | DevOps | CTO | DBA | Suporte |
| Execução de DR cenário B/C | CTO | CEO | DPO, Jurídico | Clientes |
| Notificação ANPD | DPO | CEO | Jurídico | - |
| Drills trimestrais | DevOps | CTO | - | Equipe toda |

---

## 10. Itens fora de escopo

- Replicação síncrona multi-região (custo proibitivo para o estágio atual).
- Backup de logs de aplicação (responsabilidade do provedor de observability — Logflare/Axiom).
- DR de e-mail transacional (terceirizado SendGrid).

---

## 11. Próximos passos pós-MVP

1. Avaliar **Supabase Read Replica** em região secundária (SP) para reduzir RTO < 1 h.
2. Implementar **Logical Replication** para tenant_id-aware streaming a um data warehouse (Snowflake/BigQuery) para analytics offline.
3. Considerar **WORM storage** (write-once-read-many) para folha de pagamento — atende exigência de não-mutabilidade fiscal.
4. Acrescentar **DR de schema próprio** (rollback de migration que quebrou produção) via `pg_dump` antes de cada `supabase db push`.
