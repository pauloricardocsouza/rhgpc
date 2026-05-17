# Política de Privacidade · Atestados Médicos

**Versão:** 1.0 · 17 de maio de 2026
**Controlador:** Cliente que opera o GPC People (ex: Grupo Pinto Cerqueira)
**Operador:** R2 Soluções Empresariais Ltda
**Complementa:** [r2_people_privacy_policy.md](r2_people_privacy_policy.md) e [r2_people_privacy_oneonones.md](r2_people_privacy_oneonones.md)
**Base legal:** LGPD Lei 13.709/2018 (Art. 11 categoria especial) · CLT Art. 168 · Resolução CFM 1.658/2002

---

## 1. Por que esta política existe

Atestados médicos contêm dois tipos de dados altamente sensíveis:

1. **Dados de saúde** (CID-10, nome do médico, diagnóstico) → categoria especial conforme **LGPD Art. 11**
2. **Documento original assinado** → potencial vazamento de informações pessoais (assinatura, papel timbrado de clínica, etc.)

Tratar esses dados como cadastro comum seria violação de privacidade e contrato social. Esta política descreve o **modelo de 3 níveis de acesso** que protege esses dados na arquitetura do produto.

---

## 2. O modelo de 3 níveis de acesso

```
┌─────────────────────────────────────────────────────────────────┐
│  NIVEL 1 · ACESSO COMPLETO · DP (Departamento Pessoal)         │
│  ───────────────────────────────────────────────                │
│  Vê:  PDF original, CID-10, nome médico, CRM, hospital,         │
│       todas as datas, justificativa                             │
│  Quem: DP com permission view_medical_cid (geralmente RH        │
│        sênior, especialista de DP)                              │
│  Garantia: RLS · policy mc_dp_select                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  NIVEL 2 · ACESSO PARCIAL · O PRÓPRIO COLABORADOR              │
│  ───────────────────────────────────────────────                │
│  Vê:  Seus próprios atestados (lista), data, dias afastados,    │
│       status. CID **só ao baixar o PDF original**.              │
│  Quem: o próprio employee_id da app_users                       │
│  Garantia: RLS · policy mc_self_select                          │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  NIVEL 3 · ACESSO MÍNIMO · LÍDER QUE ENVIOU                    │
│  ───────────────────────────────────────────────                │
│  Vê:  Apenas protocolo, status, iniciais do colaborador         │
│       ("F. Lima"), tipo certificado, dias afastados             │
│  Quem: submitter_id no momento do envio                         │
│  NÃO vê: CID, PDF, nome médico, hospital                        │
│  Garantia: NÃO há policy de SELECT pro líder · acesso só via    │
│            RPC limitada rpc_get_my_submitted_certificates       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Princípios duros (arquiteturais, não cosméticos)

### 3.1 Líder envia mas não vê depois

Quando um líder envia um atestado pelo colaborador (caso comum: papel físico chegou na supervisão), ele perde acesso ao conteúdo imediatamente após o upload. A política RLS no banco **não permite** que o líder leia a tabela `medical_certificates` direto.

A única forma do líder ver algo é via RPC `rpc_get_my_submitted_certificates(p_limit)` que retorna **campos abreviados**:

```sql
-- Pseudocode do que a RPC retorna pro líder:
{
  protocol: 'ATD-2026-05-10-A3F2C',
  employee_initials: 'F. Lima',           -- não nome completo
  certificate_type: 'doenca_propria',
  starts_at: '2026-05-10',
  ends_at: '2026-05-12',
  days_off: 3,
  status: 'validated',
  created_at: '2026-05-10T08:14:00Z'
  -- NUNCA: cid_code, doctor_name, file_storage_path, hospital_clinic
}
```

Se o líder tentar acessar via SQL direto (caso superuser hipotético com má-fé), a query retorna 0 rows porque não há policy `mc_leader_select`.

### 3.2 CID só pro DP

O **CID-10** é o dado mais sensível do atestado · revela diagnóstico médico. Por isso:

- Visível apenas em `rpc_get_certificate_detail` chamada por usuário com `permission='view_medical_cid'`
- Nem o próprio colaborador vê CID em listagem · só ao **clicar pra baixar o PDF original**
- Auditoria log obrigatória em CADA visualização

### 3.3 OCR client-side

O processo de OCR (extração de texto do PDF do atestado) roda **no navegador** do líder ou do colaborador (Tesseract WASM). A imagem do atestado nunca é enviada para serviço externo de OCR.

Implicações:
- ✅ Sem custo de API externa
- ✅ Sem risco de vazamento via terceiros
- ✅ Conformidade com LGPD Art. 11 (categoria especial sem compartilhamento)
- ⚠️ Pode ser lento em dispositivos antigos (~5-10s por página)

### 3.4 Storage do PDF é privado

O bucket `medical-certificates` no Supabase Storage:
- **Privado** (não público · requer assinatura URL para download)
- Policy RLS espelha a da tabela (DP + próprio colaborador)
- URLs assinadas expiram em 60 segundos (download direto, sem cache no CDN)
- Backup criptografado AES-256 em região South America

---

## 4. Fluxo completo · exemplo real (Atestado do Rafael)

Para deixar concreto, segue o fluxo de ponta a ponta de um atestado real:

### Passo 1 · Recebimento (Sandra Lima, gerente)

Rafael (repositor do ATP Varejo) entrega atestado físico pra Sandra na 2ª feira de manhã. Sandra abre `/atestados/enviar` no celular dela.

### Passo 2 · Envio (Sandra)

Sandra:
1. Seleciona Rafael na busca por nome/matrícula
2. Tira foto do atestado com `<input type="file" capture="environment">`
3. OCR roda no celular dela (3 segundos) e pré-preenche:
   - CID: M54.5 (Dor lombar baixa)
   - Médico: Dr. House
   - Período: 12/05 a 14/05 (3 dias)
4. Sandra confirma e envia

### Passo 3 · Submit · garantias arquiteturais

Sistema:
1. Grava em `medical_certificates` com `submitter_id = sandra.id`
2. Gera protocolo `ATD-2026-05-12-A3F2C` automaticamente
3. Faz upload do PDF pro bucket privado
4. **Sandra perde acesso ao conteúdo imediatamente** · sua próxima abertura da tela mostra só protocol + iniciais + status

### Passo 4 · Notificações

Notifica em paralelo:
- **Patrícia Mello** (DP do GPC · view_medical_cid)
- **Larissa Pereira** (RH prestadora Labuta · scope_employer = labuta · só se Rafael for Labuta)
- **Rafael** (próprio colaborador)

### Passo 5 · Validação (Patrícia)

Patrícia abre `/atestados/validar` em layout inbox-style:
- Fila central com cards (qualidade OCR, prioridade)
- Clica no card do Rafael
- Viewer mostra PDF + form de validação com CID pré-preenchido
- Confirma CID M54.5, clica **Validar e gerar movimentação**

### Passo 6 · Movimentação automática

`rpc_validate_certificate(p_id, 'M54.5', 'Dor lombar', p_create_movement=TRUE)`:
1. Atualiza `status='validated'`, `validated_by=patricia.id`
2. Como `days_off >= 3`, cria automaticamente uma movimentação em `movements`:
   - kind: `leave_medical`
   - protocol: `MOV-AUTO-2026-05-12-A3F2C`
   - effective_date: 12/05/2026
   - notice_days: 0 (atestado já entregue)
3. Vincula `medical_certificates.auto_movement_id = movements.id`
4. Audit log registra ação

### Passo 7 · Rafael acompanha

Rafael recebe notificação in-app. Abre `/minha-jornada/atestados`:
- Vê o atestado validado
- Vê dias afastados, status
- **Não vê CID** na listagem
- Pode baixar PDF original (audit log da visualização do CID)

### Passo 8 · Sandra acompanha (limitado)

Sandra abre o histórico dela:
- Vê protocol `ATD-2026-05-12-A3F2C` · status: validated
- Vê "F. Lima · 3 dias afastado"
- **Não vê CID, não vê PDF, não vê nome do médico**

---

## 5. Quem acessa o quê (tabela definitiva)

| Dado | Líder (submitter) | Colaborador (owner) | DP | RH Prestadora | DPO |
|---|:-:|:-:|:-:|:-:|:-:|
| `protocol` | ✅ | ✅ | ✅ | ✅ (escopo) | ✅ |
| `status` | ✅ | ✅ | ✅ | ✅ (escopo) | ✅ |
| `employee_initials` | ✅ "F. Lima" | ✅ nome cheio | ✅ nome cheio | ✅ nome cheio | ✅ |
| `days_off` | ✅ | ✅ | ✅ | ✅ (escopo) | ✅ |
| `starts_at`, `ends_at` | ✅ | ✅ | ✅ | ✅ (escopo) | ✅ |
| `certificate_type` | ✅ | ✅ | ✅ | ✅ (escopo) | ✅ |
| `cid_code` | ❌ | ⚠️ só ao baixar PDF | ✅ | ❌ | ⚠️ DSAR |
| `cid_description` | ❌ | ⚠️ só ao baixar PDF | ✅ | ❌ | ⚠️ DSAR |
| `doctor_name` | ❌ | ⚠️ só ao baixar PDF | ✅ | ❌ | ⚠️ DSAR |
| `doctor_crm` | ❌ | ⚠️ só ao baixar PDF | ✅ | ❌ | ⚠️ DSAR |
| `hospital_clinic` | ❌ | ⚠️ só ao baixar PDF | ✅ | ❌ | ⚠️ DSAR |
| `file_storage_path` (PDF) | ❌ | ✅ | ✅ | ❌ | ⚠️ DSAR |
| `ocr_extracted` (raw text) | ❌ | ❌ | ✅ | ❌ | ⚠️ DSAR |

**Legenda:**
- ✅ = acesso direto via tela/RPC
- ⚠️ = acesso indireto (audit log obrigatório)
- ❌ = bloqueado pela RLS · não tem policy de SELECT

---

## 6. Permissions relevantes

| Permission | Quem tem | O que libera |
|---|---|---|
| `submit_medical_self` | colaborador, líder, rh | Submeter atestado |
| `submit_medical_for_subordinate` | líder, rh | Submeter pra outro |
| `view_medical_cid` | rh sênior, especialista DP | Ver CID, nome médico, baixar PDF |
| `validate_medical` | rh sênior, especialista DP | Validar/rejeitar atestado |
| `validate_medical_for_employer` | RH prestadora (permission_profile escopo) | Validar só do empregador específico |
| `view_audit_log` | DPO | Ver logs de visualização |
| `dsar_export` | DPO | Exportar dados pra atender LGPD Art. 18 |

---

## 7. Auditoria

### O que é auditado

| Evento | Onde |
|---|---|
| Submissão de atestado | `audit_log` (kind='medical_submit') |
| Visualização de CID por DP | `audit_log` (kind='medical_cid_view') |
| Download do PDF original | `audit_log` (kind='medical_pdf_download') |
| Validação | `audit_log` (kind='medical_validate') |
| Rejeição | `audit_log` (kind='medical_reject') |
| Geração de movimento automático | `audit_log` (kind='medical_auto_movement') |
| Export DSAR de atestados | `audit_log` (kind='dsar_medical_export') |

### O que NÃO é auditado

- Leitura normal da lista de atestados pelo próprio colaborador (seria poluído)
- Acesso à fila do DP (operação de rotina · auditar só ações específicas)

### Retenção do audit log

5 anos (igual aos atestados). Após 5 anos, audit log é anonimizado (remove `actor_user_id` direto, mantém `actor_email_hash`).

---

## 8. Retenção de dados

| Item | Prazo | Base legal |
|---|---|---|
| Atestado completo (com CID, PDF) | **5 anos** após emissão | CLT Art. 168 + LGPD Art. 16 |
| Auto-movimento gerado | 5 anos | Idem |
| Audit log de visualização | 5 anos | Boas práticas LGPD |
| Backup criptografado em região US | 90 dias | Recuperação de desastre |

Após o prazo:
- PDF original é **deletado** do bucket
- Row de `medical_certificates` é **anonimizada** (CID = NULL, doctor = NULL, file_storage_path = NULL)
- Mantém `days_off`, `starts_at`, `ends_at` (necessário pra calculadora de férias retroativa)

---

## 9. Cuidados com OCR e dados sensíveis

### 9.1 Tesseract WASM client-side

- Carregado on-demand (~3MB gzipped) só na página `/atestados/enviar`
- Arquivo PDF rasterizado via `pdfjs-dist` localmente
- Output texto fica apenas em memória JS · enviado ao backend já estruturado (CID, datas, médico)
- **Imagem nunca é enviada como base64** · só o arquivo binário pro storage

### 9.2 Qualidade do OCR

| Qualidade | Confiança | Comportamento |
|---|---|---|
| `excellent` | ≥ 95% | Pré-preenche sem warning |
| `good` | 80-95% | Pré-preenche com banner sutil "revisar" |
| `fair` | 60-80% | Pré-preenche + warning amber + priorização alta na fila DP |
| `poor` | < 60% | NÃO pré-preenche · obriga DP a digitar do zero |

### 9.3 Casos especiais

- **PDF protegido por senha**: bloqueia upload com mensagem clara ("Remova a senha antes de enviar")
- **Imagem rotacionada**: detecta via Tesseract orientation API, gira automaticamente
- **Múltiplas páginas**: extrai todas, concatena no `ocr_extracted` raw
- **iOS Safari < 16**: usa fallback de canvas menor (perde qualidade mas funciona)

---

## 10. DSAR · LGPD Art. 18

Quando colaborador (ou ex-colaborador) solicita acesso aos próprios dados médicos:

1. DPO recebe solicitação por canal externo
2. DPO abre `/admin/dsar/exportar/[cpf]`
3. Sistema gera ZIP contendo:
   - PDF de TODOS os atestados do solicitante
   - JSON estruturado com CID, datas, médico, hospital
   - Audit log de quem viu o CID dele
4. Audit log da operação registra `actor=dpo`, `target=cpf_hash`, `kind=dsar_medical_export`

⚠️ DSAR de atestados é **operação irreversível** (revela dados sensíveis). Bloqueada por design para usuários sem `dsar_export` permission.

---

## 11. Transferência internacional

Atestados ficam **somente no Brasil** (Supabase região South America · São Paulo).

Backup em região US (AWS S3 standard) **excluí campos sensíveis**:
- Inclui: row metadata, audit log, file index
- **Exclui**: PDF original, ocr_extracted raw text

Em caso de incidente que exija restore da região US, atestados precisarão ser reuploadados manualmente. Decisão consciente: privacidade > conveniência.

---

## 12. Notificação de incidente

Se houver suspeita de acesso não autorizado a atestados:

1. **Imediatamente**: DPO do controlador é notificado por email + telefone
2. **Até 4h**: contenção (suspender acessos suspeitos, rotacionar credenciais)
3. **Até 24h**: investigação inicial + comunicação interna
4. **Até 72h**: notificação à ANPD se houver risco aos titulares (LGPD Art. 48)
5. **Até 7 dias**: comunicação aos titulares afetados, se aplicável
6. **Até 30 dias**: relatório completo de incidente + plano de remediação

Contato emergencial 24/7: emergencia@solucoesr2.com.br

---

## 13. Direitos do titular (LGPD Art. 18)

| Direito | Como exercer | Prazo SLA |
|---|---|---|
| Confirmação de tratamento | Email pro DPO do controlador | 15 dias |
| Acesso aos atestados próprios | Tela `/minha-jornada/atestados` | Imediato |
| Acesso ao PDF original | Clicar em "Baixar" na tela | Imediato (audit log) |
| Correção de dado factual errado | Solicitar ao DP por email | 7 dias |
| Anonimização | Solicitar ao DPO · sujeito a retenção legal 5 anos | 15 dias |
| Eliminação | Apenas após 5 anos · antes disso, retenção CLT | 5 anos |
| Portabilidade | Export ZIP via DSAR | 15 dias |

---

## 14. Decisões de produto deliberadas

### Por que CID é categoria especial?

A LGPD Art. 11 lista explicitamente "dados referentes à saúde" como categoria especial, com requisitos mais rígidos:
- Tratamento só com consentimento específico ou hipóteses legais
- Vedação de tratamento discriminatório
- Notificação obrigatória de incidente

Por isso, CID nunca aparece em listas (mesmo pra própria pessoa) e fica sempre atrás de audit log.

### Por que líder não vê depois de enviar?

Decisão dura mas correta por 3 razões:

1. **LGPD**: minimização de acesso (Art. 6º, III)
2. **Confiança**: colaborador sabe que líder não tem acesso ao diagnóstico
3. **Operacional**: líder não precisa do CID pra gerenciar afastamento (só precisa saber "X está fora por N dias")

A exceção é quando líder é também RH com `view_medical_cid` (caso comum em PMEs com líderes acumulando funções).

### Por que não usar serviço de OCR externo?

Cogitamos Google Cloud Vision API, AWS Textract, Azure Form Recognizer. Decisão de **NÃO usar**:

- Categoria especial LGPD exige base legal mais rígida pra compartilhar com terceiros
- Risco de re-uso comercial dos dados pelos provedores (cláusulas opacas)
- Custo escala com volume (R$ 0,10 por página em média = R$ 1.500/mês a 15k atestados/ano)
- Tesseract WASM resolve 90% dos casos sem essas desvantagens

---

## 15. Mudanças desta política

Esta política pode ser atualizada periodicamente. Mudanças materiais (que afetem privacidade do titular) serão:
- Comunicadas no banner do app com 30 dias de antecedência
- Documentadas no histórico abaixo

---

## 16. Histórico de versões

| Versão | Data | Mudanças |
|---|---|---|
| 1.0 | 17 mai 2026 | Versão inicial · descreve modelo de 3 níveis implementado no schema v4 de atestados |

---

## 17. Contato

- **DPO do controlador**: definido por cada cliente
- **DPO operador (R2)**: dpo@solucoesr2.com.br
- **Emergência**: emergencia@solucoesr2.com.br
- **Suporte**: suporte@solucoesr2.com.br

---

*Esta política complementa a [política geral de privacidade](r2_people_privacy_policy.md) e a [política específica de 1:1s](r2_people_privacy_oneonones.md). Em caso de conflito, prevalece a interpretação mais restritiva (privacy by default).*
