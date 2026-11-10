# infra-k8s — Cluster Kubernetes, manifestos e observabilidade

Segundo dos quatro repositórios da Fase 3. Provisiona a rede, o cluster
**Amazon EKS** e o caminho privado do API Gateway (Terraform — `terraform/`)
e contém os artefatos de
observabilidade do **New Relic** (`observability/`) e as pipelines de CI/CD
(`.github/workflows/`).

## Propósito

A especificação da Fase 3 exige um "cluster Kubernetes com escalabilidade"
gerenciado por Terraform. Este repositório é o dono de toda a rede e do
cluster: cria a VPC, as sub-redes, o EKS, o caminho privado até ele (NLB +
VPC Link, consumidos pelo API Gateway de `lambda-auth`), o repositório ECR
da imagem da aplicação e aplica os manifestos base (`Deployment`,
`Service`, `HorizontalPodAutoscaler`, `PodDisruptionBudget`) — nenhuma
outra stack deste projeto cria rede, cluster ou ECR.

## Tecnologias

| Item | Escolha |
|---|---|
| IaC | Terraform `>= 1.6.0`, provider `hashicorp/aws ~> 5.70`, módulos `terraform-aws-modules/vpc` e `/eks` |
| Cluster | Amazon **EKS**, node group gerenciado (Auto Scaling Group) |
| Rede | VPC dedicada, sub-redes privadas, NLB interno (`aws_lb`), VPC Link (`aws_apigatewayv2_vpc_link`) |
| Registro de imagens | Amazon **ECR** (`aws_ecr_repository.oficina_api`) |
| Orquestração | Kubernetes (EKS). Os manifestos da `oficina-api` vivem em `soat-oficina-api/k8s` |
| Autoscaling | `HorizontalPodAutoscaler` (CPU/memória) + `metrics-server` (addon) |
| Observabilidade | New Relic (`nri-bundle` via Helm + dashboard/alertas via NerdGraph/Terraform) |
| Contrato entre stacks | AWS SSM Parameter Store (`/oficina/<env>/...`) |
| Backend do estado | S3 parcial (`terraform init -backend-config=...` na pipeline) |
| CI/CD | GitHub Actions (`fmt`/`validate` em PR, `terraform apply` via OIDC no push) |

## Diagrama da stack

```mermaid
flowchart TB
    CLIENTE["Cliente (via lambda-auth: API Gateway + VPC Link)"]

    subgraph VPC["VPC (infra-k8s)"]
        subgraph PRIV["Sub-redes privadas"]
            NLB["NLB interno\n(aws_lb.interno)"]
            subgraph EKS["Cluster EKS"]
                NS["Namespace oficina"]
                SVC["Service oficina-api\nNodePort 30080"]
                DEPL["Deployment oficina-api\n(2..N réplicas)"]
                HPA["HorizontalPodAutoscaler\nCPU 60% / memória 75%"]
                PDB["PodDisruptionBudget\nminAvailable: 1"]
            end
        end
        SGDB["db-client-sg\n(\"crachá\" emprestado a EKS e lambda-auth)"]
    end

    ECR[("Amazon ECR\noficina_api")]
    SSM["SSM Parameter Store\n(vpc-id, subnets, sg, vpc-link, cluster, ecr)"]
    NR["New Relic\n(nri-bundle + dashboard + alertas)"]

    CLIENTE --> NLB --> SVC --> DEPL
    HPA -.escala.-> DEPL
    PDB -.protege.-> DEPL
    DEPL -->|"pull da imagem"| ECR
    DEPL -- "veste" --> SGDB
    DEPL -->|"métricas + logs"| NR

    VPC --> SSM
    ECR --> SSM
    SSM -.consumido por.-> INFRADB["infra-database"]
    SSM -.consumido por.-> LAMBDA["lambda-auth"]
    SSM -.consumido por.-> APP["pipeline oficina-api"]
```

## Estrutura

```
infra-k8s/
├── terraform/                 # VPC, EKS, NLB interno, VPC Link, addons, New Relic (cluster)
│   └── environments/{homolog,prod}.tfvars
├── observability/
│   ├── dashboard-oficina.json # dashboard New Relic como código
│   └── alertas.md             # condições de alerta NRQL
├── local-kind/                # setup local (kind) herdado da Fase 2 — não usado na AWS
│   ├── k8s/                   # manifestos completos p/ kind (inclui Postgres e Mailhog)
│   └── terraform/             # provider kind, cria o cluster local + aplica local-kind/k8s
└── .github/workflows/{ci,cd}.yml
```

## Terraform (`terraform/`)

Cria a VPC, o cluster EKS, o NLB interno (alvo do VPC Link do API Gateway) e o
bundle de observabilidade do New Relic (`nri-bundle` via Helm). Publica
outputs no SSM Parameter Store (`ssm.tf`) para as demais stacks (ADR-0005 —
comunicação entre repositórios via SSM, nunca remote state cruzado).

Duas variáveis de ambiente pré-definidas: `environments/homolog.tfvars` e
`environments/prod.tfvars`. O `node_port` (padrão `30080`) é o contrato entre
este Terraform (Target Group do NLB) e o `Service` Kubernetes abaixo — mudar
um sem o outro quebra o roteamento do API Gateway até o cluster.

Também provisiona, em `newrelic.tf`, o dashboard e as condições de alerta
descritos em `observability/` (ver seção "Observabilidade" abaixo) — variáveis
novas: `newrelic_account_id`, `newrelic_api_key` (ambas vazias por padrão;
todo recurso NerdGraph fica com `count = 0` até serem preenchidas) e
`uptime_check_url` (ver "Apply em duas fases" logo abaixo).

### Apply em duas fases (monitor sintético de uptime)

`var.uptime_check_url` alimenta o `newrelic_synthetics_monitor` que faz o
ping em `/api/actuator/health/readiness` — mas essa URL é o endpoint do API
Gateway, que só é publicado (`/oficina/<env>/gateway/endpoint`) pela stack
`lambda-auth`, e `lambda-auth` roda **depois** de `infra-k8s` na ordem de
apply (`infra-k8s → infra-database → lambda-auth → aplicação`). Ler esse SSM
parameter aqui de dentro criaria a dependência circular que o contrato via
SSM (ADR-0005) existe para evitar. Por isso, por ambiente:

1. **1º apply** de `infra-k8s` com `uptime_check_url = ""` (default) — cluster,
   NLB, dashboard e as 3 primeiras condições de alerta sobem; o monitor
   sintético e a condição de uptime ficam com `count = 0` (esperado).
2. Aplica `infra-database` e depois `lambda-auth` (que publica o endpoint).
3. **2º apply** de `infra-k8s`, agora com `uptime_check_url` preenchida
   (endpoint publicado por `lambda-auth`) no `environments/<env>.tfvars` ou
   via `-var` — só a partir daqui o monitor sintético existe de fato.

Detalhado também em `observability/alertas.md`, seção "O monitor sintético e
o apply em duas fases".

### Secret `oficina-secrets`

O CD de `soat-oficina-api` cria o Secret. Ele tolera a ordem de apply: se os
parâmetros SSM de `infra-database` e `lambda-auth` não existirem, ele avisa e
pula o passo.

## Manifestos Kubernetes

Os manifestos da `oficina-api` (Namespace, ConfigMap, Deployment, Service, HPA,
PDB) passaram para o repositório `soat-oficina-api` (`k8s/`) na Fase 4.
O `Service` usa `NodePort` fixo em `30080`. Esse valor precisa bater com
`terraform/nlb.tf` (`var.node_port`).

## Observabilidade (`observability/`)

Os arquivos aqui não são só documentação — são a fonte que
`infra-k8s/terraform/newrelic.tf` provisiona de fato via NerdGraph:

- **`dashboard-oficina.json`** — dashboard do New Relic como código. Lido por
  `newrelic_one_dashboard_json` via `file()` e enviado ao NerdGraph (o
  recurso substitui o `"accountId": 0` placeholder do arquivo pelo ID de
  conta real). Também pode ser importado manualmente (New Relic One >
  Dashboards > Import dashboard) se preferir não usar o Terraform. Painéis:
  volume diário de OS criadas, tempo médio de execução por status, falhas de
  integração, latência p95 das APIs, CPU/memória dos pods e uptime dos
  healthchecks. As métricas de negócio (`oficina.ordens.criadas`,
  `oficina.ordens.tempo.status`, `oficina.integracoes.falhas`) são emitidas
  pela aplicação via Micrometer (Tarefa 6, repositório `oficina-api`).
- **`alertas.md`** — quatro condições de alerta NRQL (latência p95, taxa de
  5xx, falha no processamento de OS, uptime do healthcheck), com limiar e
  canal de notificação de cada uma. Provisionadas por `newrelic_alert_policy`
  + 4× `newrelic_nrql_alert_condition` em `newrelic.tf`. **Sem canal de
  notificação anexado** (Slack/PagerDuty exigem credenciais — webhook URL,
  integration key — que este projeto não tem configuradas); anexar um canal
  é um passo manual na conta New Relic real, documentado no próprio arquivo.

Todos os recursos NerdGraph acima (`newrelic_one_dashboard_json`,
`newrelic_alert_policy`, `newrelic_nrql_alert_condition` × 4) ficam com
`count = 0` (não existem) enquanto `newrelic_account_id`/`newrelic_api_key`
estiverem vazias — mesmo padrão de guarda já usado para o bundle Helm de
observabilidade do cluster.

## Pipelines (`.github/workflows/`)

- **`ci.yml`** — `terraform fmt -check` + `terraform validate` (sem backend)
  em todo push/PR. O job `Validar manifestos Kubernetes (kustomize)` não
  renderiza mais nada e só passa. Ele existe porque é um check obrigatório.
- **`cd.yml`** — em push para `main` (ou `workflow_dispatch`): autentica na
  AWS via OIDC e roda `terraform apply` (cluster, rede, NLB, ECR, New Relic).
  O Secret `oficina-secrets`, os manifestos e o rollout da imagem pertencem
  ao CD de `soat-oficina-api`.

  O repositório ECR (`aws_ecr_repository.oficina_api`, em `ecr.tf`) também é
  provisionado por esta stack — nenhuma outra stack deste projeto cria ECR.
  A URL do repositório é publicada em `/oficina/<ambiente>/registry/repository-url`
  (SSM, mesmo padrão ADR-0005 dos demais parâmetros) e também exposta como
  output `ecr_repository_url`; a pipeline da aplicação (Tarefa 6) lê esse
  parâmetro em vez de montar a URL do registry a partir de conta/região
  fixas no workflow.

  Secrets/variables do GitHub Actions exigidos:

  | Nome | Tipo | O que quebra se estiver ausente |
  |---|---|---|
  | `AWS_DEPLOY_ROLE_ARN` | Secret | O passo "Credenciais AWS (OIDC)" falha ao assumir a role — nenhum comando Terraform/`kubectl` seguinte consegue autenticar |
  | `TF_STATE_BUCKET` | Secret | `terraform init` falha (backend S3 sem bucket) |
  | `TF_LOCK_TABLE` | Secret | `terraform init` falha (backend sem tabela de lock DynamoDB) |
  | `AWS_REGION` | Variable | Opcional — sem ela, a pipeline usa `us-east-1` como padrão |

  A mesma role `AWS_DEPLOY_ROLE_ARN` é assumida pela pipeline da aplicação
  (Tarefa 6) para publicar a imagem no ECR — além das permissões de
  Terraform/EKS já exigidas por esta stack, ela precisa de:
  `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`,
  `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`,
  `ecr:CompleteLayerUpload`. A criação/edição dessa role é feita fora destas
  stacks (por quem administra a conta AWS) — nenhum `.tf` aqui declara o
  `aws_iam_role`/`aws_iam_policy` dela, só documentamos o que ela precisa ter.

  Segredos/variáveis do New Relic — todos opcionais, repassados ao
  `terraform plan` como `TF_VAR_*` (em vez de `-var=...`, para não aparecerem
  no comando renderizado no log do Actions). Um repositório sem New Relic
  configurado ainda faz deploy normalmente: `${{ ... }}` de um secret/var
  ausente vira string vazia, e os `count` guards em `newrelic.tf` desativam
  só os recursos correspondentes.

  | Nome | Tipo | O que quebra se estiver ausente |
  |---|---|---|
  | `NEW_RELIC_LICENSE_KEY` | Secret | `helm_release.newrelic_bundle` não sobe — sem agente de infraestrutura/logs do New Relic no cluster (métricas de K8s, logs JSON encaminhados) |
  | `NEW_RELIC_ACCOUNT_ID` | Variável | Junto com `NEW_RELIC_API_KEY` ausente, desativa dashboard e as 4 condições de alerta (`local.newrelic_configured` fica falso) |
  | `NEW_RELIC_API_KEY` | Secret | Mesmo efeito de `NEW_RELIC_ACCOUNT_ID` ausente — as duas são checadas juntas |
  | `UPTIME_CHECK_URL` | Variável | `newrelic_synthetics_monitor.uptime` não é criado — sem monitor sintético, o painel de uptime do dashboard e a condição de alerta #4 não têm dados (ver "Apply em duas fases" acima: só existe depois do 1º apply de `infra-database`/`lambda-auth`) |

  `NEW_RELIC_LICENSE_KEY` já era passada ao `terraform plan` antes; as outras
  três (`NEW_RELIC_ACCOUNT_ID`, `NEW_RELIC_API_KEY`, `UPTIME_CHECK_URL`) foram
  adicionadas para fechar o gap de "dashboard e alertas escritos em código,
  mas nunca de fato criados por nenhuma pipeline".

## `local-kind/` — setup da Fase 2

Ambiente local em `kind`, usado só para desenvolvimento (não faz parte do
deploy na AWS). Contém o `Postgres` e o `Mailhog` que o `k8s/base/` não tem
mais, porque na AWS eles são substituídos por RDS e um provedor SMTP real.
Veja [`local-kind/k8s/README.md`](local-kind/k8s/README.md) e
[`local-kind/terraform/README.md`](local-kind/terraform/README.md) para o
passo a passo local completo (kind + Terraform + Kustomize).

## Documentação da API (Swagger / Postman)

Este repositório não expõe API própria — provisiona o cluster e a rede que
hospedam a aplicação. A documentação interativa das rotas é o Swagger da
aplicação (`oficina-api`), acessível através do caminho provisionado aqui:

- Swagger UI (via API Gateway, `lambda-auth`): `https://<api_endpoint>/api/swagger-ui.html`
- Swagger UI (direto no cluster, dentro da VPC): `http://<nlb-interno>/api/swagger-ui.html`
- OpenAPI JSON: `https://<api_endpoint>/api/v3/api-docs`

`<api_endpoint>` é publicado por `lambda-auth` (`terraform output api_endpoint`).

## Documentação complementar

- [`docs/arquitetura/componentes.md`](https://github.com/olavowilke/soat-oficina-api/blob/main/docs/arquitetura/componentes.md) — diagrama de componentes de todo o sistema
- [`docs/arquitetura/cicd.md`](https://github.com/olavowilke/soat-oficina-api/blob/main/docs/arquitetura/cicd.md) — pipelines, ordem de apply e secrets/variables de todos os repositórios
- [`docs/adr/0003-autoscaling-com-hpa.md`](https://github.com/olavowilke/soat-oficina-api/blob/main/docs/adr/0003-autoscaling-com-hpa.md) — ADR do autoscaling via HPA
- [`docs/adr/0002-comunicacao-sincrona-via-api-gateway.md`](https://github.com/olavowilke/soat-oficina-api/blob/main/docs/adr/0002-comunicacao-sincrona-via-api-gateway.md) — ADR da comunicação síncrona via API Gateway
- [`docs/rfc/001-escolha-da-nuvem.md`](https://github.com/olavowilke/soat-oficina-api/blob/main/docs/rfc/001-escolha-da-nuvem.md) — RFC da escolha do provedor de nuvem
- [`docs/rfc/002-api-gateway.md`](https://github.com/olavowilke/soat-oficina-api/blob/main/docs/rfc/002-api-gateway.md) — RFC da escolha do API Gateway

> A documentação compartilhada entre os 4 repositórios (`docs/`, na raiz)
> tem cópia canônica em [`soat-oficina-api`](https://github.com/olavowilke/soat-oficina-api) — este repositório referencia por link em vez de duplicar.
