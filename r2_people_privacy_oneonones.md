# Política de Privacidade · 1:1s Estruturadas

**Versão:** 1.0 · 17 de maio de 2026
**Controlador:** Cliente que opera o R2 People (ex: Grupo Pinto Cerqueira)
**Operador:** R2 Soluções Empresariais Ltda
**Complementa:** [r2_people_privacy_policy.md](r2_people_privacy_policy.md)
**Base legal:** LGPD Lei 13.709/2018 · CLT · Resoluções CNDP/ANPD

---

## 1. Por que esta política existe

As 1:1s estruturadas processam um tipo particular de dado que merece tratamento dedicado: **conversas entre líder e liderado, com expectativa de privacidade**. Diferente de avaliações formais (que têm peso institucional explícito) ou de feedback público (que é, por definição, compartilhado), a 1:1 é o espaço onde:

- O líder anota observações pessoais sobre comportamento, sinais de motivação ou desmotivação, percepções de evolução
- O liderado expressa dificuldades, dúvidas sobre carreira, preocupações que não levaria a uma reunião pública
- Ambos negociam compromissos (action items) que misturam profissional e pessoal

Tratar esses dados como "mais um campo no banco" seria uma falha. Esta política descreve o **modelo de 3 camadas de privacidade** que protege esses dados na arquitetura.

---

## 2. O modelo de 3 camadas

```
┌─────────────────────────────────────────────────────────────────┐
│  CAMADA 1 · PRIVADO DO LÍDER                                    │
│  ─────────────────────────────                                  │
│  Notas privadas do líder, sentimento (mood) do líder            │
│  Quem vê:  apenas o leader_id da meeting                        │
│  Garantia: RLS · ninguém mais consegue SELECT (nem DPO regular) │
│  Exceção:  DSAR formal LGPD Art. 18 via RPC dedicada            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  CAMADA 2 · COMPARTILHADO ENTRE OS DOIS                         │
│  ─────────────────────────────                                  │
│  Notas compartilhadas, pauta, action items                      │
│  Quem vê:  apenas leader_id E led_id da meeting                 │
│  Garantia: RLS · RH consultando SQL direto retorna 0 rows       │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  CAMADA 3 · METADADOS AGREGADOS                                 │
│  ─────────────────────────────                                  │
│  Cadência, datas, contagens, health scores, status              │
│  Quem vê:  RH com permission view_oneonones_metadata            │
│  Garantia: Views agregadas · nunca expõem texto bruto           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Camada 1 · Privado do Líder

### O que está aqui

- **Notas privadas do líder** (campo `oneonone_notes.content` com `kind = 'private_leader'`)
- **Sentimento do líder ao concluir** (`oneonone_meetings.mood_leader` ∈ {great, good, neutral, difficult})

### Quem acessa

| Persona | Acesso |
|---|---|
| Líder dono | ✅ Total (R/W até `content_locked_at`, R apenas depois) |
| Liderado | ❌ Bloqueado |
| RH (qualquer perfil) | ❌ Bloqueado |
| Diretoria | ❌ Bloqueado |
| DPO | ❌ Bloqueado em operação normal |
| Super_admin (R2 staff) | ❌ Bloqueado em operação normal |

### Como a garantia funciona

A política RLS é literal:

```sql
CREATE POLICY notes_private_leader_only ON oneonone_notes FOR SELECT
  USING (
    kind = 'private_leader'
    AND EXISTS (
      SELECT 1 FROM oneonone_meetings m
      WHERE m.id = meeting_id AND m.leader_id = current_user_id()
    )
  );
```

Se uma analista do RH abrir o `psql` direto contra o banco e rodar `SELECT * FROM oneonone_notes WHERE kind = 'private_leader'`, o resultado é vazio. Não há policy permitindo essa leitura.

### Exceção controlada · DSAR LGPD Art. 18

O titular dos dados (geralmente o liderado, em alguns casos o próprio líder) pode exercer direito de acesso. Para isso existe **uma única RPC dedicada**:

```sql
rpc_oneonone_dsar_export(p_target_user_id UUID)
  -- exige permission dsar_export (concedida apenas a DPO formal)
  -- gera audit log pesado: quem solicitou, quando, qual target
  -- retorna todas as notas (privadas e compartilhadas) onde target_user_id participa
  -- NÃO joina com pairs de terceiros (não vaza dados de outros liderados)
```

A garantia não é "RH não vê porque a tela esconde", é "RH não vê porque o banco não devolve".

---

## 4. Camada 2 · Compartilhado entre os 2

### O que está aqui

- **Notas compartilhadas** (`oneonone_notes` com `kind = 'shared'`)
- **Itens de pauta** (`oneonone_agenda_items.text`)
- **Action items** (`oneonone_action_items.description`)

### Quem acessa

| Persona | Acesso |
|---|---|
| Líder da meeting | ✅ R/W (até `content_locked_at`) |
| Liderado da meeting | ✅ R/W (até `content_locked_at`) |
| Outro líder | ❌ Bloqueado |
| Outro liderado | ❌ Bloqueado |
| RH (qualquer perfil) | ❌ Bloqueado em texto · vê só metadados |

### Carry over automático

Itens não discutidos (`status = 'pending'`) viram pauta da próxima 1:1 do par via `rpc_oneonone_complete_meeting`. Tag visual "vindo da anterior".

**Anti-cascata:** não copia item que já é carry over (`carried_from_meeting_id IS NOT NULL`). Evita propagação infinita se nada for tratado por meses.

### Lock após 7 dias

Sete dias após `completed_at`, job pg_cron preenche `content_locked_at`. A partir daí, UPDATE em notas/pauta/AIs retorna erro `content_locked`. Permite revisão pós-1:1 mas previne edição revisionista tardia.

---

## 5. Camada 3 · Metadados agregados (RH)

### O que está aqui

RH precisa acompanhar saúde do programa de 1:1s sem invadir privacidade. Três views agregadas servem essa necessidade:

#### View 1 · `oneonones_rh_dashboard_leader`

Para cada par ativo (leader, led), retorna:
- Nome do líder, nome do liderado
- Cadência configurada
- # meetings completadas nos últimos 90d
- Data da última meeting completada
- # action items abertos (não a descrição)
- Health score: `fresh` (<14d), `aging` (14-35d), `stale` (>35d)

#### View 2 · `oneonones_rh_overdue_led`

Liderados sem 1:1 há > 30 dias. Útil pra alertas.

#### View 3 · `oneonones_rh_activity`

Eventos recentes (criação, conclusão, cancelamento, reagendamento). Sem conteúdo.

### O que RH NÃO vê

| Dado | RH vê? | Onde está bloqueado |
|---|---|---|
| Texto de nota privada | ❌ | RLS |
| Texto de nota compartilhada | ❌ | RLS |
| Texto de item de pauta | ❌ | RLS |
| Descrição de action item | ❌ | RLS |
| Sentimento (mood) do líder | ❌ | RLS + nenhuma view expõe |
| Sentimento (mood) do liderado | ❌ | RLS + nenhuma view expõe |
| # de meetings | ✅ | View agregada |
| Data da última | ✅ | View agregada |
| Cadência configurada | ✅ | View agregada |
| Nome dos participantes | ✅ | View agregada (necessário pra cobrança) |

### Templates de mensagem RH→Líder

RH pode cobrar líderes mas não pode editar nem ler conteúdo das 1:1s. Para isso há `rpc_oneonone_send_rh_message` com 4 templates:

1. **Cadence** · "Notamos que sua cadência de 1:1s está abaixo do combinado"
2. **Overdue Led** · "X está há Yd sem 1:1 com você"
3. **Overdue AI** · "Você tem N action items em atraso"
4. **Custom** · texto livre

Cada envio gera audit log obrigatório. RH não pode mascarar a identidade.

---

## 6. Sentimento (mood) · decisão dura

O campo `mood_leader` e `mood_led` é o item mais sensível da arquitetura.

### A decisão

> **Mood é privado de quem registrou. Líder não vê do liderado, liderado não vê do líder, RH não vê de ninguém.**

### Por quê

Sentimento numérico tende a ser instrumentalizado:

- Se aparece em dashboard, vira métrica de cobrança ("seu time tem mood 2.3, melhore")
- Se vira métrica de cobrança, líderes pressionam por "respostas boas"
- Se há pressão por respostas boas, o sinal desaparece (todos marcam "good")
- Quando o sinal desaparece, a feature perde valor (e custa a confiança)

A decisão de **não expor mood em lugar nenhum** é uma escolha de produto deliberada, não uma omissão.

### O que se faz com o sentimento então?

- O **líder** vê seu próprio histórico de mood ao concluir 1:1s · útil pra auto-observação ("notei que tenho marcado difficult depois das 1:1s com X")
- O **liderado** vê seu próprio histórico · idem
- **Ninguém mais** vê

---

## 7. Pares prestadora ↔ tomadora (caso GPC)

A estrutura tripartite do GPC tem casos particulares:

- **Larissa Pereira** (RH Labuta · prestadora) precisa acompanhar saúde de 1:1s **dos colaboradores Labuta**, não dos GPC
- A solução é o `permission_profile` com `scope_employer_unit_id = labuta`
- Larissa abre `/admin/1on1s` e vê apenas pairs onde `led.employer_unit_id = labuta`
- Banner roxo de escopo restrito reforça visualmente

A regra é a mesma: só metadados, nunca conteúdo.

---

## 8. Auditoria e accountability

### O que é auditado

- **Criação de meeting** (quem agendou, quando)
- **Conclusão de meeting** (quem concluiu, mood é audit'd como "registrado" mas valor não vaza)
- **Acesso a nota privada** via DSAR (quem solicitou, qual target, motivo registrado)
- **Envio de mensagem RH→Líder** (quem enviou, qual template, para quem)
- **Edição de pauta/AI/notas** depois do lock (que deveria falhar mas registra tentativas)

### O que NÃO é auditado

- Leituras normais de notas pelos participantes legítimos (seria invasivo logar cada vez que o líder abre uma 1:1)
- Conteúdo das notas em audit_log (só metadados: meeting_id, kind, ação)

---

## 9. Direitos do titular (LGPD Art. 18)

| Direito | Como exercer |
|---|---|
| Confirmação de tratamento | Solicitar ao DPO do controlador |
| Acesso aos dados | `rpc_oneonone_dsar_export` invocada pelo DPO autorizado |
| Correção | Solicitar edição via DPO se nota contém erro factual |
| Anonimização/eliminação | Não aplicável: notas são por natureza pessoais e a privacidade já é garantida arquiteturalmente. Exclusão de notas privadas seria perda de memória do líder · discutido caso a caso |
| Portabilidade | Export JSON via DSAR |
| Informação sobre compartilhamento | Não há compartilhamento com terceiros |
| Revogação de consentimento | Não aplicável: tratamento se baseia em legítimo interesse (CLT Art. 482 e gestão de pessoas) |

---

## 10. Transferência internacional

Dados das 1:1s ficam no Supabase (Postgres) hospedado em região South America (São Paulo). Sem transferência internacional rotineira. Backup criptografado pode ser mantido em região US (AWS S3) com cláusulas padrão de proteção.

---

## 11. Retenção

| Item | Prazo de retenção | Justificativa |
|---|---|---|
| Meetings (todos os campos) | Vida útil do colaborador no tenant + 2 anos pós-desligamento | Histórico de evolução · defesa em ações trabalhistas |
| Notas privadas | Mesmo | Memória do líder |
| Notas compartilhadas | Mesmo | Histórico do par |
| Action items | Mesmo | Compromissos firmados |
| Mensagens RH→Líder | 2 anos | Audit |

Após o prazo, dados são anonimizados (remove `leader_id`, `led_id`, mantém estatísticas agregadas).

---

## 12. Princípios de design por trás desta política

1. **Privacidade é arquitetural, não cosmética** · a garantia está no schema, não na tela
2. **Mínimo necessário** · RH vê o mínimo para fazer seu trabalho (acompanhar saúde do programa)
3. **Sem instrumentalização do sentimento** · mood não vira métrica de cobrança em hipótese nenhuma
4. **Audit pesado em exceções** · DSAR não é silencioso, deixa rastro explícito
5. **Confiança como capital** · uma única quebra de privacidade destruiria o valor da feature inteira

---

## 13. Contato

- **DPO do controlador**: definido por cada cliente (ex: para GPC, é Carla Moreira)
- **DPO operador (R2 Soluções)**: dpo@solucoesr2.com.br
- **Solicitações LGPD**: via canal interno do cliente, encaminhadas para DPO

---

## 14. Histórico de versões

| Versão | Data | Mudanças |
|---|---|---|
| 1.0 | 17 mai 2026 | Versão inicial · descreve modelo de 3 camadas implementado em schema_oneonones_v6 |

---

*Esta política complementa a [política geral de privacidade do R2 People](r2_people_privacy_policy.md). Em caso de conflito, prevalece a interpretação mais restritiva (privacy by default).*
