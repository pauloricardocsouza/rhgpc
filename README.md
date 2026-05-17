# R2 People · GPC

SaaS multi-tenant de gestão de pessoas para PMEs brasileiras. Cliente âncora: **Grupo Pinto Cerqueira (GPC)** · 367 colaboradores · 14 unidades · Bahia.

Este repositório hospeda **duas camadas** do mesmo produto:

| Camada | O que é | Tech | Deploy |
|---|---|---|---|
| **1 · Protótipos visuais** | 42 telas single-file HTML para validação com clientes | Tailwind inline + Sora + JetBrains Mono | [rh.solucoesr2.com.br](https://rh.solucoesr2.com.br) (GitHub Pages) |
| **2 · Codebase produtivo** | Implementação real com Postgres/RLS/RPCs + Next.js 14 | Supabase + Next.js + FastAPI worker | Vercel + Supabase (ainda não em prod) |

A Camada 1 é a fonte de verdade visual (validação rápida com Karla/Ricardo/clientes). A Camada 2 é a implementação real, portada gradualmente a partir das telas aprovadas.

Ver [`r2_people_INDEX.md`](r2_people_INDEX.md) §14 para mapa completo de paridade e plano de portabilidade.

---

## Estado atual

### Camada 1 · HTMLs (`r2_people_*.html`)

- **42 telas** em 11 módulos funcionais · ~2,33 MB
- **10 schemas SQL** de design (v1 → v6 + RLS + RPC builder + seed inicial)
- **5 docs MD** (INDEX, architecture_roadmap, privacy_policy, wireframes_mvp, analise_correcoes)
- Acessíveis abrindo qualquer `r2_people_*.html` no navegador ou via [rh.solucoesr2.com.br](https://rh.solucoesr2.com.br)

### Camada 2 · Next.js (`src/`, `supabase/`, `worker/`)

- **12 páginas Next.js** em `src/app/**/page.tsx` (admin, dashboard, drill, meus-reconhecimentos, minha-equipe, minha-jornada, pessoas, etc.)
- **~20 componentes React** em `src/components/{employees,team,profile,navbar,imports}/`
- **10 módulos do adapter TS** em `src/lib/r2/` (base, employees, modules, navbar, ninebox, onboarding, pdi, recognition, imports, index)
- **32 migrations Supabase** em `supabase/migrations/` (incrementais e idempotentes)
- **170 testes SQL passando** em `supabase/tests/` · BEGIN/ROLLBACK isolados
- **Worker FastAPI** em `worker/` para OCR de fichas via Tesseract + pdftoppm

### Cobertura por sessão (Camada 2)

| Sessão | Módulo | Testes |
|---|---|---|
| H · base | tenants, app_users, employer/working units, departments, RBAC, audit | legado |
| H2 · recognition | feed de reconhecimentos (categorias, posts, reactions) | legado |
| J · pdi | planos de desenvolvimento individual + storage de evidências | legado |
| K · onboarding | jornadas, etapas, checklists | legado |
| L · modules | catálogo de módulos + `module_activations` + helpers de gate | legado |
| A1 · module checks | gate de módulo em 31 RPCs | 32/32 |
| A2 · 9-Box | matriz 3x3/5x5, ciclos, snapshots imutáveis | 40/40 |
| B2 · admin de módulos | soft-disable, 5 RPCs admin | 35/35 |
| B3 · navbar dinâmica | `rpc_my_navbar` filtrado por papel + módulos | 25/25 |
| C4 · adapter TS | 10 módulos tipados, TS strict zero erros | - |
| E1 · ficha de empregado | 40+ colunas, 9 RPCs, página LinkedIn-style | 30 |
| E2 · /pessoas/novo | validação CPF mod 11, CEP, formulário 5 seções | 6 |
| E4 · OCR | worker Python pdftoppm 300dpi → tesseract → parser | 20 |
| E5 · storage PDFs | bucket privado, retenção 30d, view de stats | 16 |
| E6 · preview PDF | modal react-pdf via pdf.js CDN | - |
| F1 · gestão + equipe | `rpc_employees_gestao_summary`, página /minha-equipe | 18 |
| F2 · ações do gestor | dropdown Criar PDI / Reconhecer / 9-Box ad-hoc | - |
| F3 · dashboard equipe | `rpc_my_team_dashboard` | 12 |
| F4 · dashboard tenant | `rpc_tenant_dashboard` | 14 |
| F5 · inline edit PDIs | `PdiCardEditable` view↔edit | - |
| F6 · drilldown | `rpc_dashboard_drill` (5 kinds) | 15 |
| G1 · minha jornada | `rpc_my_journey`, página `/minha-jornada` | 14 |
| G2 · feed enviados | `rpc_my_sent_recognitions` | 7 |
| G3 · solicitações pessoais | 6 RPCs + workflow aprovação | 18 |

**Total Camada 2:** 32 migrations · 170/170 testes · ~13k linhas TS/TSX · ~25k linhas SQL.

---

## Estrutura do repo

```
rhgpc/
├── CNAME                              # rh.solucoesr2.com.br
├── index.html                         # demo visual (entry point GitHub Pages)
│
├── r2_people_*.html                   # 42 telas (Camada 1)
├── r2_people_INDEX.md                 # índice consolidado (sempre atualizado)
├── r2_people_schema_v1..v6.sql        # 10 schemas SQL de design
├── r2_people_*.md                     # 4 docs (architecture_roadmap, privacy_policy, wireframes_mvp, analise_correcoes)
├── r2_people_completo_v2.4.zip        # bundle dos artefatos da Camada 1
│
├── src/                               # Camada 2 · Next.js
│   ├── app/                           # App Router
│   │   ├── admin/{modulos,aprovacoes}/page.tsx
│   │   ├── dashboard/{page.tsx, drill/[kind]/[value]/page.tsx}
│   │   ├── meus-reconhecimentos/page.tsx
│   │   ├── minha-equipe/page.tsx
│   │   ├── minha-jornada/page.tsx
│   │   └── pessoas/{page.tsx, [id]/page.tsx, novo/page.tsx, importar/...}
│   ├── components/{employees,team,profile,navbar,imports}/
│   └── lib/
│       ├── r2/                        # adapter tipado (10 módulos)
│       ├── supabase.ts                # stub (substituir em D1)
│       └── validation.ts              # CPF mod 11, CEP, datas
│
├── supabase/                          # Camada 2 · backend
│   ├── 00_local_setup.sql             # stub auth/storage para dev local
│   ├── migrations/                    # 32 arquivos numerados
│   └── tests/                         # 20 arquivos · 170 testes BEGIN/ROLLBACK
│
├── worker/                            # Camada 2 · OCR (FastAPI)
│   ├── README.md
│   ├── requirements.txt
│   └── worker.py
│
├── docs/                              # docs por sessão (Camada 2)
│   ├── sessao_a1.md ... sessao_g3.md  # 22 sessões
│
├── MIGRATION_PROMPT.md                # prompt para reonboarding em nova sessão
├── README.md                          # este arquivo
├── package.json.example
├── tailwind.config.ts
├── tsconfig.json
├── .env.example
└── .gitignore
```

---

## Como usar cada camada

### Camada 1 (HTMLs) · validação rápida

```bash
# Abre direto no navegador
open r2_people_home.html

# Ou serve localmente
python -m http.server 8000
# acessa http://localhost:8000/r2_people_home.html
```

Cada HTML é autônomo · sem build, sem backend, sem dependências externas.

### Camada 2 (Next.js) · desenvolvimento real

**Pré-requisitos:** Node 18+, Postgres 14+ (ou projeto Supabase), Python 3.10+ para o worker.

```bash
# 1. Criar projeto Next.js novo (este repo tem só arquivos de domínio)
npx create-next-app@latest meu-r2-people --typescript --tailwind --app --src-dir

# 2. Copiar arquivos deste repo
cp -r src/* meu-r2-people/src/
cp -r supabase meu-r2-people/
cp tsconfig.json tailwind.config.ts .env.example meu-r2-people/

# 3. Instalar deps (ver package.json.example)
cd meu-r2-people
npm install @supabase/ssr @supabase/supabase-js lucide-react xlsx

# 4. Preencher .env.local
cp .env.example .env.local

# 5. Aplicar migrations
for f in supabase/migrations/*.sql; do
  psql $DATABASE_URL -v ON_ERROR_STOP=1 -f $f
done

# 6. Rodar testes
for f in supabase/tests/*.sql; do
  psql $DATABASE_URL -v ON_ERROR_STOP=1 -f $f | grep -E "PASS|FAIL"
done

# 7. Subir worker OCR
cd ../worker && pip install -r requirements.txt && uvicorn worker:app
```

---

## Convenções (válidas para as duas camadas)

- **PT-BR** em UI/labels/mensagens visíveis
- **Erros em `snake_case` ASCII** nas RPCs (`module_inactive`, `permission_denied`, `cross_tenant_blocked`)
- **Idempotente** em scripts (`CREATE OR REPLACE`, `ON CONFLICT DO UPDATE`)
- **Sem em-dashes** em texto, comentários ou SQL · usar `-`, `:` ou `·`
- **Sem acentos em comentários SQL** (compatibilidade de encoding)
- **`BEGIN ... ROLLBACK`** em todos os testes (não suja o banco)
- **Auditoria automática** via trigger `audit_change()` em tabelas críticas
- **Cores semânticas**: emerald=bom, amber=atenção, red=alerta, blue=info, zinc=neutro

---

## RBAC

5 papéis: `super_admin`, `diretoria`, `rh`, `lider`, `colaborador`.

| Papel | Escopo |
|---|---|
| `super_admin` | acesso total cross-tenant (staff R2) |
| `diretoria` | admin do próprio tenant (`/admin/modulos`, dashboards) |
| `rh` | operação dia-a-dia |
| `lider` | próprio time (recursivo até 10 níveis) |
| `colaborador` | próprio perfil + auto-avaliações |

Helpers SQL chave: `current_user_id()`, `current_tenant_id()`, `is_super_admin()`, `user_is_manager_of()`, `user_has_permission()`, `module_is_active_for_me()`.

Toda RPC SECURITY DEFINER segue o padrão: `current_user_id()` → carregar `app_users` → validar permissão → executar → retornar `JSONB`.

---

## Próximas frentes

### Crítica para produção
- **D1 · Supabase Auth real** · substituir `src/lib/supabase.ts` stub por SDK real + middleware Next.js + trigger de criação de `app_users` no signup

### Portabilidade Camada 1 → Camada 2 (sessões M1-M11)
Ver [`r2_people_INDEX.md`](r2_people_INDEX.md) §14 para o plano completo.

Ordem sugerida por dependência:
1. **M1** · Estrutura & Acessos (CRUD filiais/departamentos/cargos + perfis)
2. **M3** · Atestados ⭐ (alto valor LGPD, schema v4 pronto)
3. **M7** · 1:1s ⭐ (privacidade enforced, schema v6 pronto)
4. **M4** · Férias (módulo operacional)
5. **M6** · Folha & Custo (depende de M1)
6. **M2** · Movimentações, **M5** · Avaliações, **M8** · Metas, **M9** · Relatórios, **M10** · Configurações, **M11** · Histórico

### Backlog técnico
- F7 · Inline edit de tasks de onboarding
- G4 · Upload real de foto no ProfileChangeRequestModal
- G5 · Notificações por email/webhook
- H1 · Notificações in-app (bell icon)
- I1/I2/I3 · Exportação CSV/XLSX, filtros e busca, paginação

---

## Documentação por sessão (Camada 2)

| Sessão | Conteúdo |
|---|---|
| [sessao_h](docs/sessao_h.md) | Schema base |
| [sessao_h2](docs/sessao_h2.md) | Recognition |
| [sessao_j](docs/sessao_j.md) | PDI |
| [sessao_k](docs/sessao_k.md) | Onboarding |
| [sessao_l](docs/sessao_l.md) | Modules |
| [sessao_a1](docs/sessao_a1.md) | Module checks (gate em 31 RPCs) |
| [sessao_a2](docs/sessao_a2.md) | 9-Box |
| [sessao_b2](docs/sessao_b2.md) | Admin de módulos |
| [sessao_b3](docs/sessao_b3.md) | Navbar dinâmica |
| [sessao_c4](docs/sessao_c4.md) | Adapter TypeScript |
| [sessao_e1](docs/sessao_e1.md) | Ficha de empregado |
| [sessao_e2](docs/sessao_e2.md) | /pessoas/novo |
| [sessao_e4](docs/sessao_e4.md) | OCR server-side |
| [sessao_e5](docs/sessao_e5.md) | Storage de PDFs |
| [sessao_e6](docs/sessao_e6.md) | Preview do PDF |
| [sessao_f1](docs/sessao_f1.md) | Gestão por pessoa + Minha equipe |
| [sessao_f2](docs/sessao_f2.md) | Ações do gestor |
| [sessao_f3](docs/sessao_f3.md) | Dashboard agregado da equipe |
| [sessao_f4](docs/sessao_f4.md) | Dashboard tenant-wide |
| [sessao_f5](docs/sessao_f5.md) | Edição inline de PDIs |
| [sessao_f6](docs/sessao_f6.md) | Drilldown |
| [sessao_g1](docs/sessao_g1.md) | Minha Jornada |
| [sessao_g2](docs/sessao_g2.md) | Feed de reconhecimentos enviados |
| [sessao_g3](docs/sessao_g3.md) | Solicitações de alteração de dados |

Para reonboarding em nova sessão Claude, ler [`MIGRATION_PROMPT.md`](MIGRATION_PROMPT.md).

---

## Licença

Privado · R2 Soluções Empresariais.


