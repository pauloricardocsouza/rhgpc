# Termos de Uso · R2 People

**Versão:** 1.0 · 17 de maio de 2026
**Operador:** R2 Soluções Empresariais Ltda · CNPJ XX.XXX.XXX/0001-XX · Bahia, Brasil
**Aplicável a:** todos os usuários da plataforma R2 People
**Complementa:** [Política de Privacidade](r2_people_privacy_policy.md) e [Política específica de 1:1s](r2_people_privacy_oneonones.md)

---

## 1. Aceite

Ao acessar e usar o **R2 People** ("Plataforma"), você ("Usuário") declara que leu, entendeu e aceita estes Termos de Uso ("Termos") na íntegra. Se você não concorda com qualquer parte destes Termos, **não deve usar a Plataforma**.

O acesso à Plataforma é mediado pelo seu empregador ou contratante ("Cliente"), que é o **controlador dos dados** processados na sua conta. A R2 Soluções Empresariais atua exclusivamente como **operador**, nos termos da Lei 13.709/2018 (LGPD).

---

## 2. Definições

| Termo | Significado |
|---|---|
| **Plataforma** | R2 People · SaaS de gestão de pessoas operado pela R2 Soluções Empresariais |
| **Cliente** | Empresa ou organização que contrata a Plataforma e disponibiliza acesso a usuários |
| **Usuário** | Pessoa física que acessa a Plataforma (colaborador, líder, RH, diretoria, DPO) |
| **Tenant** | Instância lógica isolada da Plataforma para um Cliente específico |
| **Controlador** | O Cliente, responsável por definir finalidades e meios do tratamento de dados |
| **Operador** | A R2 Soluções Empresariais, responsável pela operação técnica conforme instrução do Controlador |
| **Dados Pessoais** | Toda informação relacionada a pessoa natural identificada ou identificável |
| **Dados Sensíveis** | Dados sobre saúde, biometria, vida sexual, etc. (LGPD Art. 5º, II) |

---

## 3. Objeto

A Plataforma oferece funcionalidades de gestão de pessoas, incluindo (mas não limitado a):

- Cadastro e ficha de colaboradores
- Avaliações de desempenho e potencial (9-Box)
- Plano de Desenvolvimento Individual (PDI)
- Reconhecimentos e feedback
- Onboarding de novos colaboradores
- Gestão de atestados médicos
- Gestão e programação de férias
- 1:1s estruturadas entre líder e liderado
- Movimentações de RH (promoções, transferências, etc.)
- Cálculos de custo e folha
- Dashboards e relatórios

A lista completa de funcionalidades disponíveis depende do plano contratado pelo Cliente e dos módulos por ele ativados.

---

## 4. Conta e acesso

### 4.1 Criação de conta

A conta do Usuário é criada pelo administrador do Cliente (geralmente RH ou TI). A R2 não cria contas diretamente para usuários finais.

### 4.2 Autenticação

O acesso se dá via email + magic link (link único enviado por email) ou OAuth com Google. **Não há senhas** armazenadas pela R2 no MVP.

### 4.3 Segurança da conta

O Usuário é responsável por:
- Manter confidencialidade do acesso ao seu email
- Não compartilhar links de magic link com terceiros
- Reportar imediatamente ao Cliente qualquer acesso não autorizado suspeito
- Realizar logout em dispositivos compartilhados

A R2 não se responsabiliza por uso indevido decorrente de negligência do Usuário em proteger o próprio email.

### 4.4 Encerramento de conta

A conta do Usuário é encerrada quando:
- O Cliente solicita (geralmente após desligamento do colaborador)
- O Cliente encerra o contrato com a R2
- O Usuário exerce direito de eliminação (LGPD Art. 18)

Dados podem ser mantidos por períodos legais de retenção (ex: 5 anos para atestados conforme CLT Art. 168) mesmo após encerramento da conta.

---

## 5. Uso aceitável

O Usuário concorda em **NÃO**:

- Acessar dados de colaboradores fora do escopo autorizado pelo seu papel (RBAC)
- Tentar burlar mecanismos de segurança (RLS, RPC checks, RBAC)
- Compartilhar capturas de tela contendo dados pessoais de outros colaboradores
- Usar a Plataforma para fins ilícitos, discriminatórios ou de assédio
- Fazer engenharia reversa, descompilar ou tentar extrair código-fonte
- Realizar scraping massivo ou ataques de negação de serviço
- Inserir dados falsos ou maliciosos (XSS, SQL injection)
- Compartilhar conteúdo de 1:1s privadas com terceiros (princípio de confidencialidade)

Violações podem resultar em **suspensão imediata da conta** sem aviso prévio, além de medidas legais cabíveis.

---

## 6. Conteúdo gerado pelo Usuário

### 6.1 Propriedade

Os dados inseridos pelo Usuário (avaliações, comentários, PDIs, notas de 1:1, etc.) são de propriedade do **Cliente** (empregador/contratante), não da R2 nem do Usuário individual.

Exceção: o conteúdo das **notas privadas de 1:1** pertence ao autor da nota (líder), conforme [Política específica de 1:1s](r2_people_privacy_oneonones.md).

### 6.2 Licença para a R2

Ao inserir conteúdo na Plataforma, o Usuário concede à R2 licença não-exclusiva, gratuita e mundial para armazenar, processar e exibir esse conteúdo, **exclusivamente para fins de operação da Plataforma** em nome do Cliente.

A R2 **não** usa conteúdo do Cliente para:
- Treinar modelos de IA próprios
- Compartilhar com terceiros para fins comerciais
- Análises agregadas que possam identificar indivíduos

### 6.3 Responsabilidade pelo conteúdo

O Usuário é responsável pelo conteúdo que insere. Conteúdo ofensivo, discriminatório, falso ou ilegal pode ser removido pelo Cliente ou pela R2 mediante denúncia, sem aviso prévio.

---

## 7. Disponibilidade do serviço

### 7.1 SLA

| Plano | SLA mensal | Crédito por descumprimento |
|---|---|---|
| Starter | 99,0% | 1 mês de assinatura por trimestre não cumprido |
| Business | 99,5% | 1 mês de assinatura por mês não cumprido |
| Enterprise | 99,9% (negociável) | Conforme contrato |

Períodos de manutenção programada (geralmente noturna ou madrugada de domingo, com aviso de 48h) não contam para o cálculo de SLA.

### 7.2 Backups

Backups automáticos do banco de dados são realizados:
- Snapshots completos: diários, retidos por 30 dias
- Point-in-time recovery: últimos 7 dias
- Backups off-site (região distinta): semanais, retidos por 90 dias

Em caso de incidente, recuperação prioritária para os últimos 24h.

### 7.3 Limitações de uso

| Recurso | Limite |
|---|---|
| Tamanho de arquivo (PDF de atestado, evidência PDI) | 10 MB por upload |
| Total de storage por tenant | 5 GB no Business, ilimitado no Enterprise |
| Requisições por minuto | 1000 por usuário |
| Sessões simultâneas | 5 por usuário |

Tentativas de burlar limites podem resultar em bloqueio temporário.

---

## 8. Propriedade intelectual da R2

### 8.1 Plataforma

A Plataforma (código-fonte, design, marca "R2 People", documentação, schemas SQL, padrões de UX) é propriedade exclusiva da R2 Soluções Empresariais Ltda. Está protegida por leis de propriedade intelectual e direitos autorais.

### 8.2 Marca

"R2 People" e o logotipo R2 são marcas da R2 Soluções Empresariais. O Cliente recebe licença de uso limitada para identificar a Plataforma no ambiente interno.

### 8.3 Sem transferência

Estes Termos **não** transferem qualquer direito de propriedade intelectual sobre a Plataforma ao Cliente ou Usuário.

---

## 9. Pagamento e cobrança

Aplicável apenas ao Cliente (não ao Usuário individual). Detalhes em contrato comercial separado:

- Cobrança mensal por colaborador ativo (modelo per-seat)
- Faturamento por boleto ou cartão de crédito empresarial
- Inadimplência superior a 30 dias resulta em suspensão da conta
- Suspensão prolongada (>90 dias) resulta em encerramento e exportação obrigatória de dados em CSV

---

## 10. Privacidade e proteção de dados

### 10.1 LGPD

A R2 atua como **operador** dos dados, processando-os conforme instrução do **controlador** (Cliente).

Detalhes completos na [Política de Privacidade](r2_people_privacy_policy.md):
- Bases legais para tratamento
- Direitos do titular (Art. 18)
- Transferência internacional
- Retenção e eliminação
- Notificação de incidentes (Art. 48)

### 10.2 Categorias especiais

Atestados médicos contêm dados sensíveis (categoria especial, LGPD Art. 11). Acesso é restrito ao DP autorizado, conforme detalhado em [spec de Atestados](docs/spec_m3_atestados.md). Líderes que submetem atestados perdem acesso ao conteúdo após upload.

### 10.3 1:1s

Conteúdo de 1:1s tem modelo de privacidade arquitetural em 3 camadas. Ver [Política específica](r2_people_privacy_oneonones.md).

### 10.4 Direitos do titular

Para exercer direitos da LGPD:
- **Acesso aos dados**: solicitar ao DPO do Cliente
- **Correção**: editar campos próprios na tela "Minha Jornada" ou solicitar via workflow G3
- **Eliminação**: solicitar ao DPO do Cliente (sujeito a retenções legais)
- **Portabilidade**: export CSV/JSON via DPO

---

## 11. Limitação de responsabilidade

A R2 não se responsabiliza por:

- Decisões de negócio tomadas com base em informações da Plataforma (a Plataforma é ferramenta, não consultora)
- Imprecisões em dados inseridos por usuários do Cliente
- Indisponibilidade de provedores terceiros (Supabase, Vercel, Google OAuth) acima do SLA
- Perda de dados decorrente de ação maliciosa do próprio Cliente (ex: admin excluindo registros)
- Conformidade fiscal específica do Cliente (cálculos de folha são referenciais, conferir com contador)

Limite máximo de responsabilidade: valor total pago pelo Cliente nos 12 meses anteriores ao evento.

---

## 12. Indenização

O Usuário concorda em indenizar a R2 por reclamações, perdas ou danos decorrentes de:
- Violação destes Termos
- Uso indevido da Plataforma
- Inserção de conteúdo ilegal, ofensivo ou que viole direitos de terceiros
- Compartilhamento não autorizado de dados de outros colaboradores

---

## 13. Modificações dos Termos

A R2 pode atualizar estes Termos periodicamente. Mudanças materiais (que afetem direitos do Usuário) serão notificadas com **30 dias de antecedência** via:
- Banner na Plataforma
- Email para o admin do Cliente
- Atualização da versão neste documento

O uso continuado da Plataforma após a entrada em vigor das novas versões implica aceite.

---

## 14. Encerramento e retenção pós-encerramento

### 14.1 Pelo Cliente

O Cliente pode encerrar o contrato a qualquer momento com **30 dias de antecedência**. Após o encerramento:
- Acesso à Plataforma é desativado
- Dados ficam disponíveis para exportação por **60 dias**
- Após 60 dias, dados são **anonimizados ou eliminados** (exceto retenções legais)

### 14.2 Pela R2

A R2 pode encerrar contas individuais por violação destes Termos (notificação imediata) ou o contrato comercial por inadimplência (após 90 dias).

### 14.3 Retenções legais

Independente de encerramento, alguns dados são retidos por prazos legais:

| Dado | Retenção mínima | Base legal |
|---|---|---|
| Atestados médicos | 5 anos | CLT Art. 168 |
| Folha de pagamento (referência) | 5 anos | CLT Art. 11 + Lei 8.213/91 |
| Movimentações de RH | 2 anos pós-desligamento | Defesa em ações trabalhistas |
| Audit log de operações | 5 anos | Boas práticas LGPD |
| Histórico de 1:1s | Vida útil do colaborador + 2 anos pós-desligamento | Histórico de evolução |

Após o prazo, dados são anonimizados (remove identificadores diretos, mantém estatísticas agregadas).

---

## 15. Lei aplicável e foro

Estes Termos são regidos pela legislação da República Federativa do Brasil, em especial:
- Lei 10.406/2002 (Código Civil)
- Lei 8.078/1990 (Código de Defesa do Consumidor, quando aplicável)
- Lei 13.709/2018 (LGPD)
- Decreto-Lei 5.452/1943 (CLT)

Fica eleito o **foro da Comarca de Salvador, Bahia**, para dirimir quaisquer controvérsias, com renúncia expressa a qualquer outro, por mais privilegiado que seja.

---

## 16. Disposições gerais

### 16.1 Independência das cláusulas

Se qualquer cláusula destes Termos for considerada inválida ou inexequível, as demais permanecem em pleno vigor.

### 16.2 Não renúncia

A não exigência, pela R2 ou pelo Cliente, de qualquer disposição destes Termos não constitui renúncia ao direito de exigi-la futuramente.

### 16.3 Cessão

O Usuário não pode ceder os direitos e obrigações destes Termos a terceiros. A R2 pode ceder em caso de reorganização societária, fusão ou venda, mediante notificação ao Cliente.

### 16.4 Comunicação

Comunicações oficiais são feitas por email cadastrado na conta do Cliente. Suporte técnico: suporte@solucoesr2.com.br. Questões jurídicas: juridico@solucoesr2.com.br. Questões LGPD: dpo@solucoesr2.com.br.

---

## 17. Histórico de versões

| Versão | Data | Mudanças |
|---|---|---|
| 1.0 | 17 mai 2026 | Versão inicial · complementa Política de Privacidade existente |

---

*Última leitura recomendada por todos os Usuários antes do primeiro acesso. Cópia atualizada sempre disponível em [rh.solucoesr2.com.br/termos](https://rh.solucoesr2.com.br) e neste repositório.*

**Dúvidas?** Contato em juridico@solucoesr2.com.br.
