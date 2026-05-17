# Sessão F5 · Edição inline de PDIs

Adiciona modo de edição inline no card de PDI dentro de `/pessoas/[id]`: editar objetivo e datas, mudar status, e gerenciar ações (adicionar, marcar concluída, remover) sem sair da ficha. Padrão expansível dentro do próprio card.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Entidades | Só PDIs | Mais usado dia a dia; onboarding/9-Box ficam para sessões dedicadas |
| Padrão UI | Inline expansível (sem modal) | Reduz fricção; gestor edita rapidamente sem perder contexto da ficha |
| Escopo PDI | Ações gerenciadas inline (add/marcar/remover) | Cobertura completa da operação cotidiana |
| Permissão | Mesma regra F1 (gestor direto + RH + diretoria) | Backend já valida via RPC; frontend mostra erro `permission_denied` se aparecer |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| Card editável | `src/components/employees/PdiCardEditable.tsx` | 579 |
| Integração | `src/components/employees/GestaoSections.tsx` | +15 |
| Adapter realinhado | `src/lib/r2/pdi.ts` | 201 (reescrita) |

### Correções de adapter (descobertas integrando)

O módulo `Pdi` do C4 estava **completamente desalinhado** com as RPCs reais (todas estas funções nunca tinham sido chamadas até a F5). Foi feita uma reescrita do adapter:

| Função | Estava | Está agora |
|---|---|---|
| `Pdi.getById` | `p_plan_id` | `p_pdi_id` |
| `Pdi.update` | objeto `p_payload` | params individuais `p_objective`, `p_context`, `p_start_date`, `p_end_date` |
| `Pdi.changeStatus` | `p_plan_id`, sem motivo | `p_pdi_id`, `p_new_status`, `p_cancel_reason` |
| `Pdi.addAction` | `p_plan_id`, só descrição | `p_pdi_id`, `p_title` (obrigatório), `p_description`, `p_kind` (enum), `p_due_date` |
| `Pdi.updateAction` | objeto `p_payload` | params individuais (title, description, kind, due_date, status, evidence_url, evidence_note) |

Tipos refeitos:
- `PdiPlan` agora tem `user_id`, `objective`, `context`, `manager_id_snapshot`, `cycle_name`, `actions_total`, `actions_completed` (eram `subject_id`, `title`, `description`)
- `PdiAction` agora tem `pdi_id`, `title`, `kind`, `display_order`, `evidence_*`, `tenant_id`, `updated_at` (eram `plan_id`, só `description`, sem kind)
- Enums novos: `PdiActionKind` (curso/leitura/mentoria/projeto/certificacao/evento/outro) e `PdiActionStatus` (not_started/in_progress/completed/canceled)

### Componente `PdiCardEditable`

**Modo view (default):**
- Mostra objetivo, badge de status, ciclo, datas, gestor
- Barra de progresso de ações se houver alguma
- Botão lápis para entrar em modo edição
- Botão chevron para expandir e ver/gerenciar ações

**Modo edit:**
- Input para objetivo (mín. 5 caracteres)
- Datas de início/fim
- Botões Cancelar / Salvar (só envia campos que mudaram)

**Mudança de status:**
- Chips clicáveis para cada status diferente do atual
- Confirmação obrigatória de motivo se for cancelamento (via `window.prompt`)

**Gestão de ações (expandido):**
- Lazy load: só carrega ações quando expandido pela primeira vez
- Cada ação: checkbox circular (toggle completed ↔ in_progress), título com strike-through quando concluída, tipo, due_date, botão de remover (aparece no hover)
- Formulário "+ Adicionar ação" inline: título (mín. 3), tipo (select com 7 opções), due_date opcional

**Tratamento de erro:**
- Erros do backend mapeados para mensagens em PT-BR (`permission_denied`, `invalid_transition`, `cancel_reason_required`, etc)
- Mostrados inline com banner vermelho dentro do card expandido

### Integração no `GestaoSections`

- `PdisList` aceita prop `onChanged` que é chamada após cada edição/ação
- `GestaoSections` mantém `localRefresh` interno que incrementa nesse callback
- `useEffect` reage a `[employeeId, refreshKey, localRefresh]` → refaz fetch e atualiza progress bar/contadores
- `refreshKey` externa (de F2) continua funcionando independente

## Permissões

Backend já valida via `manage_self_pdi` / `user_is_manager_of` / `manage_all_pdi`. Frontend só roteia o erro:
- `permission_denied` → mensagem inline e ação não acontece
- `invalid_transition` → ex.: tentar voltar de `completed` para `draft` (backend bloqueia)
- `cancel_reason_required` → frontend prompt obriga texto

## Validação

```bash
tsc --noEmit --strict
# exit 0 · zero erros
```

Backend não foi alterado — todas as RPCs PDI eram pré-existentes da fase H. A F5 expõe pela primeira vez no produto.

## Fluxo prático

1. Gestor abre ficha de "JOÃO DA SILVA"
2. Na seção "PDIs", vê 2 cards. O primeiro tem objetivo "Aprimorar comunicação", status Ativo, 3/5 ações
3. Clica no chevron → expande, ações carregam, vê: "Curso de oratória" (concluída), "Apresentar reunião mensal" (em andamento), "Mentoria semanal" (em andamento), "Ler 2 livros" (concluída), "Reunião 1:1 quinzenal" (em andamento)
4. Clica no círculo da "Mentoria semanal" → vira concluída, barra de progresso vira 4/5 imediatamente
5. Clica em "+ Adicionar ação" → preenche "Curso de PNL", tipo "Curso", due 30/06 → adiciona → vira 4/6
6. Clica no lápis → modo edit → altera fim de 30/06 para 30/09 → salva
7. Decide cancelar o segundo PDI → clica em "Cancelado" → prompt pede motivo → digita "Mudança de área" → salva

## Próximas frentes sugeridas

- **G1** · Tela do colaborador ("minha jornada" pessoal: ver/editar próprios PDIs, reconhecimentos recebidos, onboarding em curso) · pode reusar o `PdiCardEditable` com mesmas permissões
- **D1** · Supabase Auth real (libera deploy)
- **F6** · Drilldown a partir do dashboard (clicar em caixa 9-Box → lista de pessoas)
- **F7** · Inline edit das demais seções da F1 (Onboarding tasks; Recognitions já estão imutáveis por design)
