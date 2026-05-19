# Spec M16 · Integração Sistema Domínio · Folha & DP

**Status**: especificação · **ESPECULATIVA** (sem doc oficial Domínio em mãos)
**Versão**: 1.0 · 18 de maio de 2026
**Escopo**: refletir em R2 People os dados de DP/folha gerados no Sistema Domínio (sem recalcular), sentido predominantemente **inbound** (Domínio → R2)
**Depende de**: spec M14 (webhooks inbound · base genérica), spec D9 (API), spec D8 (RLS)

---

## 1. Reposicionamento (não é spec convencional)

R2 People **não substitui** o Domínio. R2 People é a **camada humana** acima:

| Domínio (fonte de verdade DP/fiscal) | R2 People (camada humana) |
|---|---|
| Calcula folha, encargos, INSS, FGTS, IRRF | Mostra **resumo refletido** para colaborador e líder |
| Calcula rescisão | Aciona offboarding com **valores espelhados** |
| Processa férias (CLT) | Wizard de **programação** + alerta vencimento |
| Banco de horas | Mostra **saldo + extrato** consultivo |
| eSocial, FGTS, GPS, RAIS | n/a — R2 não toca obrigação fiscal |
| Holerite PDF oficial | Disponibiliza **download** para colaborador |

Princípio: **R2 nunca inventa cálculo fiscal**. Toda informação financeira/legal exibida tem origem rastreável no Domínio + timestamp da última sincronização.

---

## 2. Premissas (sem doc oficial — revisar)

Como ainda não temos a documentação real do Domínio em mãos, este spec adota premissas baseadas em **padrões típicos de ERPs de DP brasileiros**:

| Premissa | Plano A se confirmado | Plano B se não tiver |
|---|---|---|
| Domínio expõe **API REST** | polling/webhook nativo | n/a |
| Domínio expõe **webhook outbound** | configurar M14 endpoint | n/a |
| Domínio exporta **arquivos** (CSV/XLSX/TXT) | upload diário automatizado | manual + parser |
| Domínio entrega só **relatórios PDF** | OCR + parser estruturado | manual + revisão humana |
| Cadastro de colaborador é **mestre no Domínio** | R2 lê + reflete | n/a |
| Cadastro é **mestre no R2** | R2 empurra para Domínio | n/a |

A spec abaixo cobre **todos os 4 cenários** e o operador escolhe na configuração do endpoint.

---

## 3. Catálogo de dados sincronizados (proposta)

### 3.1 Cadastro de colaboradores

| Campo | Direção típica | Frequência | Conflito (quem ganha) |
|---|---|---|---|
| CPF, RG, nome civil | Domínio → R2 | tempo real / diário | Domínio sempre |
| CTPS, PIS | Domínio → R2 | mudança | Domínio |
| Data admissão / demissão | Domínio → R2 | mudança | Domínio |
| Cargo, faixa, salário | Domínio → R2 | mensal | Domínio |
| Filial, departamento | bidirecional | mudança | R2 (estrutura organizacional) |
| Centro de custo | Domínio → R2 | mudança | Domínio |
| Foto, e-mail corporativo, telefone | R2 → Domínio | tempo real | R2 |
| Dependentes (CPF, parentesco) | Domínio → R2 | mudança | Domínio |
| Endereço residencial | bidirecional | tempo real | quem fizer último update |
| Conta bancária (pagamento) | Domínio só | n/a | n/a (R2 não exibe) |

### 3.2 Folha mensal (refletida em R2)

Após Domínio fechar a folha, R2 recebe:

```json
{
  "event": "payroll.closed",
  "period": "2026-05",
  "tenant_external_id": "GPC-DOMINIO-001",
  "closed_at": "2026-06-05T18:30:00-03:00",
  "totals": {
    "bruto_brl_cents": 48722350,
    "liquido_brl_cents": 36541800,
    "encargos_brl_cents": 17800500,
    "headcount_paid": 367
  },
  "by_branch": [
    {"branch_external_id": "CESTAO-L1", "bruto_brl_cents": 12100000, "headcount": 91},
    ...
  ],
  "items_url": "https://erp.gpc.com.br/api/folha/2026-05/items.csv"
}
```

R2 atualiza `payroll_runs` + opcionalmente faz pull do CSV detalhado para cruzar com employees individuais (sem expor salário a quem não tem permissão).

### 3.3 Holerite individual

| Origem | Como chega |
|---|---|
| **API** | URL signed do PDF gerado no Domínio · R2 armazena link, não conteúdo |
| **Arquivo** | Domínio gera batch de PDFs · R2 ingere e armazena criptografado |
| **OCR fallback** | Domínio entrega lote PDF não estruturado · worker extrai dados-chave (bruto/líquido/descontos/data) |

Colaborador acessa via `r2_people_minha_trajetoria.html` → "Meus holerites" → click abre PDF (audit log dispara).

### 3.4 Rescisão

Quando Domínio calcula rescisão:

```json
{
  "event": "termination.calculated",
  "employee_external_id": "GPC-EMP-1234",
  "termination_date": "2026-06-15",
  "type": "sem_justa_causa",
  "totals": {
    "rescisao_brl_cents": 1842500,
    "ferias_vencidas_brl_cents": 480000,
    "13o_proporcional_brl_cents": 320000,
    "aviso_previo_brl_cents": 412500,
    "fgts_multa_brl_cents": 628000
  },
  "parcelas": [
    {"due_date": "2026-06-20", "brl_cents": 1842500, "type": "rescisao_completa"}
  ],
  "pdf_url": "https://erp.gpc.com.br/api/rescisao/.../trct.pdf"
}
```

R2 mostra na tela de offboarding (líder + RH veem; colaborador vê próprio).

### 3.5 Banco de horas

| Estrutura | Conteúdo |
|---|---|
| `saldo_atual` | em horas + decimal (ex: 12h45min ou 12.75) |
| `compensacao_proxima` | dias planejados |
| `extrato_movimentos` | últimos 90 dias: data, tipo (+/-), origem (HE noturna, etc) |
| `data_compensacao_limite` | quando o saldo precisa zerar (acordo coletivo) |

R2 mostra para colaborador + líder. **Cálculo é Domínio**, R2 só apresenta.

### 3.6 Férias

| Dado | Origem |
|---|---|
| Períodos aquisitivos (CLT) | Domínio (calculado a partir de admissão) |
| Programação | bidirecional — R2 wizard cria + Domínio confirma |
| Saldo de dias | Domínio |
| Abono pecuniário (1/3) | Domínio calcula + R2 mostra opção |
| Concessão (recibo final) | Domínio gera + R2 anexa ao histórico |

### 3.7 13º salário

- 1ª parcela (até 30/nov · 50% bruto)
- 2ª parcela (até 20/dez · líquido = 50% bruto − INSS − IRRF)
- R2 mostra previsão na home a partir de nov + confirma valor real após fechamento

### 3.8 Encargos por filial

Mensal · R2 reflete:
- INSS patronal (20% + RAT)
- FGTS (8%)
- Provisão férias (1/12 + 1/3)
- Provisão 13º (1/12)
- Vale-transporte (custo empresa)
- Custo total por filial / centro de custo

Alimenta o **People Analytics M17** (aba Custo).

### 3.9 Admissões e desligamentos

Quando Domínio processa admissão/demissão (geralmente disparada por R2 mas pode ser direto no Domínio):

```json
{ "event": "employee.admitted", "external_id": "...", "admission_date": "...", "branch": "..." }
{ "event": "employee.terminated", "external_id": "...", "termination_date": "...", "type": "..." }
```

R2 sincroniza com `employees.status` + `movements`. Já coberto pelos handlers de M14.

### 3.10 NÃO sincronizamos

| Dado | Por quê |
|---|---|
| Conta bancária do colaborador | sensível, pagamento é só Domínio |
| Pensão alimentícia (judicial) | sensível extremo, só DP toca |
| Bloqueios judiciais | privacidade |
| Empréstimo consignado | financeiro privado |

R2 People **não armazena** nem **exibe** esses dados. Se aparecerem no payload, são strippados na ingestão.

---

## 4. Modos de integração (configuráveis no endpoint)

### 4.1 Modo A · API REST nativa (ideal)

Domínio expõe endpoints REST + autenticação. R2 faz **polling agendado** em horários específicos.

```
Diário 06:00 BRT · GET /api/folha/mes-atual/resumo
Diário 06:15 BRT · GET /api/colaboradores/movimentacoes-ultimas-24h
Semanal seg 03:00 · GET /api/banco-horas/saldos
Mensal dia 6 03:00 · GET /api/folha/{ano-mes}/fechada
```

Worker R2 (`worker-dominio-polling`) executa cron, persiste em `inbound_events_log` (M14) e processa via handlers existentes.

**Configuração no R2**:

```sql
INSERT INTO inbound_webhook_endpoints (
  tenant_id, name, source_system,
  config_extra
) VALUES (
  '...', 'Domínio · prod', 'dominio_api',
  jsonb_build_object(
    'mode', 'api_polling',
    'base_url', 'https://erp.gpc.com.br/api/dominio',
    'auth_type', 'bearer',
    'auth_token_vault_key', 'gpc_dominio_token',
    'polling_schedule', jsonb_build_object(
      'daily_06_00', ['payroll.summary','employees.changes'],
      'weekly_mon_03_00', ['banco_horas.saldos']
    )
  )
);
```

### 4.2 Modo B · Webhook outbound do Domínio

Se Domínio puder enviar webhook quando evento ocorre, R2 já tem endpoint pronto (M14):

```
POST https://api.r2-people.com/v1/webhooks/inbound/gpc
X-R2-Source: dominio
X-R2-Event: payroll.closed
... HMAC + payload
```

Configuração: R2 fornece signing_secret, Domínio configura no painel administrativo.

### 4.3 Modo C · Upload de arquivos (CSV/XLSX)

Domínio gera batch diário/mensal de arquivos e:
- **3.1**: SFTP para bucket R2 (R2 monitora)
- **3.2**: Upload manual via UI `r2_people_dominio_upload.html` (a criar)
- **3.3**: E-mail para endereço dedicado (`dominio@gpc.r2-mail.com`) com anexo · R2 parseia

Cada arquivo conhecido tem parser específico:

| Arquivo | Parser | Frequência típica |
|---|---|---|
| `folha_YYYYMM.csv` | `parser_folha_dominio_csv` | mensal |
| `holerites_YYYYMM.zip` (PDFs nomeados por matrícula) | `parser_holerites_zip` | mensal |
| `movimentacoes_YYYYMMDD.csv` | `parser_movs_diarias` | diário |
| `banco_horas_YYYYMMDD.csv` | `parser_banco_horas` | semanal |
| `dependentes_YYYYMM.csv` | `parser_dependentes` | mensal |

### 4.4 Modo D · OCR de PDF não estruturado (fallback)

Quando Domínio só entrega PDF (relatório oficial sem export estruturado), R2 usa worker com Tesseract (já existe para atestados) + parser regex para extrair:
- Período da folha
- Totais (bruto, líquido, encargos)
- Lista de colaboradores com matrícula + valor

**Sempre revisão humana** antes de marcar como confiável. Status do batch: `pending_review` → `approved` (RH aprova).

---

## 5. Schema (estende M14)

```sql
-- Extensão de inbound_webhook_endpoints com configs específicas
ALTER TABLE inbound_webhook_endpoints
  ADD COLUMN IF NOT EXISTS integration_mode text
    CHECK (integration_mode IN ('webhook','api_polling','file_upload','ocr_pdf')),
  ADD COLUMN IF NOT EXISTS config_extra jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS last_sync_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_sync_status text
    CHECK (last_sync_status IN ('success','partial','failed','running','idle'));

-- Mapeamento de IDs entre R2 e Domínio (employees mestre no Domínio)
CREATE TABLE IF NOT EXISTS dominio_id_map (
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  entity_type        text NOT NULL CHECK (entity_type IN ('employee','branch','department','position','payroll_run','dependent')),
  r2_id              uuid NOT NULL,
  dominio_external_id text NOT NULL,
  first_seen_at      timestamptz NOT NULL DEFAULT now(),
  last_synced_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id, entity_type, dominio_external_id)
);

CREATE INDEX idx_dominio_id_map_r2
  ON dominio_id_map (tenant_id, entity_type, r2_id);

-- Sincronizações agendadas
CREATE TABLE IF NOT EXISTS dominio_sync_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  endpoint_id     uuid NOT NULL REFERENCES inbound_webhook_endpoints(id) ON DELETE CASCADE,
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  sync_type       text NOT NULL,                -- 'payroll.monthly','employees.daily','banco_horas.weekly'
  scheduled_for   timestamptz NOT NULL,
  started_at      timestamptz,
  finished_at     timestamptz,
  status          text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','running','success','failed','skipped')),
  records_processed int,
  records_failed  int,
  error_summary   text,
  metadata        jsonb DEFAULT '{}'::jsonb
);

CREATE INDEX idx_dominio_sync_pending
  ON dominio_sync_jobs (scheduled_for) WHERE status = 'pending';

CREATE INDEX idx_dominio_sync_tenant_recent
  ON dominio_sync_jobs (tenant_id, started_at DESC);
```

---

## 6. RPCs principais

```sql
-- Resolver R2 id a partir de external_id do Domínio
CREATE OR REPLACE FUNCTION rpc_dominio_resolve_id(
  p_tenant_id uuid,
  p_entity_type text,
  p_dominio_external_id text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_r2_id uuid;
BEGIN
  SELECT r2_id INTO v_r2_id FROM dominio_id_map
  WHERE tenant_id = p_tenant_id
    AND entity_type = p_entity_type
    AND dominio_external_id = p_dominio_external_id;
  RETURN v_r2_id;
END;
$$;

-- Upsert mapping (chamado pelo worker quando processa cada evento)
CREATE OR REPLACE FUNCTION rpc_dominio_link_id(
  p_tenant_id uuid,
  p_entity_type text,
  p_r2_id uuid,
  p_dominio_external_id text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO dominio_id_map (tenant_id, entity_type, r2_id, dominio_external_id)
  VALUES (p_tenant_id, p_entity_type, p_r2_id, p_dominio_external_id)
  ON CONFLICT (tenant_id, entity_type, dominio_external_id) DO UPDATE
    SET r2_id = EXCLUDED.r2_id, last_synced_at = now();
END;
$$;

-- Status agregado de sync (cockpit Notif & Webhooks · aba Domínio)
CREATE OR REPLACE FUNCTION rpc_dominio_sync_status(p_tenant_id uuid)
RETURNS TABLE (
  endpoint_name text,
  integration_mode text,
  last_sync_at timestamptz,
  last_sync_status text,
  pending_jobs int,
  failed_last_24h int
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    iwe.name,
    iwe.integration_mode,
    iwe.last_sync_at,
    iwe.last_sync_status,
    (SELECT count(*)::int FROM dominio_sync_jobs WHERE endpoint_id = iwe.id AND status='pending'),
    (SELECT count(*)::int FROM dominio_sync_jobs
      WHERE endpoint_id = iwe.id AND status='failed' AND started_at > now() - interval '24 hours')
  FROM inbound_webhook_endpoints iwe
  WHERE iwe.tenant_id = p_tenant_id
    AND iwe.source_system = 'dominio_api';
END;
$$;
```

---

## 7. Workers

| Worker | Função |
|---|---|
| `worker-dominio-polling` | executa cron de polling REST conforme `polling_schedule` |
| `worker-dominio-files` | monitora SFTP/storage por novos arquivos, dispara parser correspondente |
| `worker-dominio-ocr` | OCR de PDFs não estruturados + extração regex |
| `worker-dominio-reconcile` | reconciliação diária: para cada colaborador no Domínio, verifica se existe em R2 (cria placeholder se não) |

Todos rodam isolados por tenant_id, com retries exponenciais e logs em `dominio_sync_jobs`.

---

## 8. UI · onde aparece

### 8.1 Configuração inicial (tenant_admin)

Nova aba "**Integrações · Domínio**" em `r2_people_configuracoes.html`:
- Wizard 4 passos:
  1. Escolher modo (API / Webhook / Upload / OCR)
  2. Configurar credenciais (URL + token / signing_secret / SFTP / e-mail)
  3. Mapear estrutura (filial Domínio → filial R2, etc)
  4. Teste de sincronização (puxa 1 registro de cada tipo + mostra preview)

### 8.2 Monitoramento (Notif & Webhooks admin)

Adicionar aba "**Domínio**" em `r2_people_notificacoes_admin.html`:
- Status de cada endpoint (último sync, próximo agendado)
- Jobs pendentes/falhados últimas 24h
- Botão "Sincronizar agora"
- Mapeamento de IDs (R2 ↔ Domínio) c/ % de matching

### 8.3 Colaborador (apresentação dos dados)

Em `r2_people_minha_trajetoria.html` adicionar seção "**Meus dados financeiros (do Domínio)**":
- Último holerite (PDF download)
- Saldo banco de horas atual
- Saldo de férias
- Previsão 13º
- Histórico folhas (12 meses)

Cada item tem badge "Atualizado em DD/MM" e tooltip "Dados sincronizados do Sistema Domínio em [timestamp]".

### 8.4 Líder

Em `r2_people_admin_dashboard.html`:
- Custo da minha equipe (mensal, do Domínio)
- Banco de horas da equipe (quem está saturado)
- Férias programadas (com valores Domínio confirmados)

### 8.5 People Analytics (M17)

Aba **Custo** consome dados do Domínio (já especificado em M17).

---

## 9. Tratamento de conflitos

| Situação | Resolução |
|---|---|
| Colaborador admitido no Domínio sem existir em R2 | Worker cria placeholder + dispara onboarding |
| Colaborador admitido em R2 sem chegar no Domínio em 24h | Alerta P3 ao tenant_admin "verificar fluxo" |
| Cargo R2 ≠ cargo Domínio | Domínio ganha (fonte fiscal), R2 atualiza |
| Salário R2 ≠ salário Domínio | Domínio ganha sempre, R2 nem armazena individual |
| Endereço R2 mais novo que Domínio | R2 empurra (R2 é onde colaborador atualiza) |
| Foto R2 ≠ Domínio (sequer existe foto no Domínio) | R2 mestre |
| Mesma matrícula em 2 colaboradores | Erro de integração · log + alerta DPO |

---

## 10. Segurança LGPD-specific

- **Token do Domínio** armazenado em vault separado (nunca em código nem em backups planos)
- **HMAC validation** em webhooks inbound conforme M14
- **TLS 1.3 obrigatório** em qualquer canal
- **Sem dados financeiros sensíveis** (conta bancária, pensão, empréstimo)
- **Logging** de cada sync em `dominio_sync_jobs` + `action_log`
- **Retenção** dos logs: 2 anos quente + 5 anos frio (auditável)
- **DSAR-erase** propaga: quando R2 anonimiza colaborador, marca também em `dominio_id_map` para evitar re-sincronização

---

## 11. Testes meta (mínimo 20)

### 11.1 Modos de integração
- ✓ Modo API polling executa no horário agendado
- ✓ Modo webhook recebe + valida HMAC + dedupe
- ✓ Modo file upload aceita CSV padrão Domínio
- ✓ Modo OCR extrai totais corretamente em PDF mock

### 11.2 Mapeamento
- ✓ `dominio_resolve_id` retorna R2 id correto
- ✓ Mesmo `external_id` em tenant diferente NÃO conflita (RLS)
- ✓ Colaborador em Domínio sem R2 cria placeholder

### 11.3 Conflitos
- ✓ Salário individual nunca armazenado em R2
- ✓ Endereço atualizado em R2 dispara push pro Domínio
- ✓ Mesma matrícula em 2 colaboradores → erro + alerta

### 11.4 Reflexo
- ✓ `payroll.closed` atualiza payroll_runs + reflete em M17
- ✓ Banco de horas mostra saldo correto na trajetória
- ✓ Férias programadas batem com Domínio
- ✓ Holerite baixa PDF (não armazena conteúdo, só link signed)

### 11.5 LGPD
- ✓ Conta bancária no payload é strippada
- ✓ DSAR-erase marca `dominio_id_map` (evita re-sync)
- ✓ Cada sync registrado em `action_log` para audit
- ✓ Token Domínio nunca aparece em log

### 11.6 Robustez
- ✓ Endpoint Domínio offline gera badge "X dias atrás" + alerta
- ✓ Worker retoma de onde parou após reinício
- ✓ Sync parcial não corrompe estado (transação por batch)
- ✓ Reconciliação noturna detecta drift

---

## 12. Roadmap pós-MVP

1. **M+1 · Confirmar API real Domínio** com documentação oficial (esta spec é especulativa)
2. **M+3 · UI completa configuração** (`r2_people_dominio_setup.html`)
3. **M+6 · Reconciliação automática** noturna + relatório de drift
4. **M+9 · Suporte a outros ERPs DP brasileiros**: ContaAzul Folha, Conta Simples, eFolha, Folha Certa, SISFOLHA · cada um vira nova spec irmã (M16.1, M16.2, etc)
5. **M+12 · Dual-write opcional** (R2 atualiza Domínio direto, sem passar por arquivo) onde a API permitir
6. **M+18 · ETL bidirecional** com data warehouse próprio do cliente (cliente puxa do R2 + Domínio consolidado)

---

## 13. O que precisamos saber sobre Domínio para refinar

Quando você conseguir a documentação ou contato técnico Domínio, perguntas a responder:

1. Existe API REST? Quais endpoints? Auth (OAuth / API key / basic)?
2. Suporta webhooks outbound? Quais eventos? Formato do payload?
3. Quais relatórios exportam para CSV/XLSX? Layout fixo?
4. Como identificam colaborador? CPF? Matrícula interna? UUID?
5. Como tratam multi-empresa (CTPS diferente) num mesmo grupo?
6. Permitem update via API (dual-write) ou só leitura?
7. Têm sandbox para testes sem afetar produção?
8. Qual SLA de atualização (real-time vs end-of-day)?
9. Como tratam histórico (rectificação retroativa)?
10. Têm webhook signing / autenticação adicional?

Cada resposta dessas vira ajuste cirúrgico nesta spec.

---

## 14. Posicionamento do produto

Com M16, R2 People reforça mensagem comercial (atualizar C1 e C3):

> "Você não vai trocar seu Domínio. R2 People é a **camada de gestão de pessoas** que mostra no celular do seu colaborador o que o Domínio já calcula — e dá ao seu líder o que o Domínio nunca foi feito pra entregar: 1:1 estruturada, PDI, 9-Box, OKR, clima."

Diferenciação contra:
- Sólides / Qulture: nenhum tem integração Domínio nativa
- Senior / Totvs HCM: querem substituir Domínio (caro, lento, transição arriscada)
- Planilha: você sabe o problema

---

## 15. Para a próxima conversa

Esta spec é **especulativa**. Antes de implementar:
- Conseguir doc oficial Domínio (ou contato técnico)
- Validar premissas da §3.1-3.9 com cliente piloto (GPC)
- Decidir modo primário (4.1-4.4) com base na realidade do cliente
- Confirmar que NÃO sincronizamos os itens da §3.10

A partir daí, esta spec vira `v2.0` com decisões concretas.
