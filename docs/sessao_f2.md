# Sessão F2 · Ações do gestor a partir da ficha

Adiciona o botão `+ Ação` no header de `/pessoas/[id]` com dropdown de 3 ações: Criar PDI, Reconhecer e Iniciar avaliação 9-Box ad-hoc. Cada ação abre um modal full-screen e, ao concluir, dispara refresh do `GestaoSections` para o resultado aparecer na hora.

## Decisões fechadas

| Decisão | Escolha | Razão |
|---|---|---|
| Ações | PDI + Reconhecer + 9-Box ad-hoc | Cobre os 3 módulos de gestão prontos no backend |
| Trigger | Dropdown `+ Ação` no header | Menos poluição visual que 3 botões fixos |
| UI | Modal full-screen com formulário completo | Mais espaço para campos longos (objetivo, mensagem); mobile-friendly |
| PDI sem ciclo | Bloqueia com link para admin | Mantém disciplina de governança; admin cria ciclos |

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| Dropdown menu | `src/components/employees/actions/ActionsDropdown.tsx` | 153 |
| Modal Criar PDI | `src/components/employees/actions/CreatePdiModal.tsx` | 317 |
| Modal Reconhecer | `src/components/employees/actions/RecognizeModal.tsx` | 175 |
| Modal 9-Box ad-hoc | `src/components/employees/actions/StartAdhocEvaluationModal.tsx` | 129 |
| Integração na ficha | `src/app/pessoas/[id]/page.tsx` | +25 |
| Callback no GestaoSections | `src/components/employees/GestaoSections.tsx` | +15 |

### Correções de adapter (descobertas ao integrar)

Ao verificar contra as RPCs reais no banco, três incompatibilidades foram corrigidas:

| Arquivo | Antes (adapter) | Depois (RPC real) |
|---|---|---|
| `pdi.ts · create` | `p_subject_id, p_title, p_description` retorna `plan_id` | `p_user_id, p_cycle_id, p_objective, p_context, p_start_date, p_end_date` retorna `pdi_id` |
| `pdi.ts · listCycles` | `{cycles: [{id, name, status}]}` | `{items: [{id, code, display_name, start_date, end_date, open_for_planning}]}` |
| `recognition.ts · create` | `p_category, p_message` | `p_recipient_id, p_message, p_is_private` |

Essas correções são importantes além da F2 — qualquer chamada futura passa a funcionar contra o banco real.

## Fluxo das ações

### 1. Criar PDI
- Modal carrega ciclos ativos com `open_for_planning=TRUE` via `Pdi.listCycles`
- Se zero ciclos: banner amarelo com link `/admin/pdi/ciclos`
- Se 1 ciclo: auto-seleciona
- Campos: ciclo, objetivo (>=5 chars), contexto opcional, datas opcionais
- Submit chama `Pdi.create({userId, cycleId, objective, context?, startDate?, endDate?})`
- Erros amigáveis: `cycle_not_open`, `permission_denied`, `end_before_start`, etc

### 2. Reconhecer
- Campos: mensagem (>=10 chars, max 1000), toggle público/privado com cards visuais
- Submit chama `Recognition.create({recipientId, message, isPrivate})`
- Contador de caracteres em tempo real
- Privado: avisa que só RH/diretoria/sender/recipient veem

### 3. Iniciar 9-Box ad-hoc
- Card explicativo sobre o que é ad-hoc
- Botão confirma e chama `Ninebox.startEvaluation({subjectId, isAdhoc: true})`
- Redireciona para `/ninebox/avaliacoes/[evaluation_id]` onde o gestor preenche os scores

### Refresh automático

A página da ficha mantém `actionsRefreshKey` que incrementa após cada ação. O `GestaoSections` recebe esse valor como prop e refaz o fetch quando muda, então o PDI/reconhecimento recém-criado aparece na lista sem precisar dar F5.

## Permissões

O botão `+ Ação` só aparece se a ficha tem `app_user` vinculado (callback `onAppUserResolved` do `GestaoSections`). Backend valida cada ação:
- **PDI** · self com `manage_self_pdi`, ou manager direto, ou `manage_all_pdi` (RH)
- **Reconhecer** · qualquer usuário (sem self-recognition)
- **9-Box ad-hoc** · manager direto ou `manage_all_ninebox` (RH)

Erros do backend são mapeados para mensagens em português dentro de cada modal.

## Validação

```bash
tsc --noEmit --strict
# exit 0 · zero erros
```

Backend regredido (90 testes existentes continuam passando, nenhum teste novo necessário pois apenas chamamos RPCs já testadas).

## Fluxo prático

1. Gestor abre `/pessoas/<uuid>` de "JOÃO DA SILVA"
2. Vê o header da ficha com botão `+ Ação` ao lado do badge "Ativo"
3. Clica → dropdown com 3 opções aparece
4. Escolhe "Reconhecer"
5. Modal full-screen abre, preenche "Excelente condução da reunião com cliente X..."
6. Escolhe "Público"
7. Clica em "Reconhecer" → modal fecha
8. Seção "Reconhecimentos recebidos" da F1 atualiza automaticamente mostrando o novo
9. Volta no dropdown, escolhe "Iniciar 9-Box ad-hoc"
10. Confirma → é levado para `/ninebox/avaliacoes/<uuid>` da nova avaliação para preencher os scores

## Próximas frentes sugeridas

- **F4** · Dashboard tenant-wide para RH/diretoria (não só "minha equipe")
- **G1** · Tela do colaborador ("minha jornada" pessoal)
- **D1** · Supabase Auth real (libera deploy)
- **F5** · Inline edit das seções F1 (editar PDI sem sair da ficha)
