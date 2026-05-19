# Sessão autônoma · bloco pós-reposicionamento (18 de maio de 2026)

**Versão**: 1.0
**Período**: continuação da sessão após mensagem "pode ir no seu ritmo"
**Commits**: 5 (`3e61f4b` → `718a332`)
**Linhas entregues**: ~5.500

---

## 1. Contexto

Após o reposicionamento estratégico ("R2 = gestão de pessoas, NÃO DP · Domínio é fonte fiscal"), os specs M16 (Domínio) e M17 (People Analytics) foram criados. O usuário disse "pode ir no seu ritmo" — interpretação autônoma: avançar com as próximas categorias da discussão original (M18 Compliance, M19 Benefícios, M20 Inbox Líder), materializar em schema SQL e criar as UIs correspondentes.

---

## 2. Entregas

### 2.1 Specs novos

| Spec | Linhas | Escopo |
|---|---|---|
| **M18 Compliance & Treinamentos** | 480 | ASO NR-7 + EPI NR-6 + 13 treinamentos NR + termos versionados + docs pessoais c/ vencimento + LTCAT/PPP · 6 tabelas + score 0-100 + integração Domínio dispara wizards |
| **M19 Benefícios & Dependentes** | 600 | Catálogo c/ 13 tipos + adesão self-service + dependentes c/ alerta 21/24 anos + convênios parceiros + reembolso workflow líder→RH→Domínio · 12 tabelas + 7 RPCs |
| **M20 Inbox Unificado do Líder** | 340 | Uma tela: aprovações + calendar consolidado + painel equipe + atividade · auto-aprovação por regra + bulk approve · 4 RPCs |

### 2.2 Schemas SQL

| Schema | Linhas | Conteúdo |
|---|---|---|
| **v15 Domínio+Analytics+Compliance+Benefícios** | 540 | Materializa M16+M17+M18+M19 · 22 tabelas + 6 RPCs + RLS via loop em 17 tabelas + k-anonymity helper + score compliance + reembolso decide · 100% idempotente |

### 2.3 Páginas HTML novas

| Página | Persona | Conteúdo |
|---|---|---|
| **`r2_people_analytics.html`** | Renato Pinto · Diretor Operações | 4 exec cards + 5 abas (Headcount/Turnover/D&I k-anonymity/Custo Domínio/Engajamento cruzado) · filtros globais período/EMP/TOM/nível · curva sobrevivência Kaplan-Meier · 3 donuts D&I · histograma faixas salariais · 6 cards cruzamentos |
| **`r2_people_inbox_lider.html`** | João Carvalho · Líder Financeiro 11 subordinados | Layout 3-painéis (main + side equipe 340px) · 4 KPIs do dia · 3 abas (Inbox priorizado bloqueador→urgent→normal + Calendar mensal 5 tipos + Atividade feed) · 8 inbox items demo c/ aprovar/rejeitar inline · painel equipe 11 cards c/ avatar+status+score+pills |
| **`r2_people_compliance.html`** | Patrícia Mello · Coord RH | Score ring 78/100 + banner alerta vermelho ASO vencido + 5 KPIs + 6 abas (ASOs/EPIs/Treinamentos NR heatmap 6 filiais × 8 normas/Termos versionados/Documentos vencendo/LTCAT+Hazard) |
| **`r2_people_beneficios.html`** | Fernanda Lima · Analista Pleno | Hero pacote total navy→purple R$ 7.930 + 5 abas (Meus 6 ativos/Disponíveis 7 c/ Aderir/Dependentes 3 c/ alerta 21 anos/Reembolsos 5 c/ status/Convênios 6 cards c/ rating estrelas) |

### 2.4 Atualizações

- **Hub Admin** expandido para **9 cockpits** (adicionado Analytics gradient navy-orange · status banner 9 pills · Hero text)
- **SEARCH_INDEX** atualizado em `assets/r2-shell.js` com 4 novas entradas (Analytics, Inbox Líder, Compliance, Benefícios)
- **INDEX** bump v2.46 → v2.49 com 5 versões documentadas

---

## 3. Personas no sistema (9 totais com cockpit)

| Persona | Papel | Cockpit |
|---|---|---|
| Super Admin | super_admin | Hub Admin |
| Carla Moreira | DPO | LGPD Cockpit |
| Daniel Santos | CTO | Observability |
| Ricardo Silva | DevSec | Security |
| Patrícia Mello | Coord RH / tenant_admin | Notif Admin + Billing + **Compliance** |
| Eduardo Mendes | DevOps | DR Console |
| Marina Carvalho | CSM Sênior | CS Dashboard |
| Diego Ito | Dev Integrações | API Console |
| **Renato Pinto** | **Diretor Operações** | **People Analytics** ⭐ NOVO |
| **João Carvalho** | **Líder Financeiro** | **Inbox do Líder** ⭐ NOVO |
| **Fernanda Lima** | **Analista Pleno · colaborador** | **Meus Benefícios** ⭐ NOVO (perspectiva colaborador) |

11 perspectivas distintas: super_admin, gestão LGPD, operação, segurança, RH coord, DevOps, CS, dev externo, diretoria, liderança direta, colaborador final.

---

## 4. Estado dos artefatos

| Categoria | Total |
|---|---|
| **Specs M-series** | 13 (M5/M8/M9/M10/M11/M12/M13/M14/M15/M16/M17/**M18**/**M19**/**M20**) |
| **Specs D-series** | 9 (D2-D9) |
| **Specs C-series** | 3 (C1/C2/C3) |
| **Total specs** | **25 documentadas** |
| **Schemas SQL** | 6 (v9/v10/v11/v12/v13/v14/**v15**) |
| **Páginas admin novas (nesta sessão)** | 4 (Analytics + Inbox + Compliance + Benefícios) |
| **Cockpits operacionais** | 9 |
| **Commits bloco** | 5 |
| **INDEX versão** | v2.49 |

---

## 5. Cobertura conceitual

Com este bloco, a plataforma agora cobre:

| Camada | Status |
|---|---|
| **Produto técnico** | 60+ telas + 5 schemas SQL · multi-tenant + RLS + integração Domínio |
| **Operação interna R2** | 9 cockpits dedicados c/ personas distintas |
| **Liderança direta** | Inbox unificado (M20) → única tela pro líder |
| **Colaborador final** | Meus benefícios + Meu PDI + Minha trajetória |
| **Diretoria/CFO** | People Analytics (M17) com headcount/turnover/D&I/custo |
| **Compliance trabalhista** | NR-7/NR-6/treinamentos/termos/docs/LTCAT em cockpit dedicado |
| **DP fiscal** | Refletido do Domínio via M16 (especulativo · aguarda doc API) |
| **Comercial** | Landing + Pricing + 3 specs C-series |
| **LGPD** | DPO cockpit + spec D7 + k-anonymity em Analytics |
| **Observability/Security/DR** | 3 cockpits + 3 specs D-series |

---

## 6. Próximas opções

1. **Spec M21 · Específicos varejo GPC** (quadro multi-loja, absenteísmo por loja, treinamento por função, quadro de honra) — pedido recorrente do anchor client
2. **Spec D10 · Mobile-first** (PWA, push notifications, geolocation opcional, offline-first)
3. **Schema SQL v16** materializando M20 (leader_inbox_prefs)
4. **Página `r2_people_dependentes_wizard.html`** standalone (4 passos)
5. **Página `r2_people_aniversariantes.html`** consolidando aniversariantes natalícios + empresa em uma página dedicada (hoje só destaque na home)
6. **Spec C4 · Partner Program** (escritórios contábeis revendem · 20% MRR recorrente)
7. **Auditoria visual** completa (rodar pela home, abrir cada cockpit, verificar consistência)

---

## 7. Direções abertas para discussão com user

Algumas decisões ficaram em aberto e mereceriam validação:

1. **Doc oficial Domínio**: M16 ainda é especulativa. Quando conseguir a doc/API real, transformar em v2.0 com decisões concretas.
2. **Pricing dos benefícios**: M19 fala em "empresa subsidia X%" — em GPC real, quanto cada plano custa? Tabela precisa virar dado.
3. **CCT específica**: muitas regras (VR/VA, day off aniversário) dependem da convenção coletiva regional. GPC opera na Bahia · pesquisar CCT comércio varejista BA pra calibrar.
4. **Treinamentos por cargo**: matriz EPI × cargo precisa de revisão com SESMT externo do GPC.
5. **eNPS**: usamos benchmark genérico, mas dados reais GPC seriam mais úteis.
6. **Análise visual**: as 4 páginas novas seguem padrão Cofre desde criação, mas vale conferir.
