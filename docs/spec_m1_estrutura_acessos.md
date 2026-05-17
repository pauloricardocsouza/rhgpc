# Spec · M1 · Estrutura Organizacional & Acessos

**Status:** pronto para execução em ambiente com Postgres 16
**Pré-requisitos:** migrations 00010 (h_schema_base) a 00361 (g3_rpcs_profile_requests) aplicadas
**Estimativa:** 1 sessão (~3-4h em ambiente preparado)

---

## 1. Objetivo

Portar para a camada Next.js as telas [r2_people_estrutura.html](../r2_people_estrutura.html) e [r2_people_acessos.html](../r2_people_acessos.html), adicionando o que falta no schema base:

1. **Tabela `job_roles`** (Cargos como entidade, não só `app_users.job_title` string)
2. **CRUD completo** para `employer_units`, `working_units`, `departments`, `job_roles`
3. **Tabela `permission_profiles`** com perfis customizáveis por tenant (extensão dos 5 papéis base RBAC)
4. **2 páginas Next.js** com layout, modais e tabelas

---

## 2. Schema novo

### 2.1 Tabela `job_roles`

```sql
-- migration: 00400_m1_schema_job_roles.sql

CREATE TABLE IF NOT EXISTS job_roles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(40) NOT NULL,                  -- 'ANALISTA-PLENO', 'GERENTE-FILIAL'
  display_name    VARCHAR(160) NOT NULL,                 -- 'Analista Pleno'
  level           VARCHAR(20),                           -- 'estagio', 'junior', 'pleno', 'senior', 'lider', 'gerencia', 'diretoria'
  cbo_code        VARCHAR(10),                           -- código CBO oficial (Ministério Trabalho)

  active          BOOLEAN NOT NULL DEFAULT TRUE,

  -- Faixa salarial sugerida (opcional, alimenta calculadora de custo M6)
  salary_min      NUMERIC(12,2),
  salary_max      NUMERIC(12,2),

  description     TEXT,
  responsibilities TEXT,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code),
  CONSTRAINT job_roles_salary_order CHECK (
    salary_min IS NULL OR salary_max IS NULL OR salary_max >= salary_min
  )
);

CREATE INDEX IF NOT EXISTS idx_job_roles_tenant ON job_roles(tenant_id);
CREATE INDEX IF NOT EXISTS idx_job_roles_active ON job_roles(tenant_id, active) WHERE active = TRUE;

-- Trigger updated_at (helper já existe em 00010_h_schema_base)
CREATE TRIGGER trg_job_roles_updated_at
  BEFORE UPDATE ON job_roles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Adicionar FK opcional em app_users para job_role_id (mantém job_title como fallback texto)
ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS job_role_id UUID REFERENCES job_roles(id);

CREATE INDEX IF NOT EXISTS idx_app_users_job_role
  ON app_users(job_role_id) WHERE job_role_id IS NOT NULL;
```

### 2.2 Tabela `permission_profiles`

```sql
-- migration: 00401_m1_schema_permission_profiles.sql

CREATE TABLE IF NOT EXISTS permission_profiles (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,

  code            VARCHAR(60) NOT NULL,                  -- 'rh_prestadora_labuta'
  display_name    VARCHAR(160) NOT NULL,                 -- 'RH Prestadora · Labuta'
  base_role       app_user_role NOT NULL,                -- ponto de partida (estende esse papel)
  description     TEXT,

  -- Escopo opcional: limitar perfil a um employer_unit específico
  scope_employer_unit_id UUID REFERENCES employer_units(id),

  -- Lista de permission codes adicionais além do que vem do base_role
  -- Ex: ['validate_medical_for_employer', 'view_oneonones_metadata_by_employer']
  extra_permissions TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],

  active          BOOLEAN NOT NULL DEFAULT TRUE,

  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (tenant_id, code)
);

CREATE INDEX IF NOT EXISTS idx_perm_profiles_tenant ON permission_profiles(tenant_id);

-- FK opcional em app_users para profile (sobrepõe role se presente)
ALTER TABLE app_users
  ADD COLUMN IF NOT EXISTS permission_profile_id UUID REFERENCES permission_profiles(id);

CREATE INDEX IF NOT EXISTS idx_app_users_perm_profile
  ON app_users(permission_profile_id) WHERE permission_profile_id IS NOT NULL;

-- Atualizar user_has_permission() para considerar profile.extra_permissions
CREATE OR REPLACE FUNCTION user_has_permission(p_permission VARCHAR)
RETURNS BOOLEAN LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public AS $$
DECLARE
  v_user app_users;
  v_has BOOLEAN;
BEGIN
  SELECT * INTO v_user FROM app_users
    WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN FALSE; END IF;

  -- 1. Checa permissão herdada do base role
  SELECT EXISTS (
    SELECT 1 FROM role_permissions rp
    JOIN permissions p ON p.code = rp.permission_code
    WHERE rp.role = v_user.role
      AND rp.permission_code = p_permission
      AND p.active = TRUE
  ) INTO v_has;

  IF v_has THEN RETURN TRUE; END IF;

  -- 2. Checa permissão extra do profile (se houver profile)
  IF v_user.permission_profile_id IS NOT NULL THEN
    SELECT (p_permission = ANY(extra_permissions)) INTO v_has
      FROM permission_profiles
      WHERE id = v_user.permission_profile_id AND active = TRUE;
    IF COALESCE(v_has, FALSE) THEN RETURN TRUE; END IF;
  END IF;

  RETURN FALSE;
END;
$$;
```

---

## 3. RPCs CRUD

Padrão: cada entidade tem `list`, `get`, `create`, `update`, `archive` (soft-delete via `active = FALSE`).

### 3.1 RPCs `employer_units`

```sql
-- migration: 00402_m1_rpcs_employer_units.sql

CREATE OR REPLACE FUNCTION rpc_employer_units_list()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user app_users; v_items JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT (is_super_admin() OR v_user.role IN ('diretoria', 'rh')) THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', eu.id, 'code', eu.code, 'legal_name', eu.legal_name,
    'trade_name', eu.trade_name, 'cnpj', eu.cnpj, 'ie', eu.ie,
    'unit_type', eu.unit_type, 'city', eu.city, 'state_uf', eu.state_uf,
    'active', eu.active,
    'headcount', (SELECT COUNT(*) FROM app_users au WHERE au.employer_unit_id = eu.id AND au.active = TRUE)
  ) ORDER BY eu.legal_name), '[]'::jsonb) INTO v_items
    FROM employer_units eu WHERE eu.tenant_id = v_user.tenant_id;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END; $$;

CREATE OR REPLACE FUNCTION rpc_employer_unit_create(
  p_code VARCHAR, p_legal_name VARCHAR, p_trade_name VARCHAR DEFAULT NULL,
  p_cnpj VARCHAR DEFAULT NULL, p_ie VARCHAR DEFAULT NULL,
  p_unit_type unit_type DEFAULT 'matriz', p_city VARCHAR DEFAULT NULL, p_state_uf VARCHAR DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user app_users; v_id UUID;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT (is_super_admin() OR v_user.role = 'diretoria') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;
  IF p_code IS NULL OR length(trim(p_code)) = 0 THEN
    RETURN jsonb_build_object('error', 'invalid_value', 'field', 'code');
  END IF;
  IF p_legal_name IS NULL OR length(trim(p_legal_name)) = 0 THEN
    RETURN jsonb_build_object('error', 'invalid_value', 'field', 'legal_name');
  END IF;
  IF p_cnpj IS NOT NULL AND p_cnpj !~ '^[0-9]{14}$' THEN
    RETURN jsonb_build_object('error', 'invalid_value', 'field', 'cnpj');
  END IF;

  INSERT INTO employer_units (tenant_id, code, legal_name, trade_name, cnpj, ie, unit_type, city, state_uf)
    VALUES (v_user.tenant_id, upper(p_code), p_legal_name, p_trade_name, p_cnpj, p_ie, p_unit_type, p_city, upper(p_state_uf))
    RETURNING id INTO v_id;

  INSERT INTO audit_log (tenant_id, actor_user_id, action, entity_table, entity_id, after_data)
    VALUES (v_user.tenant_id, v_user.id, 'insert', 'employer_units', v_id, jsonb_build_object('code', p_code, 'legal_name', p_legal_name));

  RETURN jsonb_build_object('ok', TRUE, 'id', v_id);
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('error', 'duplicate_code');
END; $$;

-- rpc_employer_unit_update, rpc_employer_unit_archive seguem o mesmo padrão.
GRANT EXECUTE ON FUNCTION rpc_employer_units_list TO authenticated;
GRANT EXECUTE ON FUNCTION rpc_employer_unit_create TO authenticated;
```

### 3.2 RPCs `working_units`, `departments`, `job_roles`

Mesmo padrão. Adicionais relevantes:

- `rpc_working_units_list(p_employer_unit_id UUID DEFAULT NULL)` · filtro opcional por empregador
- `rpc_departments_list(p_working_unit_id UUID DEFAULT NULL)` · filtro opcional por unidade
- `rpc_departments_tree()` · retorna árvore hierárquica completa (parent_id)
- `rpc_job_roles_list(p_active_only BOOLEAN DEFAULT TRUE)` · filtro de ativos

### 3.3 RPCs `permission_profiles`

```sql
-- migration: 00403_m1_rpcs_permission_profiles.sql

CREATE OR REPLACE FUNCTION rpc_permission_profiles_list()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user app_users; v_items JSONB;
BEGIN
  SELECT * INTO v_user FROM app_users WHERE id = current_user_id();
  IF v_user.id IS NULL THEN RETURN jsonb_build_object('error', 'not_authenticated'); END IF;
  IF NOT (is_super_admin() OR v_user.role = 'diretoria') THEN
    RETURN jsonb_build_object('error', 'permission_denied');
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', pp.id, 'code', pp.code, 'display_name', pp.display_name,
    'base_role', pp.base_role, 'description', pp.description,
    'scope_employer_unit_id', pp.scope_employer_unit_id,
    'scope_employer_name', (SELECT legal_name FROM employer_units WHERE id = pp.scope_employer_unit_id),
    'extra_permissions', pp.extra_permissions, 'active', pp.active,
    'user_count', (SELECT COUNT(*) FROM app_users au WHERE au.permission_profile_id = pp.id AND au.active = TRUE)
  ) ORDER BY pp.display_name), '[]'::jsonb) INTO v_items
    FROM permission_profiles pp WHERE pp.tenant_id = v_user.tenant_id;

  RETURN jsonb_build_object('ok', TRUE, 'items', v_items);
END; $$;

CREATE OR REPLACE FUNCTION rpc_permission_profile_create(
  p_code VARCHAR, p_display_name VARCHAR, p_base_role app_user_role,
  p_description TEXT DEFAULT NULL, p_scope_employer_unit_id UUID DEFAULT NULL,
  p_extra_permissions TEXT[] DEFAULT ARRAY[]::TEXT[]
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
-- ... seguir mesmo padrão de validação + audit log
$$;
```

---

## 4. Testes

Criar [supabase/tests/00400_m1_org_structure.sql](../supabase/tests/) com:

```sql
BEGIN;

-- Helpers de teste (já devem existir, criar se não)
-- test_login(uuid), test_logout()

-- Setup: tenant + diretoria + rh + colaborador + 2 employer_units pré-existentes
INSERT INTO tenants (id, slug, legal_name, display_name) VALUES
  ('00m1aaaa-0000-0000-0000-000000000001', 'm1test', 'M1 Test Tenant', 'M1 Test');

INSERT INTO app_users (id, tenant_id, email, full_name, role, auth_user_id) VALUES
  ('00m1bbbb-0000-0000-0000-000000000001', '00m1aaaa-0000-0000-0000-000000000001', 'diretor@m1.test', 'Diretor M1', 'diretoria', '00m1cccc-0000-0000-0000-000000000001'),
  ('00m1bbbb-0000-0000-0000-000000000002', '00m1aaaa-0000-0000-0000-000000000001', 'rh@m1.test', 'RH M1', 'rh', '00m1cccc-0000-0000-0000-000000000002'),
  ('00m1bbbb-0000-0000-0000-000000000003', '00m1aaaa-0000-0000-0000-000000000001', 'colab@m1.test', 'Colab M1', 'colaborador', '00m1cccc-0000-0000-0000-000000000003');

-- Cenário 1 · diretoria cria employer_unit
SELECT test_login('00m1cccc-0000-0000-0000-000000000001');
SELECT _assert_eq(
  (rpc_employer_unit_create('GPC-MATRIZ', 'GPC Matriz Ltda', 'GPC', '12345678000190', NULL, 'matriz', 'Salvador', 'BA')->>'ok')::TEXT,
  'true', 'diretoria pode criar employer_unit'
);

-- Cenário 2 · rh tenta criar e é bloqueado
SELECT test_login('00m1cccc-0000-0000-0000-000000000002');
SELECT _assert_eq(
  rpc_employer_unit_create('TESTE', 'Teste Ltda')->>'error',
  'permission_denied', 'rh não pode criar employer_unit'
);

-- Cenário 3 · diretoria cria job_role com faixa salarial
SELECT test_login('00m1cccc-0000-0000-0000-000000000001');
SELECT _assert_eq(
  (rpc_job_role_create('ANALISTA-PLENO', 'Analista Pleno', 'pleno', '2521-05', 4500.00, 7500.00)->>'ok')::TEXT,
  'true', 'cria job_role com faixa válida'
);

-- Cenário 4 · faixa salarial invertida é rejeitada
SELECT _assert_eq(
  rpc_job_role_create('INVALIDO', 'Inválido', NULL, NULL, 7500.00, 4500.00)->>'error',
  'invalid_value', 'rejeita faixa salarial invertida'
);

-- Cenário 5 · criar permission_profile com escopo por empregador
SELECT _assert_eq(
  (rpc_permission_profile_create(
    'rh_prestadora_labuta', 'RH Prestadora · Labuta', 'rh',
    'Acesso restrito a colaboradores da Labuta',
    '00m1eeee-0000-0000-0000-000000000001'::UUID,
    ARRAY['validate_medical_for_employer', 'view_oneonones_metadata_by_employer']
  )->>'ok')::TEXT,
  'true', 'cria permission_profile com escopo'
);

-- Cenário 6 · user com profile herda permissões extras
UPDATE app_users SET permission_profile_id = ... WHERE id = ...;
SELECT _assert_eq(
  user_has_permission('validate_medical_for_employer')::TEXT, 'true',
  'profile concede permissão extra'
);

-- Cenário 7 · arquivamento mantém histórico
SELECT _assert_eq(
  (rpc_employer_unit_archive('...')->>'ok')::TEXT, 'true',
  'arquivamento (active=false)'
);

-- Cenário 8 · cross-tenant blocked
-- (criar outro tenant + user, tentar acessar units do tenant original)

ROLLBACK;
```

**Meta:** 25-30 testes cobrindo CRUD + permissões + validações + cross-tenant.

---

## 5. Adapter TypeScript

Criar [src/lib/r2/org.ts](../src/lib/r2/):

```typescript
import { callRpc, type RpcResponse } from './base'

export interface EmployerUnit {
  id: string
  code: string
  legal_name: string
  trade_name: string | null
  cnpj: string | null
  ie: string | null
  unit_type: 'matriz' | 'filial' | 'cd' | 'office' | 'rural' | 'other'
  city: string | null
  state_uf: string | null
  active: boolean
  headcount: number
}

export interface WorkingUnit { /* análogo */ }
export interface Department { /* com parent_id, children?: Department[] */ }
export interface JobRole {
  id: string; code: string; display_name: string; level: string | null;
  cbo_code: string | null; salary_min: number | null; salary_max: number | null;
  description: string | null; active: boolean
}
export interface PermissionProfile {
  id: string; code: string; display_name: string; base_role: AppUserRole;
  description: string | null; scope_employer_unit_id: string | null;
  scope_employer_name: string | null; extra_permissions: string[];
  active: boolean; user_count: number
}

export const EmployerUnits = {
  list: () => callRpc<{ items: EmployerUnit[] }>('rpc_employer_units_list'),
  create: (input: Omit<EmployerUnit, 'id' | 'active' | 'headcount'>) =>
    callRpc<{ id: string }>('rpc_employer_unit_create', { ... }),
  update: (id: string, patch: Partial<EmployerUnit>) =>
    callRpc<{ ok: true }>('rpc_employer_unit_update', { p_id: id, ...patch }),
  archive: (id: string) =>
    callRpc<{ ok: true }>('rpc_employer_unit_archive', { p_id: id }),
}

export const WorkingUnits = { /* análogo */ }
export const Departments = {
  list: (workingUnitId?: string) => callRpc(...),
  tree: () => callRpc<{ tree: DepartmentNode[] }>('rpc_departments_tree'),
  // ...
}
export const JobRoles = { /* análogo */ }
export const PermissionProfiles = { /* análogo */ }
```

Exportar tudo em [src/lib/r2/index.ts](../src/lib/r2/index.ts).

---

## 6. Páginas Next.js

### 6.1 `/admin/estrutura`

Referência visual: [r2_people_estrutura.html](../r2_people_estrutura.html)

- 3 abas (Filiais, Departamentos, Cargos) + 1 oculta (Empregadores, super_admin/diretoria)
- KPIs no topo: total ativo por categoria
- Tabela com colunas: código, nome, headcount, status
- Botão "+ Novo X" abre modal
- Inline edit ao clicar na linha
- Empty state amigável

**Estrutura:**
```
src/app/admin/estrutura/
├── page.tsx                  # tabs + container
├── EmployerUnitsTab.tsx
├── WorkingUnitsTab.tsx
├── DepartmentsTab.tsx
├── JobRolesTab.tsx
├── EntityFormModal.tsx       # modal genérico CRUD
└── ArchiveConfirmDialog.tsx
```

### 6.2 `/admin/acessos`

Referência visual: [r2_people_acessos.html](../r2_people_acessos.html)

- Lista de `permission_profiles` (cards ou tabela)
- Cada card mostra: nome, base_role, escopo (se houver), # de usuários, # de permissões extras
- Botão "+ Novo perfil" abre wizard 3 passos:
  1. Dados básicos (código, nome, descrição, base_role)
  2. Escopo (opcional: limitar a um employer_unit)
  3. Permissões extras (checklist do catálogo `permissions` filtrado por módulo)
- Botão "Atribuir a usuários" abre seletor de `app_users`

**Estrutura:**
```
src/app/admin/acessos/
├── page.tsx
├── ProfileCard.tsx
├── ProfileFormWizard.tsx
├── PermissionPicker.tsx
└── AssignUsersDialog.tsx
```

---

## 7. Critérios de aceitação

- [ ] Migrations 00400-00403 aplicam idempotentemente
- [ ] Teste 00400_m1_org_structure.sql passa com 25+ asserts verdes
- [ ] `tsc --noEmit --strict` sem erros após adicionar src/lib/r2/org.ts e as páginas
- [ ] Páginas `/admin/estrutura` e `/admin/acessos` renderizam sem erros
- [ ] CRUD funcional (criar → editar → arquivar) para as 5 entidades
- [ ] Permissões respeitadas (rh não cria, só diretoria; colaborador 403)
- [ ] Modais validam input client-side antes de chamar RPC
- [ ] Erros da RPC mapeados para mensagens PT-BR
- [ ] Audit log registra todas as criações/edições/arquivamentos
- [ ] Empty states amigáveis quando lista vazia
- [ ] Doc da sessão criada em `docs/sessao_m1.md`
- [ ] INDEX §10 atualizado (mover M1 do parking lot para "entregues")

---

## 8. Pontos de atenção

- **Migration ordem**: 00400 (job_roles) deve vir antes de 00401 (perm_profiles porque pode referenciar), e ambas antes das RPCs (00402+)
- **Backfill**: `app_users.job_role_id` é NULL para todos · não criar trigger de obrigatoriedade
- **Cuidado com `job_title`**: manter o campo string como fallback enquanto migra dados existentes
- **Permission_profiles.extra_permissions é TEXT[]**: garantir que valida contra catálogo `permissions` na RPC de create (ou aceitar livre e validar na leitura · decidir)
- **Sidebar nav-item**: adicionar entry "Estrutura" e "Acessos" no `rpc_navbar` (sessão B3) ou no helper de filtro · só visível para diretoria/super_admin
- **Cross-tenant**: testar que diretoria de tenant X não vê units de tenant Y

---

## 9. Próximas sessões desbloqueadas após M1

- **M6 · Folha & Custo** · depende de `job_roles.salary_min/max` (alimenta calculadora) e `units.tax_regime`
- **M2 · Movimentações** · usa `job_roles` na promoção (mudar de Junior para Pleno)
- **Acessos refinados em todos os módulos** · uma vez que `permission_profiles` existem, todos os checks podem usar `user_has_permission()` com extras

---

**Comando de execução** (em sandbox Linux com Postgres):

```bash
# Aplicar migrations
for f in supabase/migrations/00400*.sql supabase/migrations/00401*.sql \
         supabase/migrations/00402*.sql supabase/migrations/00403*.sql; do
  psql $DATABASE_URL -v ON_ERROR_STOP=1 -f $f
done

# Rodar teste
psql $DATABASE_URL -v ON_ERROR_STOP=1 -f supabase/tests/00400_m1_org_structure.sql | grep -E "PASS|FAIL"

# Validar TS
cd src && tsc --noEmit --strict
```
