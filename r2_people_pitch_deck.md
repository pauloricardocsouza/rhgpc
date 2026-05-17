# R2 People · Pitch Deck Comercial

**Para:** PMEs brasileiras de 100-1000 colaboradores
**Posicionamento:** plataforma de RH para redes regionais com estrutura tripartite
**Versão:** 1.0 · 17 de maio de 2026

---

## Slide 1 · Capa

> ## R2 People
> **Gestão de pessoas pra empresas que cresceram além das planilhas**
>
> R2 Soluções Empresariais · Bahia, BR

---

## Slide 2 · O problema

PMEs brasileiras médias chegam num ponto em que **planilhas + WhatsApp + e-mail não dão mais conta**.

- 300+ colaboradores espalhados em 10+ filiais
- 3-4 empresas no mesmo grupo (CTPS distinto da operação)
- Atestados chegam em papel, ninguém sabe onde estão
- PDIs viram lembrancinha de feedback semestral
- Férias são planejadas em planilha que ninguém atualiza
- LGPD é tratada como "vamos ver depois"

**O resultado:** RH apaga incêndio em vez de desenvolver pessoas. Líderes não têm visibilidade. Colaboradores acham que ninguém escuta.

---

## Slide 3 · Por que as opções atuais não servem

| Opção | O que falta |
|---|---|
| **Senior, TOTVS RM, ERP de folha** | Bom em folha, ruim em desenvolvimento. UI de 2010. Não tem 9-Box, PDI, 1:1s. |
| **Sólides, Qulture.Rocks, Feedz** | Bom em desenvolvimento. Não entende estrutura tripartite (CTPS ≠ tomador). Preço enterprise. |
| **Gupy + Mereo + ferramenta X + outra Y** | Stack frankenstein. 4 logins. Dados não conversam. |
| **Continuar com planilha** | Vai colapsar quando a Karla sair de férias. |

---

## Slide 4 · O que é o R2 People

Plataforma única, pensada pra realidade brasileira:

- 📋 **Ficha de empregado** completa · importação OCR de fichas Domínio
- ⭐ **9-Box** com ciclos formais + avaliações ad-hoc
- 🎯 **PDI** com plano de ação, evidências, ciclos
- 👏 **Reconhecimentos** público/privado com feed
- 🚀 **Onboarding** por templates de jornada
- 📊 **Dashboards** por equipe + tenant-wide com drilldown
- 👤 **Tela do colaborador** (Minha Jornada · auto-serviço com workflow de solicitações)
- 🩺 **Atestados** com OCR client-side e CID protegido (LGPD Art. 11)
- 🏖️ **Férias** com gestão visual + programação anual
- 💬 **1:1s estruturadas** com privacidade arquitetural
- 💰 **Folha & Custo** com legislação 2026 versionada
- 🔐 **LGPD** levada a sério desde o schema (RLS no banco)

---

## Slide 5 · Diferenciais técnicos

### 1. Estrutura tripartite no DNA

Diferente das opções padrão, R2 People modela **CTPS distinto da operação**:

- **EMP** (empregador legal) · ATP, Labuta, Limpactiva, Segure
- **TOM** (tomador operacional) · Cestão Loja 1, Cestão Inhambupe, ATP Varejo, Sede

Reports e queries suportam ambos os eixos via switch. Crítico pra redes que terceirizam atividades operacionais.

### 2. Privacidade como arquitetura

LGPD não é "vamos esconder na tela". Os dados sensíveis (CID, notas de 1:1, mood) estão protegidos pelas **policies RLS no banco**. RH consultando SQL direto não consegue ler conteúdo proibido.

### 3. PT-BR de verdade

Não é tradução. É produto pensado em português, com CLT em mente:

- Período aquisitivo e concessivo de férias
- Fracionamento até 3 partes com regras CLT Art. 134
- IRRF tabela 2026 com Lei 15.270/2025 (isenção até R$ 5k)
- Encargos por regime tributário (Simples Anexo III ≠ Lucro Real)

### 4. Importação OCR

Fichas Domínio em PDF · Tesseract WASM client-side · não envia imagem pra terceiros. Reduz onboarding manual de horas a minutos.

---

## Slide 6 · Demonstração · Fluxo "Atestado do Rafael"

```
1. Sandra (gerente ATP Varejo) recebe atestado físico do Rafael
2. Abre R2 People · /atestados/enviar · seleciona Rafael · tira foto
3. OCR client-side extrai CID, datas, médico
   (a imagem nunca sai do navegador · LGPD preservada)
4. Submete · sistema gera protocolo ATD-2026-04-28-3D72A
5. Sandra perde acesso ao conteúdo · só vê protocol + status
6. Patrícia (DP) abre /dp/atestados · valida com 1 clique
7. Sistema gera movimentação automática (afastamento 7 dias)
8. Rafael recebe notificação · vê em Minha Jornada (sem CID exposto)
```

**Tempo total: 3 minutos.** Antes: papel viajava por 5 dias.

---

## Slide 7 · Casos de uso reais · GPC

**Cliente âncora:** Grupo Pinto Cerqueira (GPC)
- 367 colaboradores · 14 unidades · 4 empregadores · Bahia

**Implementação:**
- 8 meses do primeiro contato à produção
- Validação semanal com Karla (RH), Lucas (Serviços Compartilhados), Carlos (Comercial), Sandra (Varejo)
- 42 telas desenhadas iterativamente antes de qualquer linha de código produtivo

**Resultados (projetados após 6 meses de uso):**
- Tempo de fechamento da folha: -40%
- Atestados extraviados: zero (eram ~5 por mês)
- PDIs ativos: passou de 12% para 77% da empresa
- 1:1s estruturadas: 80% dos líderes com cadência regular

---

## Slide 8 · Stack técnica

| Camada | Tech | Por quê |
|---|---|---|
| **Banco** | Postgres 16 (Supabase) | RLS, JSONB, full-text search PT-BR |
| **Backend** | RPCs SECURITY DEFINER · sem ORM | Performance, segurança auditável |
| **Frontend** | Next.js 14 (App Router) + TS strict + Tailwind | DX moderno, type safety |
| **Auth** | Supabase Auth (magic link + Google OAuth) | Sem senha = menos vazamento |
| **OCR** | Tesseract WASM client-side + FastAPI server (fichas Domínio) | LGPD-friendly |
| **Hosting** | Vercel (front) + Supabase (back) | $30-264/mês conforme escala |
| **Idioma** | PT-BR exclusivo | Mercado-alvo claro |

170 testes backend + TS strict zero erros. Não é protótipo.

---

## Slide 9 · Preços

### Plano Starter
**R$ 12 / colaborador / mês**
- Até 100 colaboradores
- Todos os módulos básicos
- Suporte por email · resposta em 1 dia útil

### Plano Business
**R$ 18 / colaborador / mês** (cliente âncora GPC: R$ 14/mês)
- 100-500 colaboradores
- Todos os módulos + Folha & Custo
- Importação OCR de fichas Domínio
- 1:1s estruturadas com privacidade enforced
- Suporte prioritário (WhatsApp business)

### Plano Enterprise
**Sob consulta**
- 500+ colaboradores
- Customizações no schema (módulos novos)
- SSO SAML/OIDC
- SLA 99.9%
- Onboarding assistido

**Sem fidelidade.** Cancela com 30 dias de antecedência.

---

## Slide 10 · Comparativo

|  | Planilha | ERP folha | Sólides/Qulture | **R2 People** |
|---|:-:|:-:|:-:|:-:|
| Ficha completa | 🟡 | ✅ | ✅ | ✅ |
| Importação OCR | ❌ | ❌ | ❌ | ✅ |
| 9-Box | ❌ | ❌ | ✅ | ✅ |
| PDI com ações | ❌ | 🟡 | ✅ | ✅ |
| Atestados LGPD | ❌ | 🟡 | ❌ | ✅ |
| Férias com Gantt + programação anual | ❌ | 🟡 | ❌ | ✅ |
| 1:1s com privacidade enforced | ❌ | ❌ | 🟡 | ✅ |
| Estrutura tripartite (CTPS ≠ tomador) | ❌ | 🟡 | ❌ | ✅ |
| Folha & Custo com regime tributário | 🟡 | ✅ | ❌ | ✅ |
| PT-BR nativo | ✅ | ✅ | ✅ | ✅ |
| Preço por colab/mês | grátis | R$ 35-80 | R$ 25-60 | **R$ 12-18** |

---

## Slide 11 · O time R2

**Ricardo Silva** · fundador
- 15 anos de TI em redes regionais BA (Pinto Cerqueira, Filadelfia, etc.)
- Engenheiro de dados, BI, integrador
- Cliente-âncora valida cada release

**Anthropic Claude** · co-engenharia
- Sessões de imersão semanais
- Decisões de produto registradas e auditáveis
- Permite operar enxuto sem perder qualidade

**Stack de validação:**
- 170 testes automatizados no backend
- Validação contínua com 6 personas reais do GPC
- Política de privacidade revisada por advogado especializado em LGPD

---

## Slide 12 · Roadmap próximos 6 meses

| Mês | Entrega |
|---|---|
| 1 | D1 · Supabase Auth real em produção |
| 2 | M1 · Estrutura & Acessos completo |
| 2-3 | M3 · Atestados em produção |
| 3-4 | M7 · 1:1s estruturadas |
| 4 | M4 · Férias completo |
| 5 | M6 · Folha & Custo (Calculadora + Folha por filial + Regime tributário) |
| 6 | M9 · Relatórios consolidados + exportação |

A camada de protótipos (42 HTMLs visuais) já existe e está em [rh.solucoesr2.com.br](http://rh.solucoesr2.com.br) pra demos.

---

## Slide 13 · Por que agora

**3 ventos a favor pra PMEs investirem em RH-tech:**

1. **eSocial S-1200** vai apertar fiscalização de afastamentos a partir de 2027 · empresas sem controle digital vão pagar multas
2. **Reforma tributária** muda regras de Simples vs Lucro Real · planilhas não acompanham
3. **Geração Z chega na liderança** · não tolera processos analógicos · vai pra concorrência

Quem digitaliza agora tem 18 meses de vantagem.

---

## Slide 14 · Próximos passos

### Quer ver funcionando?

**Demo guiada · 30 min**
- Tour pelas 42 telas + casos reais GPC
- Marca em ricardo@solucoesr2.com.br
- Sem compromisso · sem comercial chato

### Quer testar com seu time?

**Piloto · 60 dias · 30 colaboradores · grátis**
- Cadastro real do seu time
- Acesso a 6 módulos básicos
- Reunião semanal de checkpoint
- Decisão de continuar ou não no fim do período

### Quer apenas saber o preço?

Tabela acima. Se você é nicho que não cabe (sindicato, gov, ONG), conversa rápida pra entender se faz sentido.

---

## Slide 15 · Encerramento

> **R2 People** é o produto que a Ricardo gostaria de ter quando era TI de uma rede de supermercados.
>
> Sem promessa miraculosa. Sem stack frankenstein. Sem preço enterprise pra startup.
>
> Só software bem feito, em PT-BR, pra PMEs brasileiras que cresceram além da planilha.

**Vamos conversar:**
- ricardo@solucoesr2.com.br
- +55 71 9XXXX-XXXX
- [rh.solucoesr2.com.br](http://rh.solucoesr2.com.br)

---

## Anexo · perguntas frequentes

### "Vocês integram com nosso ERP?"

Não. R2 People é sistema paralelo. Importação via CSV manual cobre 90% dos casos. Decisão deliberada: integração ERP é fonte clássica de bugs. Empresas que precisam de sincronização contratam projeto dedicado, fora do escopo do produto base.

### "Tem perfil público dos colaboradores tipo LinkedIn interno?"

Não. R2 People é ferramenta de RH operacional, não rede social interna. Apelido (`@Fê`) existe pra busca, mas não vira link clicável pra perfil. Reduz LGPD e moderação.

### "Funciona offline?"

Não no MVP. Web responsivo (PWA) é o suficiente. App nativo iOS/Android está no roadmap pós-MVP se houver demanda real.

### "Funciona em inglês?"

Não. PT-BR exclusivo. CLT, eSocial, CAGED, INSS são regulações brasileiras. Adaptar pra outros países exigiria reformular o domínio inteiro.

### "Vocês fazem onboarding?"

Sim no Enterprise. No Business, oferecemos uma sessão de 2h de configuração inicial + biblioteca de vídeos. O produto foi desenhado pra ser auto-evidente.

### "E se a R2 fechar?"

Banco é seu (Supabase). Exportação completa via DSAR LGPD a qualquer momento. Schemas SQL são abertos. Sem lock-in.

---

*Última atualização: 17 maio 2026 · próximas revisões: trimestral*
