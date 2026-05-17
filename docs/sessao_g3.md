# Sessão G3 · Solicitações de alteração de dados pessoais

Workflow completo para o colaborador solicitar mudanças nos próprios dados de contato (telefone, email pessoal, endereço, contato de emergência, foto), com aprovação do RH antes de aplicar à ficha.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Campos editáveis | Tudo, inclusive fotografia | Pessoal/contato; demais dados (CPF, admissão) seguem só RH |
| Workflow | Solicitação que RH aprova | Mantém RH como guardião dos dados oficiais; colaborador propõe |
| Concorrência | 1 solicitação pendente por (colaborador, campo) | Evita duplicações; cancel libera |
| Auditoria | Tabela própria de requests guarda old/new + reviewer | Histórico imutável independente do audit_log geral |
| Storage de foto | Bucket privado `employee-photos` | Privacidade; signed URL para visualização |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| Schema (tabela + enums + bucket) | `supabase/migrations/00360_g3_schema_profile_requests.sql` | 102 |
| 6 RPCs + 2 helpers | `supabase/migrations/00361_g3_rpcs_profile_requests.sql` | 400 |
| Testes | `supabase/tests/00361_g3_profile_requests.sql` | 375 |
| Modal genérico de solicitação | `src/components/profile/ProfileChangeRequestModal.tsx` | 359 |
| Painel "minhas solicitações" | `src/components/profile/MyProfileRequests.tsx` | 211 |
| Página de aprovação | `src/app/admin/aprovacoes/page.tsx` | 275 |
| Botões + seção na `/minha-jornada` | `src/app/minha-jornada/page.tsx` | +85 |
| Adapter | `src/lib/r2/employees.ts` | +95 |

### Schema

**Colunas novas em `employees`** (idempotentes via `ADD COLUMN IF NOT EXISTS`):
- `personal_email`, `emergency_contact_name`, `emergency_contact_phone`, `emergency_contact_relation`, `photo_storage_path`

**Enums:**
- `profile_change_field`: phone_mobile, phone_home, personal_email, residence_address, emergency_contact, photo
- `profile_change_status`: pending, approved, rejected, canceled

**Tabela `employee_profile_change_requests`:**
- `tenant_id`, `employee_id`, `requested_by` (app_user)
- `field`, `old_value` (JSONB snapshot do valor atual no momento da criação), `new_value` (JSONB)
- `pending_photo_path` (para field='photo' antes de aprovação)
- `status`, `reviewed_by`, `reviewed_at`, `rejection_reason`
- Partial unique index `uq_pcr_one_pending_per_field` em `(employee_id, field) WHERE status='pending'` — garante 1 pendente por campo

**Bucket `employee-photos`** criado idempotentemente via `INSERT INTO storage.buckets ... ON CONFLICT DO NOTHING` com `EXCEPTION WHEN invalid_schema_name` para tolerar ambiente local sem schema storage.

### RPCs

| RPC | Quem chama | O que faz |
|---|---|---|
| `rpc_my_profile_request_create(field, new_value, photo_path?)` | colaborador com ficha | Valida, snapshot do old_value, insere pending. Bloqueia duplicação |
| `rpc_my_profile_requests_list(limit)` | qualquer authenticated | Lista próprias solicitações com reviewer_name |
| `rpc_my_profile_request_cancel(id)` | dono | Cancela pendente (libera a unique) |
| `rpc_profile_requests_pending_list()` | rh/diretoria/SA | Fila enriquecida com employee_name |
| `rpc_profile_request_approve(id)` | rh/diretoria/SA | Aplica em `employees` e marca approved |
| `rpc_profile_request_reject(id, reason)` | rh/diretoria/SA | Marca rejected; razão >=3 chars |

Helpers internos:
- `pcr_validate_value(field, value)` retorna NULL ou código de erro (phone_invalid, email_invalid, address_invalid, emergency_name_invalid, emergency_phone_invalid)
- `pcr_snapshot_current_value(employee_id, field)` retorna JSONB do valor atual para gravar como old_value

### Frontend

**`ProfileChangeRequestModal`** · Modal full-screen genérico aceita prop `field` e renderiza o input apropriado:
- `phone_mobile`/`phone_home`: input tel com normalização para dígitos
- `personal_email`: input email
- `residence_address`: textarea
- `emergency_contact`: 3 inputs (nome, telefone, parentesco)
- `photo`: upload com preview, max 5MB, JPG/PNG/WEBP. Upload via stub `uploadProfilePhoto()` (deve virar `supabase.storage.from('employee-photos').upload()` no deploy real)

Erros do backend mapeados para PT-BR (11 códigos).

**`MyProfileRequests`** · Painel listando as próprias solicitações com:
- Badge de status (pending amber, approved emerald, rejected red, canceled zinc)
- Diff resumido (line-through no old_value + bold no new_value)
- Botão cancelar para pendentes (com confirm nativo)
- Motivo da rejeição quando aplicável
- Nome do revisor e data quando aplicável

**`/admin/aprovacoes`** · Fila do RH:
- Cards com nome do colaborador, cargo, campo solicitado, diff visual
- Botão **Aprovar** (com confirm) e **Rejeitar** (prompt de motivo)
- Tela 403 amigável se colaborador comum tenta acessar
- Empty state quando fila está vazia

**Integração na `/minha-jornada`:**
- 6 botões "Solicitar alteração" abaixo dos dados pessoais (um por campo)
- Nova seção "Solicitações de alteração" entre dados pessoais e PDIs
- Modal acionado abre full-screen; ao criar, fecha e refresca a lista

## Testes (18/18 PASS)

| Teste | Cobertura |
|---|---|
| T01 | `not_authenticated` |
| T02 | `employee_not_linked` (sem ficha vinculada) |
| T03 | Validações: email, phone, address, emergency_name, emergency_phone |
| T04 | photo sem path bloqueado (`photo_path_required`) |
| T05 | Criação com sucesso |
| T06 | `pending_request_exists` (unique index parcial) |
| T07 | Lista própria com old_value snapshot |
| T08 | Cancel libera unique e permite recriar |
| T09 | Cancel bloqueado após review |
| T10 | Colaborador comum bloqueado em pending_list |
| T11 | RH vê fila enriquecida |
| T12 | Approve aplica `phone_mobile` em employees |
| T13 | Approve aplica `personal_email` |
| T14 | Approve aplica `residence_address` |
| T15 | Approve aplica `emergency_contact` (3 colunas) |
| T16 | Approve photo move `pending_photo_path` → `photo_storage_path` |
| T17 | Reject exige razão >=3 e grava em `rejection_reason` |
| T18 | Cross-tenant bloqueado em approve |

## Fluxo prático

1. Colaborador na `/minha-jornada` clica em "Email pessoal" abaixo dos dados pessoais
2. Modal full-screen abre com campo de email; digita "novo@gmail.com"
3. Clica em "Enviar solicitação"
4. Modal fecha; seção "Solicitações de alteração" mostra novo item com badge amber "Pendente"
5. RH em `/admin/aprovacoes` vê o card: "JOÃO DA SILVA · Analista · Email pessoal · ~~antigo@gmail.com~~ → **novo@gmail.com**"
6. RH clica "Aprovar" → confirm → backend aplica em `employees.personal_email` e marca approved
7. Colaborador volta à `/minha-jornada` → badge agora é emerald "Aprovada", com "Revisada por RH em 17/05/2026"

**Caso de rejeição:** RH clica "Rejeitar" → prompt pede motivo (mín 3 chars) → "documento não confere" → request marcada rejected com motivo visível para o colaborador.

**Caso de foto:** colaborador seleciona JPG, vê preview, envia → `uploadProfilePhoto()` retorna path no bucket, RPC grava `pending_photo_path`. Ao aprovar, RPC move o path para `employees.photo_storage_path`.

## Pontos abertos para evolução

- **`uploadProfilePhoto` é stub**: precisa virar `supabase.storage.from('employee-photos').upload(path, file)` quando D1 (auth real) for feito. Path padrão sugerido: `<tenant_id>/<employee_id>/<uuid>.<ext>`
- **Política de retenção** das fotos rejeitadas: hoje o arquivo fica órfão no bucket. Job de cleanup periódico seria adequado
- **Notificações**: ideal notificar o RH quando há nova solicitação e o colaborador quando há review (fica para H1)
- **Filtros na fila do RH**: por colaborador, por campo, por data. Cresce relevante com mais usuários
