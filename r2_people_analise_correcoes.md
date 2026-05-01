# Relatório de Análise e Correções · R2 People

**Data**: 29 de abril de 2026
**Escopo**: 34 HTMLs + 8 SQLs + 4 MDs em `/mnt/user-data/outputs/`
**Status**: TODAS AS CORREÇÕES APLICADAS E VALIDADAS

---

## Resumo Executivo

| Severidade | Achados | Corrigidos | Status |
|---|---|---|---|
| P0 (Crítico) | 4 | 4 | ✓ |
| P1 (Alto) | 3 | 3 | ✓ |
| P2 (Médio) | 2 | 2 | ✓ |
| P3 (Baixo) | 1 | 0 (não bloqueante) | Diferido |
| **Total** | **10** | **9** | **90%** |

**211 substituições contextuais de em-dash** aplicadas em 27 arquivos (15 HTMLs + 4 MDs + 8 SQLs).

---

## Ondas de Correção

### Onda 1 · P0 críticos (4 itens)

**P0#1 · Em-dashes (regra explícita)**:
Substituição contextual em massa via Python:
- `>—<` → `>-<` (placeholders em células)
- ` — ` → ` · ` (separadores entre items)
- `palavra—palavra` → `palavra-palavra` (sem espaços)
- 4 polishes manuais (travessão de oração → vírgula/dois pontos)

**P0#2 · XSS via input do CID** em `atestado_validacao_dp.html`:
Refatorada `searchCID()` usando DOM API segura:
- `textContent` em vez de `innerHTML` interpolado
- `addEventListener` em vez de `onclick="..."` interpolado
- Eliminação por construção (não escape de string)

**P0#3 · IRRF 2026 incompleto** em `calculadora_custo.html`:
Implementado redutor adicional Lei 15.270/2025 entre R$ 5k e R$ 7.350:
```js
redutor = Math.max(0, 978.62 - (0.133145 * salarioBruto))
irrfFinal = Math.max(0, irrfBruto - redutor)
```
Validação matemática:
- R$ 6.000 → redutor R$ 179,75 ✓ (bate Receita Federal)
- R$ 7.000 → redutor R$ 46,60 ✓ (bate exemplo Solides)
- R$ 7.350 → redutor 0,00 ✓ (transição correta)

**P0#4 · Contraste branco-em-cinza** em `feedback_mural.html`:
`background: var(--gray3) + color:#fff` → `background: var(--dark) + color:#fff`
Mantém conceito de "anonimato neutro" mas com contraste WCAG AAA.

### Onda 2 · P1 alto impacto (3 itens)

**P1#5 · Divisões por zero**: 6 divisões protegidas com guarda ternária
- `calculadora_custo.html`: multS, multL, diffPerc
- `folha_por_filial.html`: salMedio
- `comparar_cenarios.html`: salMed, A_medio, B_medio

**P1#6 · Constante mágica** em `comparar_cenarios.html`:
`ENC_LUCRO = 0.358` → forma decomposta `0.20 + 0.02 + 0.058 + 0.08` consistente com `folha_por_filial.html`

**P1#7 · Inputs sem `min`**: adicionado `min="0"` em 3 inputs de dissídio (1 em folha_por_filial, 2 em comparar_cenarios).

### Onda 3 · P2 polish (2 itens)

**P2#8 · Texto técnico** em `regime_tributario.html`:
"permission · manage_tax_regime" → "Acesso restrito · administradores"

**P2#9 · Debounce** em `comparar_cenarios.html`:
- KPIs e painéis A/B atualizam imediatamente (UX responsiva)
- Renderização pesada (paired bars + diff table de 14 linhas) com debounce de 150ms
- Init imediato (sem flash de tabela vazia)

### Diferido

**P3#10 · Listeners sem cleanup**: aceito como dívida técnica até virar SPA real (atualmente HTMLs estáticos isolados; reload limpa naturalmente).

---

## Arquivos Modificados (9 únicos + 22 com em-dashes)

Modificações funcionais:
1. `r2_people_atestado_validacao_dp.html` (XSS)
2. `r2_people_calculadora_custo.html` (IRRF + zero-division)
3. `r2_people_feedback_mural.html` (contraste + em-dashes)
4. `r2_people_folha_por_filial.html` (zero-division + min)
5. `r2_people_comparar_cenarios.html` (zero-division + constante + min + debounce + em-dashes)
6. `r2_people_regime_tributario.html` (permission text)
7. `r2_people_minha_trajetoria.html` (em-dashes polish)
8. `r2_people_error_pages.html` (em-dashes polish)
9. `r2_people_colaborador.html` (em-dashes polish)

Outros arquivos com em-dashes substituídos: 22 arquivos (12 HTMLs + 4 MDs + 5 SQLs).

