# Modelo de Proposta Comercial · GPC People

**Versão:** 1.0 · 17 de maio de 2026
**Uso:** template para Ricardo enviar propostas comerciais a PMEs interessadas
**Tipo:** Markdown editável · pode exportar pra PDF via Pandoc ou copiar pro Google Docs

---

## Como usar este template

1. Faça uma cópia (não edite o master)
2. Substitua todos os campos `[ENTRE_COLCHETES]` com dados do cliente
3. Personalize o **Slide 2** com pelo menos 1 dor específica que você ouviu na reunião descoberta
4. Ajuste o **Slide 5** com o pricing exato baseado no headcount real
5. Exporte pra PDF: `pandoc proposta.md -o proposta.pdf --pdf-engine=xelatex`
6. Ou copie pro Google Docs e ajuste branding

---

## Versão completa da proposta

---

# Proposta Comercial · GPC People

**Cliente:** [NOME_DA_EMPRESA]
**Atenção a:** [NOME_DO_DECISOR] · [CARGO]
**De:** Ricardo Silva · R2 Soluções Empresariais
**Data:** [DD/MM/AAAA]
**Validade da proposta:** 30 dias corridos a partir da data acima
**Proposta nº:** PROP-[ANO]-[NNN]

---

## 1. Contexto da conversa

Esta proposta consolida o que conversamos em [DATA_DA_REUNIAO] entre [RICARDO + STAFF_R2] e [DECISOR + STAFF_CLIENTE]. Os pontos centrais que ouvimos:

- **[DOR_1]** · ex: "Não temos visibilidade clara dos PDIs em andamento. Cada líder controla na planilha dele."
- **[DOR_2]** · ex: "Atestados se perdem. Já tivemos problema trabalhista por não acharmos o documento original."
- **[DOR_3]** · ex: "Programação de férias é uma bagunça anual. Líder não sabe quando o colaborador venceu o aquisitivo."
- **[DOR_4]** · ex: "Estrutura tripartite (CTPS na Labuta, mas opera na loja) não cabe nos sistemas atuais."

O **GPC People** foi desenhado especificamente para empresas brasileiras de [HEADCOUNT] colaboradores com essa realidade.

---

## 2. O que está incluso

### Módulos cobertos (todos no preço)

| # | Módulo | O que faz |
|---|---|---|
| 1 | **Ficha de empregado** | Cadastro completo, importação via OCR de fichas Domínio, histórico de admissão/transferências |
| 2 | **Estrutura organizacional** | CRUD de unidades (CTPS), filiais operacionais, departamentos, cargos e níveis |
| 3 | **9-Box** | Matriz potencial × desempenho 3x3 ou 5x5, ciclos formais, snapshots imutáveis |
| 4 | **PDI** | Plano de desenvolvimento individual com ações, evidências e ciclos |
| 5 | **OKRs** | Objetivos e key results com check-ins semanais |
| 6 | **1:1s estruturadas** | Notas duais (líder privadas + compartilhadas), pauta, action items, mood |
| 7 | **Onboarding** | Templates de jornada de integração com tasks |
| 8 | **Reconhecimentos** | Mural público/privado de elogios entre colegas |
| 9 | **Feedback contínuo** | Solicitação e envio de feedback a qualquer momento |
| 10 | **Atestados** | OCR client-side, validação DP, gera afastamento automático ≥3d |
| 11 | **Férias** | Gestão visual com Gantt, programação anual, regras CLT enforced |
| 12 | **Movimentações** | Promoções, transferências, ajustes salariais com aprovação RH |
| 13 | **Folha & Custo** | Calculadora individual, folha por filial, regime tributário |
| 14 | **Clima organizacional** | Pulsos semanais anônimos, mood faces, heatmap por unidade |
| 15 | **eNPS** | Pesquisa quinzenal Net Promoter Score com tendência |
| 16 | **Comunicados internos** | Feed editorial RH/Diretoria com priorização |
| 17 | **Vagas internas** | Banco de talentos com programa de indicação (R$ 1.500 padrão) |
| 18 | **Trilhas de treinamento** | LMS-style com obrigatórias, opcionais, certificados |
| 19 | **Dashboards e relatórios** | Por equipe, tenant-wide, drilldown, exportação |
| 20 | **Tela do colaborador** | Minha jornada, autosserviço com workflow de solicitações |

### Infraestrutura incluída

- Hospedagem em Supabase (Postgres 16 com RLS) + Vercel (frontend)
- Backups automáticos diários (30d retenção)
- Point-in-time recovery (últimos 7 dias)
- SSL/TLS automático
- CDN para velocidade em todo o Brasil
- Monitoramento 24/7 (alerta se downtime)

### Conformidades

- **LGPD**: privacy by design (RLS no banco, não só na tela)
- **CLT Art. 130-143** (férias): regras embarcadas no schema
- **CLT Art. 168** (atestados): retenção 5 anos garantida
- **eSocial-compatível**: campos preparados para integração futura
- **Lei 15.270/2025** (IRRF): tabela 2026 atualizada

---

## 3. O que NÃO está incluso (deliberado)

Para evitar surpresa, listamos o que **deliberadamente NÃO** é parte do escopo:

- ❌ Integração ERP (TOTVS, WinThor, Senior): por escolha de produto · entrada por CSV
- ❌ Folha de pagamento real (cálculo final que vai pro RAIS/CAGED): use seu sistema atual
- ❌ Ponto eletrônico (bater ponto): mantenha seu sistema atual
- ❌ App nativo iOS/Android: PWA responsivo cobre 100% das funcionalidades
- ❌ Multi-idioma: PT-BR exclusivo
- ❌ Pesquisa de mercado salarial: usamos suas faixas configuradas
- ❌ Recrutamento externo (publicar vagas em sites): vagas internas apenas
- ❌ Treinamentos como conteúdo: importamos seus PDFs/vídeos, não produzimos
- ❌ Consultoria de RH: ferramenta, não serviço de consultoria

Se algum desses for crítico, conversamos sobre customização (sob orçamento separado).

---

## 4. Cronograma de implementação

### Fase 1 · Setup e migração (semanas 1-2)
- Criação do tenant
- Cadastro de empregadores (CTPS) e unidades operacionais
- Importação de colaboradores via CSV
- Configuração de perfis de permissão
- Definição de cargos e bandas salariais
- Treinamento do administrador (4h)

**Entregável:** ambiente populado, acesso liberado pra admin do cliente.

### Fase 2 · Onboarding dos líderes (semanas 3-4)
- Convite por email magic link a todos os líderes
- Webinar de 1h apresentando a plataforma
- Mini-tutoriais por módulo (vídeos curtos)
- Suporte priorizado nas primeiras 2 semanas

**Entregável:** líderes ativos e usando 1:1s, PDI, reconhecimentos.

### Fase 3 · Onboarding de colaboradores (semanas 5-6)
- Convite por email + comunicação interna
- Vídeo de boas-vindas customizado
- Primeiros pulsos de clima abertos
- Acompanhamento de adoção semanal

**Entregável:** ≥70% dos colaboradores fizeram primeiro acesso.

### Fase 4 · Acompanhamento (semanas 7-12)
- Reunião quinzenal de checkpoint
- Ajustes finos baseados em uso real
- Relatório de adoção mensal
- Identificação de quick wins

**Entregável:** uso consolidado, métricas de engajamento estáveis.

---

## 5. Investimento

### Modelo de cobrança

Cobrança mensal **por colaborador ativo**. Inativos (desligados) não contam. Estagiários e jovens aprendizes contam pela metade.

### Tabela de preços 2026

| Plano | Faixa | Preço/colab/mês | Valor estimado (com [HEADCOUNT] colab) |
|---|---|---|---|
| Starter | até 100 colab | R$ 12 | n/a |
| **Business** | 100-500 colab | **R$ 18** | **R$ [HEADCOUNT × 18]** |
| Enterprise | 500+ colab | sob consulta | n/a |

### Sua proposta específica

| Item | Valor |
|---|---|
| Plano: **Business** | R$ 18 / colaborador / mês |
| Colaboradores ativos: **[HEADCOUNT]** | × |
| **Mensalidade total** | **R$ [HEADCOUNT × 18]** / mês |
| Setup inicial | **Grátis** (incluso) |
| Treinamento admin (4h) | **Grátis** (incluso) |
| Suporte | **Grátis** (incluso) |

**Anual:** R$ [HEADCOUNT × 18 × 12] (pago mensalmente · sem multa de fidelidade)

### Desconto especial GPC-âncora

Como cliente-âncora (validou o produto com a R2 durante o desenvolvimento), o GPC paga **R$ 14/colab/mês** (22% off do preço Business padrão).

### Forma de pagamento

- Boleto bancário com vencimento todo dia 15
- Cartão de crédito empresarial (taxa 2% adicional)
- PIX (sem custo adicional, mas requer aprovação manual)

### Reajuste

- Primeiro reajuste apenas após 12 meses
- Indexador: **IPCA acumulado** + 1% (custo de infraestrutura cloud)
- Comunicação obrigatória 60 dias antes

---

## 6. SLA · Service Level Agreement

| Aspecto | Compromisso |
|---|---|
| Uptime mensal | **99,5%** (Business) ou 99,9% (Enterprise) |
| Tempo de resposta a chamado | 1 dia útil (Business) ou 4h (Enterprise) |
| Tempo de resolução de bug crítico | 8h úteis |
| Backup completo | Diário · retenção 30 dias |
| Point-in-time recovery | Últimos 7 dias |
| Notificação de incidente LGPD | até 24h (legal: 72h ANPD) |

### Crédito por descumprimento de SLA

| Uptime | Crédito |
|---|---|
| 99,5% - 99,0% | 5% da mensalidade |
| 99,0% - 95,0% | 10% da mensalidade |
| < 95,0% | 25% da mensalidade + escalation pessoal |

---

## 7. Riscos e mitigação

### Para você (cliente)

| Risco | Mitigação |
|---|---|
| R2 fechar ou parar de operar | Banco é do cliente (Supabase). Export completo via DSAR LGPD. Schemas SQL são abertos. Sem lock-in. |
| Dependência de Ricardo Silva | Documentação completa, código fonte versionado em repo git. Em caso extremo, outra empresa pode dar continuidade. |
| Vazamento de dados | RLS no banco, criptografia em trânsito (TLS) e em repouso. Cláusula contratual de responsabilidade. Notificação ANPD em 72h. |
| Custos saírem do controle | Cobrança por colab ativo · você só paga pelo que usa. Sem mínimo escondido. |

### Para nós (R2)

| Risco | Mitigação |
|---|---|
| Cliente não pagar | Suspensão automática após 30 dias de inadimplência. |
| Uso abusivo | Limites técnicos no plano · upgrade automático com aviso. |
| Solicitações infinitas de customização | Backlog priorizado · acessórias sob orçamento separado. |

---

## 8. Termos legais

### Validade

Esta proposta é válida por **30 dias corridos** a partir de [DATA]. Após esse prazo, sujeita a revisão de preços e termos.

### Contrato

O aceite desta proposta gera contrato com:
- Política de Privacidade ([rh.solucoesr2.com.br/r2_people_privacy_policy](https://rh.solucoesr2.com.br/r2_people_privacy_policy.md))
- Termos de Uso ([rh.solucoesr2.com.br/r2_people_terms_of_service](https://rh.solucoesr2.com.br/r2_people_terms_of_service.md))
- Política específica de 1:1s ([rh.solucoesr2.com.br/r2_people_privacy_oneonones](https://rh.solucoesr2.com.br/r2_people_privacy_oneonones.md))

### Foro

Comarca de **Salvador, Bahia**.

### Cancelamento

Sem fidelidade. Cancela com **30 dias de antecedência** por escrito (email para juridico@solucoesr2.com.br). Após cancelamento, dados ficam disponíveis para export por 60 dias, depois são anonimizados ou eliminados (exceto retenções legais como CLT Art. 168).

---

## 9. Próximos passos

Se topa, basta:

1. Responder este email com "Aceito a proposta PROP-[ANO]-[NNN]"
2. Assinar contrato (enviamos em até 1 dia útil, formato eletrônico)
3. Agendar reunião de kickoff (1h) na semana seguinte

Quer testar antes de fechar? Te ofereço **piloto gratuito de 60 dias** com até 30 colaboradores. Sem compromisso, sem cartão, sem cláusula de continuação automática.

---

## 10. Sobre a R2 Soluções Empresariais

- **CNPJ**: [XX.XXX.XXX/0001-XX]
- **Endereço**: [ENDERECO_COMPLETO_SALVADOR_BA]
- **Site**: [solucoesr2.com.br](https://solucoesr2.com.br)
- **Demonstração**: [rh.solucoesr2.com.br](https://rh.solucoesr2.com.br)

### Quem somos

Empresa baiana de tecnologia para PMEs. Fundada em [ANO_FUNDACAO] por Ricardo Silva (ex-TI de redes regionais por 15 anos), atendemos hoje clientes como **Grupo Pinto Cerqueira** (rede de supermercados · 367 colaboradores · cliente-âncora desde 2024), **[CLIENTE_2]** e **[CLIENTE_3]**.

Especialidade em produtos para **PMEs com estrutura tripartite** (empresa CTPS distinta do tomador operacional · comum em redes regionais que terceirizam atividades).

### Contatos

- **Comercial e técnico**: Ricardo Silva · ricardo@solucoesr2.com.br · +55 71 9XXXX-XXXX
- **Jurídico**: juridico@solucoesr2.com.br
- **LGPD/DPO**: dpo@solucoesr2.com.br
- **Suporte (após contratação)**: suporte@solucoesr2.com.br

---

## 11. Anexos

- [ANEXO_1] · Demonstração ao vivo (link Calendly para agendamento)
- [ANEXO_2] · Política de Privacidade completa
- [ANEXO_3] · Termos de Uso completos
- [ANEXO_4] · Casos de uso reais GPC (com permissão para citar)

---

**Obrigado pela oportunidade. Estamos à disposição para qualquer dúvida.**

Ricardo Silva
R2 Soluções Empresariais
Salvador · Bahia · Brasil

---

*Esta proposta foi gerada a partir do template `r2_people_modelo_proposta.md` versão 1.0. Última atualização do template: 17 mai 2026.*
