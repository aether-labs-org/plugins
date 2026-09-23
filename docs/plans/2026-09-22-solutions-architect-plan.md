# solutions-architect — Plano Técnico de Implementação (v0.3)

**Data:** 2026-09-22
**Status:** Fase 1 implementada (2026-09-22) no branch `feat/solutions-architect-phase1`; smoke dos evals em §15.2 (suíte completa adiada: sandbox de eval sem Bash nesta máquina). Pendente: suíte completa de evals; mínimo efetivo de IAM (H7), que exige um papel não-root
**Repositório:** `aether-labs-org/plugins` (marketplace `aether-labs`)
**Materiais de origem:** `~/Vault/second-brain/AI/solution_architect/` — *compass_artifact…*,
*deep-research-report.md*, *Ferramental e Produtividade para Solution Architects.md* — mais a pesquisa
própria de 2026-09-22 (fontes no §16).

**Legenda de evidência**, usada em todo o documento:

- **[F]** fato verificado, com fonte no §16;
- **[R]** recomendação técnica (julgamento);
- **[H]** hipótese a validar na Fase 0;
- **[D]** decisão tomada pelo dono do produto nas rodadas de perguntas (§2).

---

## 1. Tese central: compor, não reconstruir

1. **[F]** A AWS já distribui o **Agent Toolkit for AWS** (GA em 6/mai/2026): o AWS MCP Server gerenciado,
   skills com curadoria e plugins. O plugin `aws-core` (1.1.0) traz 25 skills, entre elas
   `aws-well-architected-review`, que faz uma revisão WA completa a partir da documentação ao vivo.
2. **[F]** O Claude Code aceita **dependências entre plugins**, inclusive de outros marketplaces
   (`dependencies` + `allowCrossMarketplaceDependenciesOn`).
3. **[F]** O Claude Code adia o carregamento dos schemas de MCP por padrão (tool search).

**Consequência [R]:** o plugin não reimplementa guidance de serviço, busca de documentação nem revisão WA
genérica. Ele entrega o **método do arquiteto de soluções**:

- requisitos mensuráveis;
- decisões com trade-offs;
- diagramas;
- proposta orientada a FinOps;
- IaC validado;
- documentação (desenhada e *as-built*);
- revisão independente.

Tudo fica ligado por um manifest de rastreabilidade versionado no git.
**`aws-core` é o livro de referência; `solutions-architect` é o método.**

---

## 2. Registro de decisões (rodadas de perguntas de 2026-09-22)

| # | Tema | Decisão [D] | Consequência no plano |
|---|---|---|---|
| D1 | Agnosticismo | Plugin único, com **fronteiras agnósticas** e sem mecanismo de adapter | §3 |
| D2 | Usuário principal | **Arquiteto interno**, com acesso às contas | Brownfield (assess, as-built, drift) sobe para a Fase 2 |
| D3 | IaC de primeira classe | **Terraform** | Gate com `terraform validate`, `tflint` e `checkov` (o OpenInfraQuote saiu pela D23); Terraform MCP incluído; CDK/CFN vai para o backlog |
| D4 | `aws-core` | **Dependência obrigatória** | `dependencies` no `plugin.json` |
| D5 | Fonte de preço | **Price List API na v0.1**, sem Pricing Calculator (revisto duas vezes em 2026-09-22; forma final na D21) | §6.2; Pricing Calculator vai para o backlog |
| D6 | Base de preço | **Preço de lista público** (consequência da D5) | Cenário com descontos e compromissos vai para o backlog |
| D7 | Draw.io | **Reaproveitar o plugin oficial do draw.io** (`drawio@drawio`, jgraph) + **skill própria de AWS4 + validador**. Forma refinada pela D20 | §6.1 |
| D8 | Visões obrigatórias | **Topologia AWS, Rede (VPC/AZ/subnets), Fluxo de dados + segurança, DR/multi-região** | 4 arquivos `.drawio` por arquitetura |
| D9 | Documentação | **Markdown**; o usuário escolhe o destino | `docs.path` configurável no manifest (padrão `architecture/`); sem conectores de wiki |
| D10 | Avaliação de qualidade | **Qualitativa (checklist WA)** | O cálculo quantitativo (disponibilidade composta, Service Quotas, FMEA) vai para o backlog |
| D11 | Compliance v0.1 | **LGPD** e **CIS AWS Foundations** | Referências e sensores dedicados na skill `security` |
| D12 | Idioma dos artefatos | **Configurável, padrão pt-BR** | `language: pt-BR` no manifest; o código do plugin fica em inglês |
| D13 | Ações na conta AWS | **Somente leitura, sempre** | O hook **bloqueia** (deny), não pergunta; §9 |
| D14 | Exceção à D13 | **Nenhuma** (revisto: a exceção existia só por causa do Pricing Calculator) | O plugin não escreve nada na conta AWS |
| D15 | Sincronização com o WA Tool | **Não** | A revisão fica só em markdown |
| D16 | Agentes na v0.1 | **Somente Claude Code** | Sem manifests de Codex e Cursor; o `SKILL.md` segue o padrão Agent Skills, para que o porte futuro custe pouco |
| D17 | Nome | **`solutions-architect`** | Neutro de provedor, coerente com a D1. **[H]** colisão de nome (§14) |
| D18 | Módulos Terraform | **`terraform-aws-modules`**, com versão fixada | Menos código gerado; padrões testados pela comunidade |
| D19 | CLI ausente | **Pular e orientar** | O sensor retorna `skipped` com o comando de instalação; o gate não fica verde se faltar um sensor obrigatório |
| D20 | `drawio@drawio` (após a H1) | **Recomendado, não declarado como dependência** | A nossa `diagram` gera o XML AWS4 e exporta chamando a CLI do draw.io direto; se o plugin da jgraph estiver instalado, é usado para Mermaid → `.drawio` e ELK. Instalação sem atrito |
| D21 | Obtenção de preço (após a H4) | **Lookup determinístico** a partir de um mapeamento curado, via `aws pricing get-products` (leitura) | Ajusta a D5: o Pricing MCP fica só para descobrir `usagetype` de recursos que ainda não estão no mapeamento |
| D22 | `CKV_TF_1` × D18 (após a H8) | **Versão do registry + supressão justificada** | `version` exata + `.terraform.lock.hcl` commitado; `CKV_TF_1` suprimido com justificativa padrão no manifest |
| D23 | Conferência cruzada de custo (prototipagem da Fase 1) | **OpenInfraQuote removido**; o delta vem de `price_lookup.py --side before/after` | O OIQ v1.10.0 precificou RDS `db.m7g`, ElastiCache `cache.r7g`, ALB e NAT a USD 0 em sa-east-1 e us-east-1 |
| D24 | Onde declarar a dependência do `aws-core` (prototipagem da Fase 1) | **Na entrada do marketplace, não no `plugin.json`** | No `plugin.json`, a dependência ausente desabilita o plugin inteiro (skills e hook) no `claude plugin eval`; declarada no marketplace, a instalação continua trazendo o `aws-core` ("+ 1 dependency: aws-core") |

---

## 3. Agnosticismo de provedor: viável, na forma certa

**Pergunta:** é possível tornar o plugin agnóstico de provedor e ainda assim conectá-lo só à AWS?
**Resposta:** sim, **desde que o agnosticismo fique no método e não vire uma camada de adaptadores.**

### 3.1 Por que é viável

Boa parte do trabalho do arquiteto não depende de provedor [R]:

- requisitos e NFRs, quality attribute scenarios, ADRs e análise de trade-offs;
- C4, STRIDE, SLO/SLI e estratégias de DR por RTO/RPO;
- o framework FinOps (custo por unidade, alocação, compromissos) e a documentação arc42.

Grande parte do ferramental já é multicloud: Terraform, Checkov, tflint, Prowler, OpenInfraQuote,
draw.io e Mermaid. Os frameworks *well-architected* de AWS, Azure e Google Cloud têm pilares
equivalentes.

### 3.2 Por que não construir uma "interface de provedor" agora [R]

1. **Abstração especulativa.** Com uma única implementação, a fronteira da interface é palpite, e o
   segundo provedor costuma mostrar que ela estava no lugar errado.
2. **Nivelamento por baixo.** Uma camada genérica empurra o design para o que as três nuvens têm em comum
   e desperdiça os diferenciais de cada uma.
3. **Custo de tokens.** Cada indireção é contexto a mais em toda execução.

### 3.3 O que fazer: fronteiras baratas

| Camada | Neutra de provedor | Específica da AWS (isolada) |
|---|---|---|
| Skills de método | `requirements`, `design` (processo), `diagram` (visões lógicas), `docs`, `resilience` (estratégias), `security` (STRIDE, LGPD) | — |
| Conteúdo | `references/*.md` | `references/aws/*.md` em cada skill |
| Mapa de capacidades | — | `providers/aws.md`: componente lógico → serviço AWS → skill do `aws-core` |
| Manifest | schema completo | campo `provider: aws` |
| Gates | terraform, tflint, checkov, validador de diagrama (estrutura) | Access Analyzer, lista de shapes AWS4, Pricing MCP |
| Diagramas | C4 (Mermaid), o fluxo lógico | as 4 visões físicas em draw.io AWS4 |

**Como testar sem construir.** Na Fase 0, escrever **no papel** um `providers/azure.md`. Se nenhuma
skill de método precisar mudar para acomodá-lo, as fronteiras estão certas. Se precisar, corrigir a
fronteira antes da Fase 1.

**Custo estimado da neutralidade:** ~5% a mais de esforço na Fase 1 (disciplina de vocabulário e de
diretórios). Converter depois um plugin 100% AWS custaria reescrever as skills de método.

---

## 4. Análise crítica dos materiais

| Afirmação nos materiais | Veredito | Evidência / correção |
|---|---|---|
| "Não há MCP oficial de networking" | **Refutada [F]** | `aws-network-mcp-server`: 27 ferramentas read-only (VPC, TGW, Cloud WAN, NFW, VPN, flow logs). |
| Terraform MCP da HashiCorp `:0.4.0` | **Desatualizada [F]** | Versão atual 1.3.0, MPL-2.0, stdio e Streamable HTTP. |
| O AWS MCP Server expõe `call_aws` | **Incerta [H]** | A documentação atual lista `aws___run_script`, `aws___get_tasks`, `aws___get_presigned_url`, `aws___retrieve_skill`, `aws___search_documentation`, `aws___read_documentation`, `aws___list_regions` e `aws___get_regional_availability`. |
| Condition keys que distinguem o agente | **Confirmada [F]** | `aws:ViaAWSMCPService`, `aws:CalledViaAWSMCP`. |
| Diagram MCP → skill | **Confirmada [F]** | O pacote foi retirado do PyPI; a skill `aws-architecture-diagram` no `deploy-on-aws` o substitui. |
| CDK/CFN/CCAPI → IaC MCP | **Parcial [F]** | CCAPI deprecated. O IaC MCP **não cobre Terraform**, e por isso não entra no plano (D3). |
| 3 plugins no Toolkit | **Desatualizada [F]** | São 4, incluindo `aws-agents-for-devsecops`. |
| "Cost Analysis MCP" | **Desatualizada** | Hoje são o Pricing MCP e o Billing & Cost Management MCP. |
| CloudWatch MCP = Log-Analyzer-with-MCP | **Incorreta** | São projetos distintos. |
| Knowledge MCP como peça necessária | **Redundante [F]** | O AWS MCP Server busca documentação sem credenciais. |
| MCP Gateway (Bifrost, "−92,8%") | **Rejeitada [R]** | Alegação do fornecedor. O Claude Code já adia schemas [F]. |
| Servidor de estado DynamoDB+S3 (RFC #737) | **Rejeitada neste escopo [R]** | O estado são arquivos versionados (§7). |
| Threat Modeling MCP / threat-composer-ai | **Rebaixada [R]** | Pouco maduro. O threat-composer-ai chama o Bedrock e consome 0,5–1,5M tokens [F]. Uma skill gera o `.tc.json` (schema do Threat Composer). |
| Trivy como scanner principal | **Com ressalva [F]** | Comprometimento de supply chain em mar/2026 (CVE-2026-33634). O Checkov é o primário; o Trivy fica restrito a imagens, fixado por checksum. |
| "Pricing Calculator só via console" (implícito) | **Refutada [F]** | Existe a API oficial `bcm-pricing-calculator` (workload estimates, bill scenarios, rate types com descontos e compromissos) para contas standalone, member e management. |
| Sample Pricing Calculator MCP como caminho oficial | **Com ressalva [F]** | É MIT-0 e gera link `calculator.aws` sem credenciais, mas usa endpoints **não documentados** que podem mudar sem aviso. |
| AWS FinOps Agent | **Confirmada, fora de escopo [F]** | É um agente do console (preview) e não pode ser chamado como ferramenta; o plugin só o recomenda. |

---

## 5. Arquitetura do plugin

```
┌──────────────────────────────────────── Claude Code ────────────────────────────────────────┐
│  solutions-architect ── MÉTODO                                                              │
│   ├── skill `architect` (orquestrador; lê/grava manifest.yml)                               │
│   ├── espinha: requirements → design → diagram → finops → iac → security → observability    │
│   │            → resilience → docs → review                                                 │
│   ├── brownfield: assess (inventário, postura, as-built, drift) · governance · migration    │
│   ├── subagents: architecture-reviewer · security-reviewer · finops-analyst ·               │
│   │              account-inspector                                                          │
│   ├── skills/*/scripts/ (sensores determinísticos, contrato do keel-harness)                │
│   └── hooks/ PreToolUse → DENY em qualquer mutação de nuvem (D13, D14)                      │
│              │ dependencies                                                                 │
│   ├── aws-core@claude-plugins-official ── skills de serviço + AWS MCP Server                │
│   └── (recomendado, D20) drawio@drawio ── Mermaid→.drawio, ELK                              │
│                                                                                             │
│  MCPs: AWS MCP Server (via aws-core) · AWS Pricing MCP · HashiCorp Terraform MCP ·          │
│        [opt-in] Billing & Cost Mgmt · Network                                               │
│  CLIs: terraform · tflint · checkov · aws (Access Analyzer, pricing get-products,          │
│        leitura) · prowler · xmllint · drawio Desktop                                        │
└─────────────────────────────────────────────────────────────────────────────────────────────┘
                    │ grava/lê
                    ▼
     repositório do usuário: <docs.path>/ (padrão architecture/) — §7
```

**Princípios [R]:**

1. **Método aqui, conhecimento de serviço no `aws-core`.** As skills deste plugin não explicam como
   configurar serviços AWS.
2. **Determinístico antes de heurístico.** Lint, policy, scan, custo e validade de diagrama são
   verificados por ferramenta. O LLM julga trade-offs.
3. **CLI antes de MCP** para validadores. MCP entra só onde há API remota com estado.
4. **Somente leitura (D13).** A fronteira real é o IAM; o hook é a segunda camada.
5. **Subagents só existem por isolamento de contexto ou por independência** de revisão.
6. **Os arquivos são o estado.**

---

## 6. Capacidades obrigatórias do arquiteto: como o plano as garante

### 6.1 Diagramas de arquitetura em draw.io (D7, D8)

**Reaproveitamento [F]:** o plugin oficial da jgraph (`/plugin marketplace add jgraph/drawio-mcp`,
`/plugin install drawio@drawio`, Apache-2.0) gera arquivos `.drawio` locais e exporta PNG, SVG e PDF pela
CLI do draw.io Desktop, com o XML embutido. Ele **não tem nenhuma orientação específica de AWS** [F].
Pela **D20** ele é **recomendado, não declarado como dependência**. A H1 mostrou que declará-lo obriga o
usuário a adicionar o marketplace da jgraph antes; sem isso, o plugin carrega com erro. A nossa skill
`diagram` cobre a parte AWS e o export:

| Responsabilidade | Dono |
|---|---|
| Exportar PNG/SVG/PDF com XML embutido (`drawio -x -f <fmt> -e`), sempre em caminho dentro de `$HOME` por causa do snap (H10) | `diagram/scripts/export.sh` |
| Mermaid → `.drawio` (C4) e layout ELK | `drawio@drawio` se instalado; senão C4 fica em `.mmd` |
| Catálogo de shapes AWS4 (`mxgraph.aws4.*`), grupos (AWS Cloud, Region, VPC, AZ, subnet pública/privada, security group), cores e convenções dos *AWS Architecture Icons* | `diagram/references/aws/aws4-shapes.md` |
| As 4 visões obrigatórias e o que cada uma precisa conter | `diagram/references/views.md` |
| Validação | `diagram/scripts/validate-drawio.sh` |
| Ligação diagrama ↔ decisão | cada nó leva `component_id` (atributo do `mxCell`) presente no manifest |

**As 4 visões (D8):**

| Visão | Conteúdo mínimo | Validação específica |
|---|---|---|
| `topology.drawio` | Contas, regiões e serviços; fronteiras de conta | Todo componente do manifest aparece |
| `network.drawio` | VPC com CIDR, AZs, subnets públicas e privadas, NAT, endpoints, TGW, entrada e saída | Contenção subnet ⊂ AZ ⊂ VPC ⊂ Region; CIDRs sem sobreposição |
| `dataflow-security.drawio` | Fluxos numerados com protocolo, trust boundaries e dados classificados | Toda trust boundary existe no threat model (`.tc.json`) |
| `dr.drawio` | Região primária e secundária, replicação, sentido do failover, RTO/RPO anotados | A estratégia bate com o ADR de DR |

**O validador é determinístico e não usa LLM:**

- o XML está bem formado (`xmllint`);
- todo `style` com `shape=mxgraph.aws4.*` está na allowlist;
- nenhum nó está sem rótulo;
- as regras de contenção são respeitadas;
- todo `component_id` existe no manifest.

**Fluxo de uso:** o design é aprovado → as 4 visões são geradas em XML → o validador roda → o
`export.sh` exporta. Se o draw.io Desktop não estiver instalado, o export é pulado com orientação (D19).

**Disputa de disparo (H10):** a skill `drawio` da jgraph se descreve como "Always use when … architecture
diagram". Para não competir com ela, a nossa `diagram` tem descrição restrita a "AWS architecture views
for a solutions-architect workspace" e é invocada pelo `architect`. Um eval de disparo (§15.2) verifica
isso.

**As-built (Fase 2):** a mesma skill gera as visões a partir do `terraform show -json` e do inventário da
conta, e aponta o **drift** em relação ao desenho aprovado, comparando `component_id`s.

### 6.2 Proposta de infraestrutura orientada a FinOps (D5, D6)

**Fonte de preço na v0.1: a Price List API** (somente leitura, gratuita, preço de lista público [F]),
consultada de duas formas (D21):

1. **`price-lookup` determinístico (caminho principal).** Um script lê o `terraform plan -json` e, para
   cada recurso, aplica o mapeamento curado `references/aws/price-map.yaml`:
   `tipo de recurso Terraform + atributos → serviceCode + usagetype (com prefixo de região, ex. SAE1-) +
   filtros extras + regra de faixa`. A consulta é `aws pricing get-products`. O script **falha de forma
   explícita** quando a consulta devolve 0 produtos ou mais de 1 e marca a linha "não estimada"; nunca
   escolhe um produto sozinho.
   - O mapeamento inicial cobre os 15 recursos da H4, **com as 6 armadilhas já corrigidas**: DynamoDB
     on-demand = `WriteRequestUnits`/`ReadRequestUnits`; EKS = `AmazonEKS-Hours:perCluster`; Fargate =
     `Fargate-vCPU-Hours:perCPU` + `Fargate-GB-Hours`; ElastiCache = `NodeUsage:<tipo>` + `cacheEngine`;
     S3 = seleção da faixa pelo volume das premissas; CloudFront = `fromLocation`, e não `regionCode`.
   - Cada linha do relatório traz `serviceCode`, `usagetype` e faixa usados, para ser auditável.
2. **Pricing MCP (caminho de descoberta).** É usado só quando um recurso **não está no mapeamento**: o
   agente descobre o `usagetype` com as ferramentas abaixo, **propõe** a entrada nova para o
   `price-map.yaml` (com revisão humana) e a linha sai marcada "estimada via descoberta".

Ferramentas do Pricing MCP e seu papel:

| Ferramenta | Uso no plugin |
|---|---|
| `get_pricing_service_codes`, `get_pricing_service_attributes`, `get_pricing_attribute_values` | Descobrir o serviço e os filtros corretos (tipo de instância, região, classe de storage) |
| `get_pricing` | Descoberta de preço de recurso fora do mapeamento; comparação exploratória entre regiões no design |
| `analyze_terraform_project` | **Não usado.** Na H4 devolveu só nomes de serviço (`configurations: []`) e não viu o NAT dentro do módulo de VPC |
| `get_bedrock_patterns` | Padrões de custo de workloads com Bedrock (lente GenAI) |
| `generate_cost_report` | **Não usado** no relatório final: o formato do `finops/estimate.md` é nosso, para garantir premissas explícitas **[R]** |
| `get_price_list_urls` | Não usado (baixa datasets inteiros; é custo de contexto sem ganho) |

A própria documentação do Pricing MCP avisa que o agente pode montar filtros errados [F], e a H4 mostrou
isso na prática: 6 de 15 filtros "naturais" erraram sem nenhum erro. Por isso, o caminho principal é
o determinístico.

O FinOps entra **no design**, não depois dele:

1. **Custo como critério de decisão.** Todo ADR com impacto de custo compara as opções pelo custo
   mensal estimado e pelo **custo por unidade de negócio** (por transação, usuário ou GB).
2. **Estimativa da proposta.** O `terraform plan -json` e as premissas de uso dos requisitos (volume,
   horas, crescimento, região) viram linhas `recurso → filtro de preço → preço unitário → quantidade →
   custo mensal`. O `finops-analyst` roda o `price-lookup` (e a descoberta, se preciso) e grava
   `finops/estimate.md` com:
   - total mensal e anual **a preço de lista** (D6);
   - custo por componente e por unidade de negócio;
   - premissas explícitas e uma faixa baixa/esperada/alta;
   - linhas "não estimadas" para recursos sem preço identificável, **sem valor inventado**.

   **[F] (H4):** os 15 recursos mais comuns (EC2, EBS, RDS, Aurora, S3, ALB, NAT GW, Lambda, API GW,
   DynamoDB, CloudFront, EKS, ECS/Fargate, ElastiCache, CloudWatch Logs) são precificáveis em `sa-east-1`
   com filtros corretos.
3. **Conferência cruzada: removida (D23).** O OpenInfraQuote precificou a US$ 0 recursos centrais (RDS
   `db.m7g`, ElastiCache `cache.r7g`, ALB, NAT). A proteção contra filtro errado passou a ser a regra do
   próprio lookup: 0 ou vários produtos com preços diferentes tornam a linha "não estimada".
4. **Delta por mudança.** O `price_lookup.py --side before` precifica o estado atual do mesmo plan, e o
   `estimate.py` mostra o delta. Isso é gate: um delta acima do orçamento declarado nos requisitos exige ADR.
5. **Alavancas FinOps**, incluídas na proposta como recomendações **qualitativas**, sem valor calculado
   de desconto:
   - Savings Plans e RIs, Graviton, tiering de storage (S3 Intelligent-Tiering), Spot onde os NFRs
     permitirem, e dimensionamento por NFR, não por pico chutado;
   - **tags de alocação obrigatórias** (validadas pelo checkov/tflint no gate);
   - AWS Budgets e Cost Anomaly Detection **gerados como IaC**, porque o plugin não os aplica (D13).
6. **Custo real (Fase 2, brownfield):** o Billing & Cost Management MCP (opt-in, read-only) compara o
   real com o estimado. O FinOps Agent da AWS é recomendado para investigação contínua.

**O que a v0.1 não faz, e por quê (backlog):**

- **Estimativa no AWS Pricing Calculator** (API `bcm-pricing-calculator`): criaria um recurso na conta, o
  que exigiria uma exceção à regra de somente leitura. A exceção deixa de existir.
- **Cenário com descontos e compromissos** (`AFTER_DISCOUNTS_AND_COMMITMENTS`) e modelagem de compras de
  Savings Plans (bill scenarios): dependem do Calculator.
- **Link público `calculator.aws`** (sample MCP): usa uma API não documentada e expõe a arquitetura a
  quem tiver a URL.

Quando o backlog for retomado, a estimativa do Pricing MCP já produz as linhas `serviceCode`, `usageType`
e `operation` que a API do Calculator exige. Nada da v0.1 se perde.

### 6.3 Documentar a arquitetura construída (D9, D12)

- Tudo em **markdown**, no caminho que o usuário escolher (`docs.path`, padrão `architecture/`), no idioma
  de `language` (padrão pt-BR).
- `docs` gera um **SAD arc42-lite** que **referencia** os artefatos em vez de copiá-los: contexto,
  restrições, estratégia de solução, visões (os 4 diagramas + C4 em Mermaid), decisões, qualidade,
  riscos e glossário.
- **Sumário executivo** de 1 página: problema, solução, custo (preço de lista e custo por unidade), riscos principais e
  próximos passos.
- **Registro de riscos** (`risks.md`), com probabilidade, impacto, mitigação e responsável.
- **Roadmap e faseamento**, quando a solução é entregue em ondas.
- **As-built (Fase 2):** um documento gerado a partir do estado Terraform e do inventário da conta, com
  uma seção de **drift** entre o desenhado e o construído.
- **Runbooks** derivados das seções de observabilidade e DR.

### 6.4 Avaliação de escalabilidade, confiabilidade, resiliência e demais qualidades (D10)

A avaliação é **qualitativa**, na forma de checklist WA:

- `review` delega a revisão por pilar ao `aws-well-architected-review` do `aws-core`, sem duplicar. Ela
  cobre excelência operacional, segurança, confiabilidade, eficiência de performance (onde entra a
  escalabilidade), otimização de custo e sustentabilidade.
- **Lentes** são aplicadas quando o workload se encaixa (Serverless, SaaS, GenAI, Data Analytics,
  Container Build).
- O plugin acrescenta **checagens de método**:
  - todo NFR de escalabilidade, disponibilidade ou latência está coberto por um ADR;
  - a estratégia de DR bate com o RTO/RPO;
  - todo componente stateful tem backup e replicação decididos;
  - as dependências externas têm timeout, retry e circuit breaker explícitos no design.
- `resilience` produz a análise **qualitativa** de modos de falha (AZ, região, dependência) e mapeia
  RTO/RPO para a estratégia (backup & restore, pilot light, warm standby, multi-site).
- O `architecture-reviewer` roda em contexto limpo e não pode escrever além do relatório.
- **Backlog (fora da v0.1 por D10):** disponibilidade composta calculada pelos SLAs, capacidade versus
  Service Quotas, FMEA numérica e geração de planos de carga e FIS.

### 6.5 Matriz de responsabilidades do arquiteto de soluções

| Responsabilidade | Skill | Artefato | Fase |
|---|---|---|---|
| Levantar requisitos e NFRs mensuráveis, restrições, stakeholders | `requirements` | `requirements.md` | 1 |
| Avaliar alternativas e registrar trade-offs | `design` | `decisions/*.md` (MADR) | 1 |
| Selecionar serviços e verificar disponibilidade regional | `design` → `aws-core` | ADRs | 1 |
| Diagramas draw.io (4 visões) + C4 | `diagram` | `diagrams/*.drawio`, `*.mmd` | 1 |
| Proposta FinOps + estimativa a preço de lista (Pricing MCP) | `finops` | `finops/estimate.md` | 1 |
| Business case e TCO | `finops` | seção do `estimate.md` | 1 |
| IaC Terraform validado | `iac` | código + `reports/iac-gate.json` | 1 |
| Documentação (SAD, sumário executivo, riscos, roadmap) | `docs` | `README.md`, `risks.md` | 1 |
| Revisão WA qualitativa + lentes | `review` | `reviews/*.md` | 1 |
| Threat model, IAM least-privilege, LGPD, CIS | `security` | `.tc.json`, `security/*.md` | 2 |
| Observabilidade: SLO/SLI e alarmes em IaC | `observability` | `operations/slo.md` | 2 |
| Estratégia de DR e resiliência | `resilience` | `operations/dr-plan.md` | 2 |
| Avaliação de ambiente existente, as-built e drift | `assess` + `diagram` + `docs` | `assessment/*` | 2 |
| Governança multi-conta | `governance` | `governance/*.md` | 3 |
| Migração (7Rs, ondas) | `migration` | `migration/*.md` | 3 |
| Comunicação com stakeholders | `docs` (sumário executivo) | `executive-summary.md` | 1 |

---

## 7. Contrato de artefatos (o estado compartilhado)

```
<docs.path>/                          # padrão: architecture/
├── manifest.yml                      # schema: 1 — índice, estado e rastreabilidade
├── requirements.md
├── decisions/0001-*.md               # MADR; campo "supersedes"
├── diagrams/{topology,network,dataflow-security,dr}.drawio · {context,container}.mmd · exports/
├── finops/estimate.md
├── security/{threat-model.tc.json, iam.md, lgpd.md}
├── operations/{slo.md, dr-plan.md, runbooks/}
├── assessment/{inventory.md, posture.md, as-built.md}
├── reviews/YYYY-MM-DD-wa.md
├── risks.md · executive-summary.md · README.md
└── reports/*.json                    # saídas dos gates (gitignored)
```

O `manifest.yml` guarda:

- `provider`, `language`, `docs.path`, `region(s)`;
- a etapa atual e o resultado de cada gate;
- os componentes (`component_id` → serviço → ADR → recurso Terraform → nós de diagrama);
- o mapa `NFR → ADR → IaC → evidência`;
- as supressões justificadas e as premissas de custo;
- as versões das dependências (`aws-core`, `drawio`, MCPs, CLIs).

Esse schema é o **contrato público** do plugin e é validado por `validate-manifest.sh`.

---

## 8. Skills (14), agrupadas por domínio

Orçamento de tokens [F/R]: as descrições ficam sempre no contexto (máximo de 1.536 caracteres); meta de
≤ 400 caracteres por descrição e `SKILL.md` ≤ 250 linhas; os domínios ficam em `references/` e carregam
sob demanda.

### 8.1 Espinha (greenfield) — Fase 1

| Skill | Problema que resolve | Quando usar | Dependências | Integração |
|---|---|---|---|---|
| **`architect`** | Etapas puladas; trabalho que não se retoma | Pedido amplo, ou retomada | manifest | Decide a próxima etapa, invoca a skill correspondente e aplica o gate (§10). Não produz conteúdo de domínio. |
| **`requirements`** | NFR vago; arquitetura escolhida antes dos requisitos | Primeira etapa | — | IDs `REQ-`/`NFR-`/`CON-`, quality attribute scenarios, RTO/RPO, SLO-alvo, orçamento, residência de dados (LGPD). Pergunta só o que falta. |
| **`design`** | Escolha de serviço sem alternativas | Toda decisão estrutural | `aws-core`, `aws___search_documentation`, `aws___get_regional_availability`, Pricing MCP | ≥2 opções por decisão, critérios ligados a NFRs **e custo por unidade** (§6.2.1), MADR. `references/` neutras + `references/aws/{networking,compute,storage,databases,containers,serverless,integration,data,ai}.md` apontando para as skills do `aws-core`. |
| **`diagram`** | Diagramas manuais e desatualizados | Após o design; a cada ADR que muda a topologia | `xmllint`, draw.io Desktop (export); `drawio@drawio` opcional (D20) | §6.1 |
| **`finops`** | Custo descoberto depois do deploy | Durante o design (comparação), após o plan (estimativa), a cada mudança (delta) | `aws pricing` (via `price-lookup`), Pricing MCP (descoberta) | §6.2 |
| **`iac`** | IaC gerado por agente sem validação | Após o diagrama | Terraform MCP, `terraform`, `tflint`, `checkov` | Terraform com `terraform-aws-modules` fixados (D18); gate `iac-gate.sh`: `fmt -check`, `validate`, `tflint` (ruleset AWS), `checkov`. Um **`terraform plan` somente leitura** (§9) alimenta `finops`. Supressões exigem justificativa no manifest. `references/pipelines.md` cobre CI/CD com OIDC, sem chaves de longa duração. |
| **`docs`** | Documentação dispersa | Consolidação | — | §6.3 |
| **`review`** | Viés de quem fez revisando o próprio trabalho | Fim do fluxo | `aws-core` (`aws-well-architected-review`), `architecture-reviewer` | §6.4 |

### 8.2 Qualidades transversais — Fase 2

| Skill | Problema | Quando | Dependências | Integração |
|---|---|---|---|---|
| **`security`** | Threat model ausente; IAM com curinga; LGPD ignorada | Após o design e após o IaC | `aws accessanalyzer` (`validate-policy`, `check-no-new-access`, `check-no-public-access`), checkov, `security-reviewer` | STRIDE por trust boundary → `.tc.json`. Toda política IAM do Terraform passa pelo Access Analyzer. **LGPD** (`references/lgpd.md`): inventário de dados pessoais, base legal por fluxo, residência e transferência internacional (região), retenção e eliminação, suporte aos direitos do titular, registro de operações. É um checklist: LGPD não é verificável por ferramenta. **CIS AWS Foundations**: checkov no IaC e Prowler (framework CIS, **[H]** id exato) na conta. |
| **`observability`** | Monitoração posterior e desconectada do SLO | Após o IaC | `aws-core` (`observability`) | SLI/SLO derivados dos NFRs; alarmes de burn-rate, dashboards e logs e traces **como Terraform** (o plugin não aplica). |
| **`resilience`** | DR incoerente com o RTO/RPO | Com RTO/RPO declarados | — | §6.4; alimenta `dr.drawio` e `dr-plan.md`. |

### 8.3 Brownfield e organização

| Skill | Fase | Problema | Dependências | Integração |
|---|---|---|---|---|
| **`assess`** | 2 | "O que existe, quanto custa e quais são os riscos?" | `account-inspector`, `prowler`, opt-in Billing MCP e Network MCP | Inventário read-only via `aws___run_script`, postura (Prowler OCSF resumido), custo real e topologia de rede → `assessment/`. Alimenta as-built (§6.1, §6.3) e `review`. |
| **`governance`** | 3 | Multi-conta improvisado | AWS MCP Server (leitura de Organizations e Control Tower) | OUs, SCP/RCP, IAM Identity Center, tags e conformance packs como Terraform, validados no Access Analyzer. |
| **`migration`** | 3 | Migração sem portfólio | `assess` | 7Rs, ondas e TCO; aponta AWS Transform, MGN e DMS sem reimplementá-los. |

**Fora de propósito [R]:** uma skill por serviço (redundante com o `aws-core`) e skills de persona.

---

## 9. Segurança operacional: somente leitura, sem exceções (D13, D14)

1. **Política IAM de referência (README).** Um papel dedicado ao agente, com:
   - `SecurityAudit` + `ViewOnlyAccess`, **em vez de `ReadOnlyAccess`**. [R] O `ReadOnlyAccess` permite
     ler o *conteúdo* de dados, como `s3:GetObject` e `dynamodb:Scan`, o que é desnecessário para
     arquitetura e arriscado sob a LGPD;
   - `pricing:*` (leitura);
   - `access-analyzer:ValidatePolicy`, `CheckNoNewAccess` e `CheckNoPublicAccess`;
   - `ce:Get*` (Fase 2);
   - **nenhuma ação de escrita.** O Access Analyzer só analisa políticas, e o Pricing MCP só lê a Price
     List API.

   **[H]** Validar na Fase 0 o conjunto mínimo exato de ações.
2. **Hook `PreToolUse` que bloqueia (deny) e não pergunta.** Cobre:
   - `terraform apply|destroy|import|state (rm|mv|push)`;
   - `aws …` com verbos mutantes (`create|delete|put|update|terminate|modify|attach|detach|run|start|stop`),
     **sem exceções**;
   - chamadas `aws___run_script` cujo código contenha chamadas mutantes do boto3.

   A mensagem de bloqueio explica o motivo e como o humano executa por fora. Esta é a única exceção à
   regra "informa, não bloqueia" herdada do keel-harness, e a justificativa é que ação na nuvem é
   irreversível e custa dinheiro. **[H]** O matcher de hook precisa enxergar os argumentos de ferramenta
   MCP.
3. **`terraform plan` sem escrita.** Por padrão, o `plan` adquire lock no backend, o que é uma escrita no
   DynamoDB ou S3. O plugin roda `plan -lock=false -refresh=true` e documenta a permissão de leitura de
   state necessária.
4. **Supply chain.** Nenhum `@latest`: MCPs e módulos Terraform com versões fixadas; CLIs verificadas por
   checksum; Trivy restrito (§4).
5. **Dados.** Relatórios de postura e custo ficam em `reports/`, gitignored. Nada é enviado a terceiros.

---

## 10. Fluxos e gates

### 10.1 Greenfield

| # | Etapa | Gate de saída |
|---|---|---|
| 1 | requirements | Todo NFR tem medida, ou "a definir" com responsável; RTO/RPO, região, orçamento e classificação de dados declarados |
| 2 | design | ≥2 opções por decisão estrutural; critérios ligados a NFRs e ao custo por unidade; todos os serviços disponíveis na região |
| 3 | diagram | 4 visões com validador verde; todo `component_id` presente no manifest |
| 4 | finops (comparação) | Premissas explícitas; custo de lista dentro do orçamento, ou desvio em ADR |
| 5 | iac | Gate verde: 0 erros de `validate`/`tflint`; **0 falhas do checkov não suprimidas** (o checkov OSS não informa severidade); tags de alocação presentes |
| 6 | finops (estimativa) | `estimate.md` com filtro por linha; linhas "não estimadas" listadas; delta (`--side before`) registrado |
| 7 | docs | SAD, sumário executivo e riscos gerados; todos os links resolvem |
| 8 | review | `architecture-reviewer` sem bloqueios; manifest 100% rastreável |

Na Fase 2, `security`, `observability` e `resilience` entram entre as etapas 5 e 7.

O orquestrador aceita **entrar em qualquer etapa**; os gates anteriores que faltarem viram avisos.

### 10.2 Brownfield (Fase 2)

`assess` → as-built (diagramas + documento + drift) → `review` → plano de remediação → ADRs → `iac`. O
plugin gera o IaC; **quem aplica é o humano ou o pipeline** (D13).

### 10.3 Mudança incremental

ADR que supersede o anterior → `diagram` só nas visões afetadas → `iac` → gate → delta do `price_lookup.py`
→ `review` restrita aos pilares afetados.

### 10.4 Migração (Fase 3)

`assess` → `migration` → `design` por onda → fluxo greenfield a partir da etapa 2.

---

## 11. MCPs, CLIs e APIs

### 11.1 MCP servers

| Server | Status | Papel | Credenciais | Como entra |
|---|---|---|---|---|
| AWS MCP Server (gerenciado) | Obrigatório | Docs, disponibilidade regional, skills oficiais, leitura de conta | Docs: nenhuma. API: IAM | Via `aws-core`; não é redeclarado aqui |
| AWS Pricing MCP (`awslabs.aws-pricing-mcp-server`) | Incluído | Preço de lista na comparação de opções; mapeamento de `usageType`. **Usa só a Price List API: não cria estimativas no Pricing Calculator [F]** | IAM (`pricing:*`, chamadas gratuitas) | `.mcp.json`, versão fixada (a doc oficial usa `@latest`; aqui é proibido). **[H]** remover se o `aws-core` já o incluir |
| HashiCorp Terraform MCP 1.3.x | Incluído (D3) | Docs de provider e módulos do registry público | Nenhuma | `.mcp.json`, binário ou Docker fixado |
| Billing & Cost Mgmt MCP | Opt-in (Fase 2) | Custo real, anomalias | IAM read-only | README |
| AWS Network MCP | Opt-in (Fase 2) | Diagnóstico de rede na conta | IAM read-only | README |

**Rejeitados [R]:** Knowledge MCP e API MCP (redundantes com o MCP gerenciado); IaC MCP (não cobre
Terraform); draw.io MCP (o diagrama é arquivo; o plugin `drawio@drawio` é opcional, D20); WA Security MCP, Threat Modeling MCP e
Prowler MCP (o CLI basta); gateways.

### 11.2 CLIs (contrato de sensor do keel-harness; ausente = `skipped` com orientação, D19)

| CLI | Licença | Papel | Obrigatório |
|---|---|---|---|
| `terraform` | BUSL-1.1 | `fmt`, `validate`, `plan -json` read-only | Sim |
| `tflint` + ruleset AWS | MPL-2.0 | Lint | Sim |
| `checkov` | Apache-2.0 | Segurança, CIS e tags no IaC | Sim |
| `aws` CLI v2 | Apache-2.0 | `pricing get-products` (`price-lookup`), Access Analyzer (somente leitura/análise) | Sim |
| `xmllint` | MIT | Validador de diagrama | Sim |
| draw.io Desktop | Apache-2.0 | Export PNG/SVG/PDF (`export.sh`; via snap, somente caminhos em `$HOME`) | Não |
| `uv`/`uvx` | Apache-2.0/MIT | Roda o MCP do `aws-core` e o Pricing MCP (H3, §14.1) | Sim |
| `prowler` | Apache-2.0 | Postura e CIS em conta real | Fase 2 |
| `trivy` | Apache-2.0 | Imagens, fixado por checksum | Não |

**Nota [R] de licença:** o `terraform` está sob BUSL-1.1. O plugin só *invoca* o binário, o que é
permitido. O **OpenTofu** (MPL-2.0) deve ser aceito como binário alternativo pelo sensor, sem nenhuma
mudança nas skills.

---

## 12. Subagents (4)

| Agent | Critério | Responsabilidade | Ferramentas | Modelo |
|---|---|---|---|---|
| `architecture-reviewer` | Independência | Revisão adversarial de requisitos, ADRs, diagramas, IaC e custo contra NFRs e WA | Somente leitura + docs do AWS MCP | O mais capaz |
| `security-reviewer` | Isolamento + independência | Threat model, triagem do checkov e do Access Analyzer, checklist LGPD | Read, Grep, scripts de `security` | O mais capaz |
| `finops-analyst` | Isolamento | `price-lookup` sobre o plan, descoberta via Pricing MCP só fora do mapeamento → tabela condensada | scripts de `finops`, Pricing MCP | Mais barato |
| `account-inspector` | Isolamento | Descoberta read-only; devolve um inventário resumido | AWS MCP Server, Prowler, Network MCP | Mais barato |

Todos rodam com `permissionMode` sem escrita, exceto no destino do relatório.

---

## 13. Estrutura do repositório

```
plugins/solutions-architect/
├── .claude-plugin/plugin.json      # Apache-2.0; dependencies: aws-core (^1.1.0, claude-plugins-official)
├── .mcp.json                       # aws-pricing, terraform (versões fixadas)
├── hooks/hooks.json                # PreToolUse deny em qualquer mutação (D13)
├── agents/{architecture-reviewer,security-reviewer,finops-analyst,account-inspector}.md
├── providers/aws.md                # mapa de capacidades + tabela de delegação ao aws-core (§3, H9)
├── providers/aws/scripts/          # price-lookup.sh, validate-policies.sh (chamam APIs AWS; H9)
├── skills/
│   ├── architect/     SKILL.md · references/{workflow.md, manifest-schema.md} · scripts/validate-manifest.sh
│   ├── requirements/  SKILL.md · references/{nfr-catalog.md, qa-scenarios.md} · assets/requirements.md
│   ├── design/        SKILL.md · references/{trade-offs.md, aws/*.md (9 domínios)} · assets/madr.md
│   ├── diagram/       SKILL.md · references/{views.md (neutro), c4-mermaid.md, aws/aws4-shapes.md}
│   │                  · scripts/{validate-drawio.sh, export.sh} · assets/aws4-allowlist.txt
│   ├── finops/        SKILL.md · references/{levers.md, unit-economics.md, aws/price-map.yaml,
│   │                  aws/price-discovery.md} · scripts/estimate.py (D23: sem oiq)
│   ├── iac/           SKILL.md · references/{terraform.md, modules.md, pipelines.md}
│   │                  · scripts/{iac-gate.sh, sensors/*.sh}
│   ├── security/      SKILL.md · references/{stride.md, lgpd.md, aws/{iam.md, cis.md}}
│   │                  · assets/threat-model.tc.json
│   ├── observability/ SKILL.md · references/slo.md
│   ├── resilience/    SKILL.md · references/dr-strategies.md
│   ├── assess/        SKILL.md · scripts/{inventory.py, prowler-summary.sh}
│   ├── governance/    SKILL.md · references/aws/{landing-zone.md, scp-rcp.md, tagging.md}
│   ├── migration/     SKILL.md · references/{7rs.md, waves.md}
│   ├── review/        SKILL.md · references/{lenses.md, method-checks.md}
│   └── docs/          SKILL.md · assets/{sad-arc42-lite.md, executive-summary.md, risks.md}
├── evals/<caso>/{prompt.md, case.yaml, scaffold.sh, graders/*.md}
└── README.md                       # instalação, política IAM, MCPs opt-in

tests/solutions_architect_*_test.sh # na raiz, no padrão do keel-harness
.claude-plugin/marketplace.json     # + entrada; allowCrossMarketplaceDependenciesOn
                                    #   [claude-plugins-official]
```

O código e o conteúdo do plugin ficam em inglês, pela convenção do repositório. Os artefatos gerados
saem no idioma de `language` (D12).

---

## 14. Fase 0: resultados (executada em 2026-09-22)

Ambiente: Claude Code 2.1.280, `aws-core` 1.1.0 e `drawio` 1.1.0 instalados em escopo local, AWS CLI
2.22.35, conta `567944156995`. **Só chamadas de leitura ou de análise.** O AWS MCP Server rodou com as
credenciais neutralizadas.

| # | Hipótese | Resultado | Evidência | Consequência no plano |
|---|---|---|---|---|
| H1 | Dependências entre marketplaces | **Confirmada, com atrito** | Um plugin descartável com `dependencies` para `aws-core` (`^1.1.0`, `claude-plugins-official`) e `drawio` (`drawio`) + `allowCrossMarketplaceDependenciesOn` instalou e **auto-instalou o `drawio`**. Sem o marketplace `drawio` configurado, a instalação diz "ok", mas o plugin fica com o erro `Dependency "drawio@drawio" is not installed … check that its marketplace is added`. | O `aws-core` fica como dependência declarada, porque o marketplace oficial já vem configurado. Para o `drawio`, ver a decisão **D20** |
| H2 | Nomes das ferramentas do AWS MCP Server | **Confirmada; `call_aws` não existe** | `tools/list` via `mcp-proxy-for-aws-cli` 1.7.0: `aws___search_documentation`, `aws___read_documentation`, `aws___retrieve_skill`, `aws___list_regions`, `aws___get_regional_availability`, `aws___run_script` (usa `call_boto3` na sandbox), `aws___get_tasks`, `aws___get_presigned_url` | As skills citam só esses 8 nomes |
| H3 | O `aws-core` já traz o Pricing MCP? | **Não traz** | O `.mcp.json` do `aws-core` declara só o `aws-mcp`, com `--skip-auth` (somente documentação, sem credenciais) | O Pricing MCP continua no nosso `.mcp.json` |
| H4 | Cobertura de preço dos 15 recursos (`sa-east-1`) | **15/15 precificáveis, mas 6/15 filtros "naturais" retornaram o produto ou a faixa errada sem nenhum erro** | Erros: DynamoDB `DDB-WriteUnits` → WCU provisionado em vez de on-demand; EKS → Auto Mode em vez de `AmazonEKS-Hours:perCluster`; Fargate → Managed Instances; ElastiCache → SyncDurability em vez de `NodeUsage`; S3 → faixa "next 450 TB" em vez da primeira; CloudFront → não usa `regionCode` (usa `fromLocation`). O `analyze_terraform_project` só devolve nomes de serviço, com `configurations: []`, e **não vê o NAT dentro do módulo de VPC** | O preço passa a ser um **lookup determinístico** a partir de um mapeamento curado (ver **D21**). O `analyze_terraform_project` sai do fluxo; as quantidades vêm do `terraform plan -json` |
| H5 | O hook enxerga os argumentos de ferramentas MCP | **Confirmada** | O hook oficial `secret-safety.py` do `aws-core` usa o matcher `mcp__plugin_.*aws-mcp.*`, lê `tool_input` e inspeciona o código do `run_script` e o `cli_command`, retornando `deny` | Nosso hook segue o mesmo padrão. Os dois hooks convivem: o do `aws-core` bloqueia leitura de segredos, o nosso bloqueia mutações |
| H6 | Colisão do nome `solutions-architect` | **Sem colisão técnica; há risco de confusão** | Os IDs têm namespace por marketplace (`solutions-architect@aether-labs`). Existem nomes parecidos: `solutions-architect-skills` (shadowX4fox) e várias skills `solution-architect` | Manter o nome; a descrição diferencia ("AWS, Terraform, FinOps, draw.io") |
| H7 | Política IAM mínima | **Parcial** | `access-analyzer validate-policy` na política de referência: **0 findings**. O rascunho com `Deny` + `NotAction: "*:Describe*"` gerou 3 **ERRORs** (`INVALID_SERVICE_IN_ACTION`: IAM não aceita curinga no prefixo de serviço), e esse `Deny` foi removido. `SecurityAudit` (990 ações) e `ViewOnlyAccess` (373) **não contêm nenhuma ação de leitura de dados** (`s3:GetObject`, `dynamodb:Scan/Query/GetItem`, `GetSecretValue`, `ssm:GetParameter`). **Não foi possível medir o mínimo efetivo:** a conta está configurada com **access keys do usuário root**, que ignora políticas IAM | §9.1 corrigido. O mínimo efetivo fica para a Fase 1, com um papel dedicado |
| H8 | CIS no Prowler e no checkov | **Confirmada** | Prowler 5.43.0: `cis_1.4_aws` … `cis_7.0_aws`, `aws_well_architected_framework_{security,reliability}_pillar_aws`; **nenhum framework LGPD**. Checkov 3.3.19 no fixture Terraform: 18 aprovados / 30 reprovados (criptografia RDS, deletion protection, logs de ALB etc.). O **`CKV_TF_1`** exige módulo por hash de commit, o que conflita com a D18 | Fixar `cis_7.0_aws`; LGPD continua como checklist; ver **D22** |
| H9 | Fronteira agnóstica (exercício com Azure no papel) | **Confirmada, com 3 ajustes** | (1) `diagram/references/views.md` usava vocabulário AWS ("VPC"): passa a "rede virtual / zona / sub-rede", com o nome AWS só em `references/aws/`. (2) Scripts que chamam API de provedor (`price-lookup`, `validate-policies`) vão para `providers/aws/scripts/`. (3) `design` e `review` delegam pelo mapa `providers/aws.md` (`delegate: aws-core:aws-well-architected-review`) em vez de citar o `aws-core` no `SKILL.md` | Estrutura do §13 ajustada |
| H10 | O `drawio@drawio` serve para exportar | **Confirmada, com restrições** | A skill `drawio` (442 linhas, ~130 tokens fixos e ~9,9k quando invocada) documenta `drawio -x -f png|svg|pdf -e` (XML embutido), ELK `--layout` e Mermaid → `.drawio`. **Não tem nenhuma orientação de shapes AWS.** Um teste real exportou PNG e SVG de um XML AWS4 (VPC, ALB, RDS) corretamente. **O draw.io via snap só lê e grava dentro de `$HOME`**: arquivos em `/tmp` dão "input file not found". A descrição da skill ("Always use when … architecture diagram") **compete no disparo** com a nossa `diagram` | A skill AWS4 continua necessária. O sensor de export verifica se o caminho está em `$HOME`. A nossa `diagram` só é invocada pelo `architect` ou por pedido explícito, e chama o `drawio` para o export |

### 14.1 Achados que não eram hipóteses

- **`aws-core` 1.1.0 tem 25 skills, e não 14.** Entre as novas estão `aws-networking`, `aws-iam`,
  `aws-security`, `aws-compute`, `aws-deployment`, `aws-messaging-and-streaming`, `aws-auth` e
  `launch-with-aws`. As `references/aws/*.md` da skill `design` passam a delegar a elas.
- **Custo fixo do `aws-core`: ~7.056 tokens por sessão**, medido com `claude plugin details`. Somado ao
  nosso orçamento (< 2k) e ao do `drawio` (~130), o custo fixo total fica perto de 9k tokens. Deve constar
  no README.
- **`uv`/`uvx` é pré-requisito** tanto do MCP do `aws-core` quanto do Pricing MCP, e não estava
  instalado nesta máquina. Entra no checklist de ferramentas (D19).
- **O `aws-core` também usa `@latest`** no `.mcp.json` (`mcp-proxy-for-aws-cli@latest`). Como não
  controlamos isso, o check de frescor (§15.3) registra a versão resolvida.
- **Credenciais root configuradas na máquina de desenvolvimento.** Isso está fora do escopo do plugin,
  mas é um risco alto: a recomendação é remover as access keys de root e usar IAM Identity Center ou um
  papel dedicado.

## 15. Qualidade, validação e testes

### 15.1 Estrutural (`make check`, a cada commit)

- `claude plugin validate --strict`.
- Frontmatter válido; descrição ≤ 400 caracteres; `SKILL.md` ≤ 250 linhas.
- Nenhum caminho sai do plugin; nenhum `@latest`.
- `validate-manifest.sh` e `validate-drawio.sh` testados com fixtures **válidas e inválidas**: sobreposição
  de CIDR, subnet fora de AZ, shape fora da allowlist, `component_id` órfão.
- O gate de IaC precisa **falhar** em fixtures com defeito (SG `0.0.0.0/0:22`, S3 público, falta de tag).
- O `price-lookup` é testado contra as **6 armadilhas da H4**: cada fixture precisa resolver para o
  `usagetype` correto, e uma consulta que retorna 0 ou mais de 1 produto precisa virar "não estimada".
  Rodar exige `pricing:GetProducts`, então esse teste é opcional em CI sem credenciais.
- `CKV_TF_1` suprimido **somente** com a justificativa padrão da D22; qualquer outra supressão sem
  justificativa reprova o gate.
- O hook precisa **negar** `terraform apply`, `aws ec2 run-instances` e
  `aws bcm-pricing-calculator create-workload-estimate` (não há exceções), e **permitir**
  `aws accessanalyzer validate-policy` e `terraform plan -lock=false`.
- Scripts passam no `shellcheck`.

### 15.2 Evals (`claude plugin eval`, com baseline sem plugin)

| Caso | Graders determinísticos | Grader LLM |
|---|---|---|
| `greenfield-web-3tier` | ≥5 NFRs mensuráveis; ≥3 ADRs com ≥2 opções; 4 `.drawio` válidos; gate Terraform verde | Os trade-offs seguem os NFRs? |
| `drawio-four-views` | `validate-drawio.sh` verde nas 4 visões; contenção de rede correta | Legibilidade e completude |
| `finops-estimate` | `price-lookup` executado; toda linha com `serviceCode`, `usagetype` e faixa; premissas presentes; nenhum valor em linha "não estimada"; total idêntico ao da fixture gravada | Custo por unidade coerente |
| `diagram-trigger` | Pedido de visões AWS dentro do fluxo dispara a nossa `diagram`, e não a `drawio` da jgraph | — |
| `read-only-enforced` | Pedido "aplique a infra" → hook nega; nenhuma chamada mutante (`tool_order`) | Explica ao usuário como aplicar por fora |
| `iam-wildcard-trap` | Access Analyzer chamado; política corrigida | — |
| `lgpd-residency` | Dados pessoais + região fora do Brasil → requisito de transferência internacional registrado em ADR | Qualidade do checklist |
| `brownfield-as-built` (Fase 2; LocalStack ou conta mock) | Inventário + as-built + seção de drift | Priorização |
| `wa-review-qualitative` | Delegou a `aws-well-architected-review`; checagens de método presentes | Cobertura dos pilares |
| `should-not-trigger` | Nenhuma skill dispara em uma tarefa de código genérica | — |

- **Critério de release:** delta positivo sobre o baseline em ≥8 de 10 casos, e **zero regressão** em
  `read-only-enforced`, `iam-wildcard-trap` e `finops-estimate`.
- **Anti-alucinação:** todo serviço citado em ADR precisa aparecer numa chamada de documentação ou de
  disponibilidade regional na transcrição, e todo valor monetário precisa ter origem numa chamada de
  `price_lookup.py` (ou do Pricing MCP, na descoberta).

**Resultados (Fase 1, 2026-09-22):** smoke run (`--case '*trigger' --runs 1 --ablation none`) em
`/tmp/sa-eval-smoke`; suíte completa (Task 15 Step 5, com baseline sem plugin) adiada pelo owner para
uma máquina ou CI sem a restrição de sandbox abaixo.

| Caso | Score (com plugin) | Score (sem plugin) | Delta | Custo |
|---|---|---|---|---|
| `diagram-trigger` | 1.00 | — | — | $0.55 |
| `should-not-trigger` | 1.00 | — | — | $0.09 |
| `drawio-four-views` | deferred — Bash bloqueado no sandbox de eval (apparmor nested userns) | — | — | — |
| `finops-estimate` | deferred — Bash bloqueado no sandbox de eval (apparmor nested userns) | — | — | — |
| `greenfield-web-3tier` | deferred — Bash bloqueado no sandbox de eval (apparmor nested userns) | — | — | — |
| `read-only-enforced` | deferred — Bash bloqueado no sandbox de eval (apparmor nested userns) | — | — | — |
| `wa-review-qualitative` | deferred — Bash bloqueado no sandbox de eval (apparmor nested userns) | — | — | — |

Causa: `kernel.apparmor_restrict_unprivileged_userns = 1` nesta máquina; o owner optou por não alterar o
sysctl (Task 15 Step 1). Os dois casos que não usam Bash (`diagram-trigger`, `should-not-trigger`)
confirmam o disparo/não-disparo da skill `diagram` independente dessa limitação.

### 15.3 Frescor e custo

- **Check trimestral** (em `tests/`):
  - nomes de skill do `aws-core` e do `drawio` ainda existem;
  - versões fixadas de MCPs e de `terraform-aws-modules` têm release mais novo;
  - nomes das ferramentas `aws___*` batem com a documentação;
- **Custo:** `/skill-doctor` mede as descrições (meta < 2k tokens para as 14 skills), e o custo de um
  fluxo greenfield completo é registrado por release.

### 15.4 Roadmap

| Fase | Entrega | Critério de saída |
|---|---|---|
| 0 | Spikes H1–H10 | Todas as [H] viram [F] ou uma decisão alternativa registrada |
| 1 | `architect`, `requirements`, `design`, `diagram`, `finops`, `iac`, `docs`, `review`, `architecture-reviewer`, `finops-analyst`, hook, manifest; evals `greenfield-web-3tier`, `drawio-four-views`, `finops-estimate`, `read-only-enforced`, `wa-review-qualitative`, `should-not-trigger`, `diagram-trigger` | Delta positivo em `greenfield-web-3tier`, `drawio-four-views` e `finops-estimate`; `read-only-enforced` verde |
| 2 | `security` (LGPD, CIS, Access Analyzer), `observability`, `resilience`, `assess` + as-built/drift, `security-reviewer`, `account-inspector`, MCPs opt-in | Evals `iam-wildcard-trap`, `lgpd-residency` e `brownfield-as-built` |
| 3 | `governance`, `migration` | Evals próprios |
| Backlog | Pricing Calculator (API oficial, cenário com descontos, bill scenarios, link público — §6.2), avaliação quantitativa (D10), CDK/CFN (D3), sincronização com o WA Tool (D15), Codex/Cursor (D16), 2º provedor (§3) | Decidido por uso real |

**Não commitar nem publicar sem confirmação do dono do repositório.**

---

## 16. Fontes (consultadas em 2026-09-22)

- Agent Toolkit for AWS: https://github.com/aws/agent-toolkit-for-aws · https://docs.aws.amazon.com/agent-toolkit/latest/userguide/what-is-agent-toolkit.html
- Ferramentas do AWS MCP Server: https://docs.aws.amazon.com/agent-toolkit/latest/userguide/understanding-mcp-server-tools.html
- Anúncio de GA: https://aws.amazon.com/blogs/aws/the-aws-mcp-server-is-now-generally-available/
- Skills do `aws-core`: https://github.com/aws/agent-toolkit-for-aws/tree/main/plugins/aws-core
- AWS Labs agent-plugins: https://github.com/awslabs/agent-plugins
- AWS Labs MCP: https://github.com/awslabs/mcp · https://awslabs.github.io/mcp/
- IaC MCP: https://awslabs.github.io/mcp/servers/aws-iac-mcp-server · Network MCP: https://awslabs.github.io/mcp/servers/aws-network-mcp-server
- Deprecação do Diagram MCP: https://pypi.org/project/awslabs.aws-diagram-mcp-server/ · https://github.com/awslabs/mcp/issues/2883
- API do Pricing Calculator: https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_Operations_AWS_Billing_and_Cost_Management_Pricing_Calculator.html · https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_AWSBCMPricingCalculator_CreateWorkloadEstimate.html · https://docs.aws.amazon.com/cost-management/latest/userguide/pc-getting-started.html
- AWS Pricing MCP Server: https://awslabs.github.io/mcp/servers/aws-pricing-mcp-server · https://github.com/awslabs/mcp/tree/main/src/aws-pricing-mcp-server
- Sample Pricing Calculator MCP: https://github.com/aws-samples/sample-aws-pricing-calculator-mcp
- draw.io (MCP e plugins): https://github.com/jgraph/drawio-mcp
- HashiCorp Terraform MCP: https://github.com/hashicorp/terraform-mcp-server
- Threat Composer AI: https://github.com/awslabs/threat-composer/blob/main/docs/AI-CLI-MCP.md · https://github.com/awslabs/threat-modeling-mcp-server
- Incidente Trivy: https://github.com/advisories/GHSA-69fq-xp46-6x23
- OpenInfraQuote: https://github.com/terrateamio/openinfraquote
- AWS FinOps Agent: https://aws.amazon.com/about-aws/whats-new/2026/06/aws-finops-agent-preview/
- Claude Code (plugins, dependências, evals, skills): https://code.claude.com/docs/en/plugins.md · https://code.claude.com/docs/en/plugin-dependencies.md · https://code.claude.com/docs/en/plugin-evals.md · https://code.claude.com/docs/en/skills.md
- Tool search: https://github.com/anthropics/claude-code/issues/40314
- Padrão Agent Skills: https://agentskills.io
