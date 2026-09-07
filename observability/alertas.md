# Alertas New Relic — Oficina API

Quatro condições de alerta (`NRQL Alert Conditions`) cobrindo latência,
erros HTTP, falhas de negócio e disponibilidade, agrupadas numa
`Alert Policy` chamada `oficina-<ambiente>-oficina-api`.

**Estas condições são provisionadas em Terraform**, não importadas
manualmente: `infra-k8s/terraform/newrelic.tf` cria
`newrelic_alert_policy.oficina` e os quatro
`newrelic_nrql_alert_condition` abaixo (`latencia_p95`, `erros_5xx`,
`falha_processamento_os`, `uptime_healthcheck`), guardados por
`count = local.newrelic_configured ? 1 : 0` — ou seja, só existem quando
`var.newrelic_account_id` e `var.newrelic_api_key` estão preenchidas
(mesmo padrão de `count` já usado no bundle Helm de observabilidade). Este
documento continua sendo a especificação legível da política — a fonte de
verdade executável é o `.tf`.

**Sem canal de notificação anexado à policy.** Os canais previstos
abaixo (Slack, PagerDuty) exigem credenciais que este projeto não tem
configuradas (webhook URL do Slack, integration key do PagerDuty) — criar
um `newrelic_notification_destination`/`newrelic_notification_channel` sem
essas credenciais só produziria um recurso quebrado. A policy fica criada e
as condições avaliando normalmente; anexar um canal real é um passo manual
de quem opera a conta New Relic (New Relic One > Alerts & AI > Notification
channels > associar à policy `oficina-<ambiente>-oficina-api`), ou uma
extensão futura deste `.tf` quando as credenciais existirem como secret.

## 1. Latência p95 acima de 1s

- **Query NRQL:**
  ```sql
  FROM Transaction SELECT percentile(duration, 95) WHERE appName = 'oficina-api'
  ```
- **Limiar (threshold):** acima de `1` (segundo) por `5` minutos consecutivos.
  - `critical`: `> 1s` por `5` min
  - `warning`: `> 0.7s` por `5` min
- **Tipo de sinal:** `static`, janela deslizante de 5 minutos, avaliada a cada minuto.
- **Canal de notificação:** Slack `#oficina-alertas` (crítico) e e-mail do time de plataforma (aviso).

## 2. Taxa de erros 5xx acima de 1%

- **Query NRQL:**
  ```sql
  FROM Transaction SELECT percentage(count(*), WHERE httpResponseCode LIKE '5%')
  WHERE appName = 'oficina-api'
  ```
- **Limiar (threshold):** acima de `1` (%) por `5` minutos consecutivos.
  - `critical`: `> 1%` por `5` min
  - `warning`: `> 0.5%` por `5` min
- **Tipo de sinal:** `static`, janela deslizante de 5 minutos.
- **Canal de notificação:** Slack `#oficina-alertas` (crítico) e e-mail do time de plataforma (aviso).

## 3. Falha no processamento de ordens de serviço

- **Query NRQL:**
  ```sql
  FROM Metric SELECT sum(oficina.ordens.falhas)
  ```
- **Limiar (threshold):** `oficina.ordens.falhas > 0` em qualquer janela de `5` minutos
  (qualquer falha de processamento de OS já dispara o alerta — não é uma métrica
  de taxa, é uma métrica de negócio que não deveria nunca ser positiva).
  - `critical`: `> 0` por `5` min, `at least once`
- **Tipo de sinal:** `static`, avaliado a cada minuto.
- **Canal de notificação:** Slack `#oficina-alertas` + PagerDuty (crítico — impacto direto no cliente).

## 4. Healthcheck / uptime abaixo de 99%

- **Query NRQL:**
  ```sql
  FROM SyntheticCheck SELECT percentage(count(*), WHERE result = 'SUCCESS')
  FACET monitorName
  ```
  (monitor sintético do tipo "ping" apontando para
  `GET /api/actuator/health/readiness` de cada ambiente, executado a cada 5 min)
- **Limiar (threshold):** abaixo de `99` (%) na janela de avaliação de `30` minutos.
  - `critical`: `< 99%` por `30` min
- **Tipo de sinal:** `static`, janela de 30 minutos (evita ruído de falhas pontuais
  de rede do próprio monitor sintético).
- **Canal de notificação:** Slack `#oficina-alertas` + e-mail do time de plataforma (crítico).

### O monitor sintético e o apply em duas fases

Esta condição só produz dados quando existe um monitor sintético real. Ele é
provisionado por `newrelic_synthetics_monitor.uptime` (também em
`newrelic.tf`), guardado por `count = var.uptime_check_url != "" ? 1 : 0` —
e `uptime_check_url` **não pode** ser resolvida por uma leitura de SSM
dentro desta stack: o endpoint público (`/oficina/<env>/gateway/endpoint`)
só é publicado pela stack `lambda-auth`, que roda **depois** de `infra-k8s`
na ordem de apply (`infra-k8s → infra-database → lambda-auth → aplicação`).
Ler esse parâmetro aqui criaria a dependência circular que o contrato via
SSM (ADR-0005) existe justamente para evitar.

Por isso o apply desta stack é em **duas fases**, por ambiente:

1. **Primeiro apply** — `uptime_check_url = ""` (default). Cluster, NLB,
   dashboard e as três primeiras condições de alerta sobem normalmente; a
   condição de uptime e o monitor sintético ficam com `count = 0` (não
   existem ainda — não é um estado de erro, é o estado esperado até a
   segunda fase).
2. Roda `infra-database` e depois `lambda-auth` — esta última publica
   `/oficina/<env>/gateway/endpoint`.
3. **Segundo apply** — copia o valor de `terraform output -raw
   auth_token_url`/o endpoint do API Gateway (stack `lambda-auth`) para
   `uptime_check_url` em `infra-k8s/terraform/environments/<env>.tfvars` (ou
   via `-var` na pipeline) e reaplica `infra-k8s`. Só a partir daqui o
   monitor sintético e o painel/condição de uptime passam a ter dados reais.

Isso está documentado também no `infra-k8s/README.md`, seção "Apply em duas
fases (monitor sintético de uptime)" — não é um detalhe de rodapé, é um
passo operacional real de cada ambiente.

## Canais de notificação

| Canal | Uso | Condições | Status |
|---|---|---|---|
| Slack `#oficina-alertas` | Alerta em tempo real para o time de plataforma | Todas | Não anexado (falta o webhook URL — ver seção acima) |
| E-mail (time de plataforma) | Registro/auditoria, avisos não urgentes | 1, 2 (warning), 4 | Não anexado (nenhum endereço configurado como secret) |
| PagerDuty | Acorda alguém — só para impacto direto e confirmado no cliente | 3 | Não anexado (falta a integration key) |

## Observações

- As condições 1 e 2 usam `appName = 'oficina-api'`, que é o nome reportado
  pelo agente Java do New Relic (`NEW_RELIC_APP_NAME`, ver Deployment em
  `k8s/base/deployment.yaml`) — deve bater com o valor configurado no
  agente (Tarefa 6, `oficina-api`).
- A condição 3 depende da métrica de negócio `oficina.ordens.falhas`, emitida
  pela aplicação via Micrometer (Tarefa 6) — não confundir com
  `oficina.ordens.tempo.status`, que mede duração, não falha.
- A condição 4 e o painel de uptime do dashboard dependem do monitor
  sintético `newrelic_synthetics_monitor.uptime` (Terraform, guardado por
  `var.uptime_check_url`) — ver "O monitor sintético e o apply em duas
  fases" acima para o motivo de não dar para provisioná-lo já na primeira
  passada desta stack.
