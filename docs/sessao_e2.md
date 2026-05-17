# Sessão E2 · /pessoas/novo (criação manual)

Formulário longo com 5 seções para criar uma ficha de empregado do zero, com validação onBlur, máscaras de entrada e detecção de CPF duplicado em tempo real.

## O que entrega

| Componente | Arquivo | Linhas |
|---|---|---|
| Helpers de validação | `src/lib/validation.ts` | 222 |
| Componentes de campo | `src/components/employees/FormFields.tsx` | 305 |
| Página /pessoas/novo | `src/app/pessoas/novo/page.tsx` | 565 |
| RPC check_cpf | `supabase/migrations/00302_e2_rpc_check_cpf.sql` | 56 |
| Testes | `supabase/tests/00302_e2_check_cpf.sql` | 154 |

Total: ~1300 linhas. Adapter `Employees.checkCpf` adicionado (+24 linhas).

## Comportamento

### Layout

- Página única longa, sidebar fixa à esquerda com índice de seções (links âncora)
- Footer sticky com botões "Cancelar" e "Salvar ficha"
- Sticky com indicador "Pronto para salvar" verde quando todos os obrigatórios estão preenchidos

### Seções

1. **Identificação** — nome, sexo, matrícula, nº ficha, nascimento, beneficiários
2. **Documentos** — CPF (com check de duplicidade), RG, órgão, PIS, CTPS (nº/série/UF/expedição), título eleitoral
3. **Dados pessoais** — filiação, cidade/UF de nascimento, nacionalidade, estado civil, raça, escolaridade, deficiência (com campo condicional de descrição)
4. **Contato** — celular, residencial, email, endereço, CEP
5. **Vínculo** — cargo, função, CBO, admissão, salário inicial + periodicidade, jornada de trabalho (4 horários), FGTS

### Validação

- **onBlur por campo**: erro inline aparece quando o usuário sai do campo
- **Required visual** (asterisco vermelho) nos campos obrigatórios
- **Banner no topo** com lista de pendências aparece quando o usuário tenta salvar com erros
- **Validações tipadas**:
  - CPF: dígitos verificadores (mod 11) · rejeita sequências repetidas
  - CEP: 8 dígitos
  - Telefone: 10 ou 11 dígitos · celular precisa começar com 9 após DDD
  - Data: dia/mês válidos · ano entre 1900 e ano atual + 1 · respeita bissextos · `notFuture` opcional
  - Hora: HH:MM (00-23 / 00-59)
  - Email: regex padrão
  - UF: válida na lista das 27 UFs brasileiras

### Máscaras

- **CPF**: `000.000.000-00`
- **CEP**: `00000-000`
- **Telefone**: `(00) 00000-0000` ou `(00) 0000-0000` (auto-detecta pelo tamanho)
- **Data**: `DD/MM/AAAA`
- **Hora**: `HH:MM`

### CPF duplicado

Quando o usuário termina de digitar um CPF válido:

1. Frontend chama `Employees.checkCpf(cpf)` (debounce 500ms)
2. Indicador "Verificando..." aparece logo abaixo do campo
3. Se duplicado: bloco amarelo com nome da pessoa existente, matrícula, status (ativo/desligado) e **link clicável para a ficha existente**
4. Não bloqueia o submit · se o usuário insistir, o backend retorna `already_exists` e a UI redireciona para a ficha existente (idempotência por CPF do create)

### Submit

- Botão "Salvar ficha" desabilitado se há erros não resolvidos
- Loading spinner enquanto salva
- Após sucesso: redireciona para `/pessoas/[id]` da nova ficha
- Em erro do backend: mostra código do erro em banner vermelho

## Validação automática

```bash
tsc --noEmit --strict
# exit 0 · zero erros

psql -f supabase/tests/00300_e1_employees.sql
# 30/30 PASS

psql -f supabase/tests/00302_e2_check_cpf.sql
# 6/6 PASS
```

Total backend: **36 testes passam**.

## Decisões fechadas

- **Obrigatórios**: full_name, hire_date, job_title, cpf, rg, birth_date, sex + ao menos um telefone
- **CPF duplicado** mostra aviso com link, não bloqueia · backend tem idempotência
- **Validação onBlur** (não em tempo real durante digitação) · evita flicker de erros
- **DD/MM/AAAA na UI** · conversão para AAAA-MM-DD no submit
- **Telefones armazenados sem máscara** (só dígitos)

## Próximos passos

- **E3** · Validação assíncrona de CEP via ViaCEP (autopreenche endereço)
- **E4** · OCR no servidor via edge function
- **E5** · `/pessoas/[id]/editar` (formulário cheio em vez do dialog por seção)
- **E6** · Bulk actions na lista (selecionar múltiplos para arquivar, exportar, etc)
