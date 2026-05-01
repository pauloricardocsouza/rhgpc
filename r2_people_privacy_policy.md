# Política de Privacidade do R2 People

> **Versão:** 1.0
> **Vigência a partir de:** 1 de maio de 2026
> **Última atualização:** 28 de abril de 2026
> **Aplicação:** plataforma R2 People em todos os tenants (clientes) operados pela R2 Soluções Empresariais

---

## Apresentação

Esta Política de Privacidade descreve como o **R2 People** (a plataforma) coleta, usa, armazena, compartilha e protege os dados pessoais dos seus usuários · em especial dos colaboradores das empresas que contratam o serviço.

O documento foi escrito principalmente para **você, colaborador**, em linguagem direta e sem juridiquês excessivo. Ele também serve como referência formal para empresas contratantes, autoridades públicas e o time de auditoria.

A R2 leva privacidade a sério: **a maior parte do que está descrito nesta política é tecnicamente garantida pela arquitetura do sistema, não apenas declarada**. Onde isso acontece, o documento aponta a referência técnica correspondente.

Em caso de dúvidas, fale com o **Encarregado de Proteção de Dados (DPO)** da empresa onde você trabalha (no Grupo Pinto Cerqueira, por exemplo, é Carla Moreira) ou diretamente com o time R2 pelos canais ao final desta política.

---

## 1. Quem somos e nosso papel

A **R2 Soluções Empresariais LTDA** (CNPJ a confirmar, sede em Feira de Santana, Bahia) é a empresa que desenvolveu, opera e mantém a plataforma R2 People.

Em termos da LGPD, é importante diferenciar dois papéis:

- **Controlador dos dados pessoais**: é a empresa onde você trabalha (por exemplo, Grupo Pinto Cerqueira). É ela quem decide quais dados são coletados sobre seus colaboradores, para quais finalidades, e por quanto tempo. Você foi contratado por ela, e os dados existem por causa dessa relação.

- **Operador dos dados pessoais**: é a R2 Soluções Empresariais. Operamos a plataforma, executamos as instruções do controlador, e protegemos os dados conforme esta política e o contrato firmado com a empresa contratante. **Não usamos seus dados para finalidades próprias.**

Essa distinção é prevista no Art. 5º, VI e VII da LGPD e tem efeitos práticos: por exemplo, se você quer ser esquecido após o desligamento, o pedido vai para o RH da sua empresa (controlador). A R2 executa, mas não decide sozinha.

---

## 2. Dados pessoais que tratamos

A plataforma processa os seguintes grupos de dados pessoais:

### 2.1 Dados cadastrais e de identificação

- Nome completo, nome social (se aplicável), apelido
- CPF (apenas mascarado em telas comuns; completo apenas para o RH com permissão `export_sensitive`)
- Data de nascimento, gênero (autodeclarado, opcional)
- Foto de perfil (se você optou por enviar)

### 2.2 Dados de contato

- E-mail corporativo e pessoal
- Telefones (celular pessoal, ramal corporativo)
- Endereço residencial (se solicitado pela empresa)
- Contato de emergência (nome, relação, telefone)

### 2.3 Dados de vínculo e funcionais

- Matrícula, data de admissão, data de desligamento (se aplicável)
- Empregador (CNPJ que paga sua folha) e Tomador (filial onde você trabalha)
- Cargo, departamento, gestor direto, tipo de contrato (CLT, terceirizado, estágio etc.)
- Salário base, faixa salarial do cargo, histórico de reajustes
- Movimentações funcionais aprovadas (promoções, transferências, mudanças de cargo)

### 2.4 Dados de avaliação e desempenho

- Notas de auto-avaliação e de avaliação do gestor por competência
- Comentários escritos por você e pelo seu gestor
- Posicionamento na matriz 9-Box (se a empresa habilitou esse módulo)
- Plano de Desenvolvimento Individual (PDI), com objetivos e progressos
- Feedbacks recebidos e enviados (privados ou anônimos), elogios públicos

### 2.5 Dados de uso da plataforma

- Login (data, hora, endereço IP, navegador, sistema operacional)
- Páginas que você acessou e em que ordem (apenas dentro do R2 People)
- Notificações que você recebeu e abriu

### 2.6 Dados que NÃO coletamos

Para deixar claro o que **não** tratamos:

- Não rastreamos sua localização fora do contexto de login
- Não temos acesso a câmera, microfone ou contatos do seu celular
- Não usamos cookies de terceiros para publicidade
- Não compartilhamos seus dados com Google Analytics, Facebook Pixel ou afins
- Não temos acesso aos seus dados bancários completos (apenas banco e agência, se a empresa decidir armazenar para folha)

---

## 3. Para que usamos seus dados

A LGPD exige que cada uso (finalidade) seja declarado. As principais são:

| Finalidade | Base legal (LGPD) | Exemplo concreto |
|---|---|---|
| Identificá-lo na plataforma | Execução de contrato (Art. 7º, V) | Login, exibição do nome no mural |
| Operar avaliações de desempenho | Execução de contrato + legítimo interesse (Art. 7º, V e IX) | Auto-avaliação, avaliação do gestor |
| Permitir feedback entre colegas | Legítimo interesse (Art. 7º, IX) | Mural de elogios, feedback contínuo |
| Tomar decisões funcionais (promoção, reajuste) | Execução de contrato (Art. 7º, V) | Movimentação de promoção registrada |
| Cumprir obrigações trabalhistas | Cumprimento de obrigação legal (Art. 7º, II) | Histórico para eSocial, dissídio CCT |
| Garantir segurança e auditoria | Cumprimento de obrigação legal + legítimo interesse | Trilha de auditoria, detecção de fraude |
| Aprimorar a plataforma | Legítimo interesse (Art. 7º, IX) | Análise agregada de uso (sem identificá-lo) |

**Não usamos seus dados** para:

- Treinar modelos de inteligência artificial fora do escopo da plataforma
- Vender ou ceder informações a terceiros
- Tomar decisões automatizadas que afetem você sem revisão humana · toda promoção, transferência ou rescisão exige aprovação manual de gestor e/ou RH (Art. 20 LGPD)

---

## 4. Como protegemos seus dados (medidas técnicas)

Esta seção descreve mecanismos **realmente implementados** na arquitetura, não apenas declarações de boa intenção.

### 4.1 Isolamento entre empresas (multi-tenant)

Cada empresa-cliente (tenant) tem seus dados completamente isolados dos demais. Isso é garantido por **políticas Row-Level Security (RLS)** aplicadas a todas as tabelas que contêm dados pessoais. Um colaborador do GPC nunca vê, sob nenhuma circunstância, dados de colaboradores de outra empresa cliente da R2.

Referência técnica: arquivo `r2_people_rls_policies_detailed.sql`, seção "tenant isolation".

### 4.2 Visibilidade controlada dentro da própria empresa

Mesmo dentro da sua empresa, nem todos veem tudo. A plataforma aplica **4 dimensões de escopo simultâneas** para decidir quem vê o quê:

1. **Empregador** · RH da Labuta vê apenas colaboradores da Labuta
2. **Tomador** · Gerente do Cestão L1 vê apenas quem trabalha lá, independentemente do empregador
3. **Departamento** · Coordenador de Operações vê apenas o seu departamento e sub-departamentos
4. **Hierarquia** · Líder vê os subordinados diretos e indiretos

Essas regras se combinam por interseção lógica (AND), não por exceções. Você só vê dados de outra pessoa se as 4 dimensões permitirem simultaneamente, ou se for uma exceção explícita autorizada (override temporário com data de validade).

### 4.3 Senhas

Senhas são armazenadas usando algoritmos de hash criptográfico padrão da indústria (`bcrypt` via Supabase Auth). **Nem mesmo a R2 ou o RH da sua empresa consegue ler sua senha original.** Em caso de esquecimento, o caminho é redefinir, não recuperar.

A política de senha mínima (8 caracteres, 1 número, 1 caractere especial, 1 maiúscula) é configurável por empresa e auditável.

### 4.4 Comunicação criptografada

Todo o tráfego entre seu dispositivo e a plataforma usa **HTTPS com TLS 1.3**. Não há transmissão de dados em texto puro.

### 4.5 Trilha de auditoria imutável

Toda ação relevante na plataforma é registrada em um log imutável: quem fez, o que fez, quando, e a partir de qual endereço. **Esse log não pode ser editado nem deletado por ninguém**, nem pelo administrador da empresa, nem pelo time R2 · uma trigger no banco de dados rejeita qualquer tentativa de modificação (referência: LGPD Art. 37).

Você pode pedir para ver as ações que **outras pessoas fizeram em relação aos seus dados** · esse é o seu direito de acesso (item 7.3 desta política).

### 4.6 Sessões com expiração automática

Por padrão, se você ficar 60 minutos sem interação, a sessão expira automaticamente e você precisa fazer login novamente. Isso protege sua conta caso você esqueça aberta em um computador compartilhado. O tempo é configurável pela empresa, mas não pode ser desabilitado.

### 4.7 Backups e recuperação

Backups completos são realizados diariamente e mantidos por 30 dias em ambiente seguro. Em caso de incidente catastrófico, a recuperação completa é possível em até 4 horas.

### 4.8 Onde os dados ficam fisicamente

Os dados são armazenados em data centers da Amazon Web Services (AWS) na **região São Paulo (sa-east-1)**, em território brasileiro. Não há transferência internacional rotineira de dados pessoais. Em caso de uso de subprocessadores estrangeiros (raro), a transferência segue as regras dos Arts. 33 a 36 da LGPD.

---

## 5. Quem pode ver seus dados

### 5.1 Dentro da sua empresa

Quem vê o quê é determinado pelo **perfil de acesso** atribuído pelo RH da sua empresa. Os perfis padrão são:

| Perfil | O que vê | O que não vê |
|---|---|---|
| **Colaborador** (você, por padrão) | Seus próprios dados, suas avaliações, seus feedbacks recebidos, mural público | Dados de outros colaboradores |
| **Líder de equipe** | Subordinados diretos e indiretos | Pares, outros líderes, outras filiais |
| **Gerente de filial** | Quem trabalha na filial dele, independente de empregador | Outras filiais |
| **RH de prestadora** | Apenas funcionários do empregador específico (ex: Labuta), em qualquer filial | Funcionários de outros empregadores |
| **RH corporativo** | Todos da empresa | Auditoria avançada |
| **DPO/Auditor** | Trilha de auditoria completa, mas com cada acesso registrado | Apenas leitura |

Você sempre pode pedir ao RH da sua empresa para saber qual perfil tem hoje.

### 5.2 Time R2 (operador)

O time da R2 Soluções tem acesso técnico limitado e estritamente operacional, com finalidades específicas:

- **Suporte ao cliente** · apenas quando o cliente abre um chamado e autoriza explicitamente o acesso para resolver um problema
- **Manutenção e correção de bugs** · em ambiente de staging, com dados anonimizados sempre que possível
- **Auditoria interna** · para garantir cumprimento desta política

Cada acesso da R2 a dados de produção é registrado na trilha de auditoria da empresa cliente, e pode ser consultado pelo DPO.

### 5.3 Terceiros e subprocessadores

A R2 utiliza os seguintes subprocessadores essenciais para operar a plataforma. Todos têm contratos firmados que os obrigam a cumprir a LGPD ou regulamentação equivalente:

| Subprocessador | Função | Localização |
|---|---|---|
| Amazon Web Services (AWS) | Infraestrutura de banco de dados e backup | São Paulo, Brasil |
| Supabase Inc. | Plataforma de backend gerenciado | EUA / SP (sa-east-1) |
| Vercel Inc. | Edge network para a aplicação web | EUA com edge no Brasil |
| Sentry Inc. | Monitoramento de erros (anonimizado) | EUA |
| Microsoft Corporation | (Opcional) SSO via Azure Entra para empresas que ativam | EUA / Europa |

A lista atualizada está sempre disponível mediante solicitação ao DPO ou em `r2people.com.br/subprocessadores`.

### 5.4 Autoridades públicas

Compartilhamos dados com autoridades públicas (ANPD, Ministério Público, Justiça do Trabalho, polícias) **apenas mediante ordem judicial ou requisição formal devidamente fundamentada**, e somente o estritamente necessário. Sempre que legalmente possível, notificamos você antes da entrega.

---

## 6. Por quanto tempo guardamos seus dados

A retenção segue duas regras distintas:

### 6.1 Enquanto você é colaborador ativo

Todos os dados são mantidos enquanto durar o vínculo trabalhista, atualizados em tempo real conforme suas movimentações.

### 6.2 Após o desligamento

Após desligamento, os dados entram em **fase de retenção legal**, com prazos diferentes por tipo:

| Tipo de dado | Prazo de retenção | Base legal |
|---|---|---|
| Contrato de trabalho, folha, FGTS | 30 anos | CLT + LGPD Art. 16, II |
| Avaliações de desempenho | 5 anos | Legítimo interesse + comprovação de decisões |
| Feedbacks e elogios | 5 anos (ou apagados a pedido) | Legítimo interesse |
| Documentos de RH (admissão, exames) | 5 anos após desligamento | Obrigação legal |
| Trilha de auditoria | 5 anos | LGPD Art. 37 + obrigação legal |

### 6.3 Anonimização programada

Após **365 dias do desligamento**, a plataforma executa automaticamente um processo de **anonimização parcial**: seu nome, CPF, e-mail, foto e endereço são substituídos por marcadores genéricos ("Ex-colaborador 12345"), preservando apenas dados estatísticos (datas de vínculo, cargos ocupados, médias de desempenho) que continuam servindo a finalidades agregadas · sem identificá-lo individualmente.

O prazo de 365 dias pode ser ajustado pela empresa nas configurações do tenant, mas não pode ser desativado.

### 6.4 Direito ao esquecimento (Art. 18, IV LGPD)

Você pode solicitar a eliminação completa dos seus dados a qualquer momento após o desligamento, exceto quando a retenção for legalmente obrigatória (folha, FGTS, contratos). Quando exigido por lei, o dado fica em armazenamento restrito, acessível apenas a operações legais necessárias.

---

## 7. Seus direitos como titular dos dados

A LGPD garante uma série de direitos a você. **Todos eles são exercitáveis diretamente pela plataforma, sem burocracia:**

### 7.1 Direito de confirmar a existência de tratamento (Art. 18, I)

Você tem direito de saber se a plataforma trata dados pessoais seus. Resposta: **se você está logado, a plataforma trata seus dados** · e esta política descreve quais.

### 7.2 Direito de acesso (Art. 18, II)

Você pode visualizar a qualquer momento todos os seus dados pessoais armazenados:

- Tela "Meus dados" no seu perfil mostra cadastro, vínculo, salário, banco, histórico
- Tela "Minhas movimentações" mostra todas as decisões funcionais sobre você
- Tela "Minhas avaliações" mostra todas as suas avaliações em todos os ciclos
- Tela "Auditoria pessoal" (em desenvolvimento) mostrará todas as ações que outros fizeram sobre seus dados

Você pode também solicitar **exportação completa** dos seus dados em formato estruturado (JSON ou CSV) através da função "Exportar meus dados" no perfil. O download é liberado em até 24 horas.

### 7.3 Direito de correção (Art. 18, III)

Dados desatualizados, incorretos ou incompletos podem ser corrigidos:

- Dados pessoais (telefone, e-mail, endereço): edição direta na tela "Meu perfil"
- Dados funcionais (cargo, salário, departamento): solicitação ao RH, que abre uma movimentação para correção

### 7.4 Direito de eliminação (Art. 18, IV)

Após desligamento, você pode pedir eliminação completa, exceto onde a retenção é obrigatória. O pedido é feito ao DPO da sua empresa.

### 7.5 Direito à portabilidade (Art. 18, V)

Seus dados podem ser exportados em formato JSON ou CSV padrão, prontos para serem importados em outro sistema. Use a função "Exportar meus dados".

### 7.6 Direito de informação sobre compartilhamento (Art. 18, VII)

Esta política e a lista de subprocessadores (item 5.3) cobrem este direito. Atualizações são notificadas com 30 dias de antecedência.

### 7.7 Direito de revogar consentimento (Art. 18, IX)

Quando o tratamento depender de consentimento (raramente · a maior parte é base legal de execução de contrato), você pode revogar a qualquer momento. Algumas funções podem ficar limitadas após revogação.

### 7.8 Direito de revisão de decisão automatizada (Art. 20)

Como mencionado no item 3, a plataforma **não toma decisões automatizadas** que afetem você. Promoções, transferências, rescisões · todas exigem decisão humana. Caso você tenha dúvida sobre alguma decisão, pode solicitar revisão ao RH.

---

## 8. Cookies e tecnologias semelhantes

A plataforma usa apenas **cookies estritamente necessários** ao funcionamento:

- Cookie de sessão (mantém você logado)
- Cookie de preferências (idioma, tema, configurações de UI)
- Cookie de proteção contra falsificação de requisição (CSRF token)

**Não usamos cookies de rastreamento, publicidade ou analytics de terceiros.** A análise interna de uso é feita com dados agregados que não permitem reidentificação.

Você pode desativar cookies no seu navegador, mas a plataforma deixará de funcionar (não há como manter login sem cookie de sessão).

---

## 9. Crianças e adolescentes

A plataforma é destinada a uso profissional adulto. Aceitamos **menores aprendizes (a partir de 14 anos)** e **estagiários (a partir de 16 anos)** quando a empresa contratante os emprega legalmente, com consentimento dos responsáveis quando aplicável (LGPD Art. 14).

Não tratamos dados de crianças menores de 14 anos sob nenhuma circunstância.

Para aprendizes e estagiários, restrições adicionais se aplicam:

- Mural de elogios: leitura permitida, criação restrita
- Feedback anônimo: pode receber, mas o emissor sempre é registrado para fins de mediação em caso de necessidade
- Avaliações: seguem o ciclo normal, mas comentários são revisados pelo gestor antes de finalização

---

## 10. Incidentes de segurança

Em caso de incidente que possa causar **risco ou dano relevante** aos titulares (ex: vazamento de dados pessoais), seguiremos o procedimento exigido pela LGPD:

1. **Em até 24 horas após detecção**: notificação interna ao DPO da empresa cliente afetada
2. **Em até 72 horas**: notificação à ANPD com detalhamento do incidente
3. **Comunicação aos titulares afetados**: prazo razoável conforme a gravidade
4. **Relatório de impacto** disponibilizado ao DPO e à ANPD

A R2 mantém **plano de resposta a incidentes** documentado e revisado anualmente, com simulações periódicas (table-top exercises).

Para reportar qualquer suspeita de incidente: **dpo@solucoesr2.com.br** ou diretamente o DPO da sua empresa.

---

## 11. Atualizações desta política

Esta política pode ser atualizada periodicamente. Quando isso acontecer:

- **Mudanças menores** (clarificação de redação, ajustes de formato): aplicação imediata, com aviso na próxima sessão de login
- **Mudanças relevantes** (nova finalidade, novo subprocessador, alteração de retenção): notificação com **30 dias de antecedência**, e necessidade de aceite explícito antes de continuar usando a plataforma

Versões anteriores ficam arquivadas em `r2people.com.br/privacidade/historico` para consulta histórica.

---

## 12. Como entrar em contato

### 12.1 Para exercer seus direitos como titular

**Primeiro caminho**: use as funcionalidades da própria plataforma (telas listadas no item 7).

**Segundo caminho**: contate o DPO da sua empresa (controlador). No GPC, é Carla Moreira · endereço fixo `dpo@gpc.com.br`. Em outras empresas, consulte o Recursos Humanos.

**Terceiro caminho**: contate o time R2 (operador) · `dpo@solucoesr2.com.br`. Nesses casos, costumamos encaminhar para o DPO do controlador, que é quem decide.

### 12.2 Para reportar problemas técnicos ou bugs

`suporte@solucoesr2.com.br` ou abertura de chamado pela própria plataforma (menu Ajuda).

### 12.3 Para sugestões e elogios sobre a plataforma

`feedback@solucoesr2.com.br`. Lemos tudo, mas nem sempre conseguimos responder individualmente.

### 12.4 Em caso de discordância com a R2 ou com sua empresa

Você pode acionar a **Autoridade Nacional de Proteção de Dados (ANPD)** pelo site `https://www.gov.br/anpd/` ou pelo Ministério Público da sua região.

---

## 13. Disposições finais

Esta política é regida pelas leis brasileiras, em especial pela **Lei nº 13.709/2018 (LGPD)** e pelas resoluções, guias e enunciados da ANPD.

Eventuais conflitos entre esta política e o contrato firmado com sua empresa empregadora devem ser comunicados ao DPO. Em caso de litígio, o foro é a Comarca de Feira de Santana, Bahia.

A R2 Soluções Empresariais reserva-se o direito de prestar esclarecimentos adicionais por meio de FAQs, comunicados e respostas individuais às solicitações dos titulares.

---

> *Documento aprovado pela direção da R2 Soluções Empresariais e revisado por consultoria jurídica externa especializada em LGPD em 28 de abril de 2026.*

> *Próxima revisão programada: outubro de 2026.*

---

## Apêndice A · Glossário rápido

- **ANPD**: Autoridade Nacional de Proteção de Dados, órgão regulador da LGPD no Brasil.
- **Anonimização**: processo que substitui dados identificáveis por marcadores genéricos, impossibilitando reidentificação.
- **Base legal**: motivo jurídico que autoriza o tratamento de dado pessoal (Art. 7º LGPD).
- **Controlador**: quem decide sobre o tratamento dos dados (sua empresa).
- **DPO** (Data Protection Officer) ou Encarregado: pessoa responsável pela proteção de dados na empresa.
- **DSAR** (Data Subject Access Request): pedido formal de acesso aos próprios dados.
- **LGPD**: Lei Geral de Proteção de Dados, Lei nº 13.709/2018.
- **Operador**: quem trata os dados em nome do controlador (a R2).
- **Pseudonimização**: substituição de identificadores diretos por códigos, mantendo possível a reidentificação com chave separada.
- **Subprocessador**: empresa terceira que processa dados em nome do operador.
- **Tenant**: cada empresa cliente com seus dados isolados.
- **Titular**: a pessoa a quem os dados pessoais se referem (você).

---

## Apêndice B · Referências cruzadas com a arquitetura técnica

Para garantia de que esta política é **executada e não apenas declarada**, segue mapeamento entre cláusulas da política e arquivos/recursos técnicos do produto:

| Cláusula desta política | Implementação técnica |
|---|---|
| Item 4.1 (isolamento multi-tenant) | `r2_people_rls_policies_detailed.sql` · todas as policies filtram por `company_id = current_user_company_id()` |
| Item 4.2 (4 dimensões de visibilidade) | `r2_people_rls_policies_detailed.sql` · função `can_see_user_company()` |
| Item 4.5 (trilha imutável) | `r2_people_schema_v3.sql` · tabela `audit_log` + trigger `audit_log_immutable` |
| Item 4.6 (sessões com expiração) | `r2_people_seed_initial.sql` · `companies.settings.session_idle_timeout_minutes` |
| Item 6.3 (anonimização programada) | `r2_people_seed_initial.sql` · `companies.settings.anonymize_after_termination_days` |
| Item 7.2 (direito de acesso) | Telas: Meus dados, Minhas movimentações, Minhas avaliações |
| Item 7.5 (portabilidade) | Edge Function "Exportar meus dados" → ZIP com JSON/CSV |
| Item 9 (proteção de aprendizes/estagiários) | Verificações por idade no schema + RLS específicas |
| Item 10 (resposta a incidentes) | Plano interno R2 + relatório semestral à ANPD |

---

**R2 Soluções Empresariais LTDA**
Feira de Santana, Bahia, Brasil
`dpo@solucoesr2.com.br` · `r2people.com.br`
