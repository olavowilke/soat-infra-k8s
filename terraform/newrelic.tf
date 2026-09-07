# Provider NerdGraph (dashboards, alertas, synthetics) — recursos abaixo sao
# gerados como codigo em vez de importados manualmente no New Relic One.
#
# O bloco de provider e configurado (Configure()) mesmo quando TODO recurso
# que o usa tem count = 0 — isso foi verificado experimentalmente: um
# provider "newrelic" com account_id = null falha o `terraform plan` com
# "Missing required argument", mesmo sem nenhuma instancia de recurso para
# criar. Por isso os dois argumentos abaixo nunca podem ser null/vazio;
# usamos um placeholder ("0" / "NRAK-PLACEHOLDER") quando as variaveis nao
# estao preenchidas. Esses placeholders nunca chegam a fazer uma chamada de
# API de verdade, porque `local.newrelic_configured` (abaixo) mantem todo
# recurso do New Relic em count = 0 nesse caso — o unico papel deles e
# satisfazer a validacao do proprio bloco de provider.
provider "newrelic" {
  account_id = var.newrelic_account_id != "" ? var.newrelic_account_id : "0"
  api_key    = var.newrelic_api_key != "" ? var.newrelic_api_key : "NRAK-PLACEHOLDER"
  region     = "US"
}

locals {
  # Dashboard, policy de alertas e condicoes NRQL so sao criados quando a
  # conta e a API key do New Relic estao configuradas — mesmo padrao de
  # `count` usado no bundle Helm abaixo, para o `plan` funcionar sem os
  # segredos (ambiente local, forks).
  newrelic_configured = var.newrelic_account_id != "" && var.newrelic_api_key != ""
}

# Observabilidade do cluster. Guardado por count para que o `plan` funcione
# mesmo sem a chave de licenca (ambiente local, forks sem o secret).
resource "helm_release" "newrelic_bundle" {
  count = var.newrelic_license_key != "" ? 1 : 0

  name             = "newrelic-bundle"
  repository       = "https://helm-charts.newrelic.com"
  chart            = "nri-bundle"
  namespace        = "newrelic"
  create_namespace = true

  set_sensitive {
    name  = "global.licenseKey"
    value = var.newrelic_license_key
  }

  set {
    name  = "global.cluster"
    value = module.eks.cluster_name
  }

  set {
    name  = "newrelic-infrastructure.privileged"
    value = "true"
  }

  set {
    name  = "kube-state-metrics.enabled"
    value = "true"
  }

  set {
    name  = "nri-kube-events.enabled"
    value = "true"
  }

  # Coleta os logs JSON dos pods (mesmo formato usado pela aplicacao e pelas Lambdas).
  set {
    name  = "newrelic-logging.enabled"
    value = "true"
  }

  set {
    name  = "nri-prometheus.enabled"
    value = "true"
  }

  depends_on = [module.eks]
}

# Dashboard como codigo: publica o mesmo JSON versionado em
# observability/dashboard-oficina.json, em vez de depender de alguem
# importar manualmente pelo New Relic One. O arquivo usa "accountId": 0
# como placeholder (para poder ser importado manualmente sem edicao); aqui
# trocamos pelo ID de conta real antes de enviar ao NerdGraph.
resource "newrelic_one_dashboard_json" "oficina" {
  count = local.newrelic_configured ? 1 : 0

  json = replace(
    file("${path.module}/../observability/dashboard-oficina.json"),
    "\"accountId\": 0",
    "\"accountId\": ${var.newrelic_account_id}"
  )
}

# Policy + condicoes NRQL documentadas em observability/alertas.md. Sem canal
# de notificacao anexado: os canais previstos no documento (Slack, PagerDuty)
# exigem credenciais (webhook URL, integration key) que este projeto nao tem
# configuradas — anexar um canal fica para quem operar o New Relic da conta
# real (ver observability/alertas.md).
resource "newrelic_alert_policy" "oficina" {
  count = local.newrelic_configured ? 1 : 0

  name                = "${local.prefixo}-oficina-api"
  incident_preference = "PER_CONDITION_AND_TARGET"
}

# 1. Latencia p95 acima de 1s por 5 minutos.
resource "newrelic_nrql_alert_condition" "latencia_p95" {
  count = local.newrelic_configured ? 1 : 0

  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "Oficina API - latencia p95 acima de 1s"
  description                  = "p95 de duracao das transacoes da oficina-api acima de 1s por 5 minutos."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM Transaction SELECT percentile(duration, 95) WHERE appName = 'oficina-api'"
  }

  critical {
    operator              = "above"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }

  warning {
    operator              = "above"
    threshold             = 0.7
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

# 2. Taxa de respostas 5xx acima de 1% por 5 minutos.
resource "newrelic_nrql_alert_condition" "erros_5xx" {
  count = local.newrelic_configured ? 1 : 0

  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "Oficina API - taxa de erros 5xx acima de 1%"
  description                  = "Percentual de respostas 5xx da oficina-api acima de 1% por 5 minutos."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM Transaction SELECT percentage(count(*), WHERE httpResponseCode LIKE '5%') WHERE appName = 'oficina-api'"
  }

  critical {
    operator              = "above"
    threshold             = 1
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }

  warning {
    operator              = "above"
    threshold             = 0.5
    threshold_duration    = 300
    threshold_occurrences = "ALL"
  }
}

# 3. Falha no processamento de ordens de servico — metrica de negocio que
# nunca deveria ser positiva, entao qualquer ocorrencia > 0 ja e critica.
resource "newrelic_nrql_alert_condition" "falha_processamento_os" {
  count = local.newrelic_configured ? 1 : 0

  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "Oficina API - falha no processamento de ordens de servico"
  description                  = "oficina.ordens.falhas > 0 em qualquer janela de 5 minutos."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM Metric SELECT sum(oficina.ordens.falhas)"
  }

  critical {
    operator              = "above"
    threshold             = 0
    threshold_duration    = 300
    threshold_occurrences = "AT_LEAST_ONCE"
  }
}

# 4. Uptime do healthcheck sintetico abaixo de 99% em 30 minutos.
resource "newrelic_nrql_alert_condition" "uptime_healthcheck" {
  count = local.newrelic_configured ? 1 : 0

  policy_id                    = newrelic_alert_policy.oficina[0].id
  type                         = "static"
  name                         = "Oficina API - uptime do healthcheck abaixo de 99%"
  description                  = "Uptime do monitor sintetico contra /api/actuator/health/readiness abaixo de 99% em 30 minutos."
  enabled                      = true
  violation_time_limit_seconds = 3600

  nrql {
    query = "FROM SyntheticCheck SELECT percentage(count(*), WHERE result = 'SUCCESS') FACET monitorName"
  }

  critical {
    operator              = "below"
    threshold             = 99
    threshold_duration    = 1800
    threshold_occurrences = "ALL"
  }
}

# Monitor sintetico (ping) contra o endpoint publico da API — alimenta a
# condicao de alerta #4 e o painel de uptime do dashboard. Fica desligado
# (count = 0) ate var.uptime_check_url ser preenchida, o que so acontece
# depois que a stack lambda-auth publica o endpoint do API Gateway (ver
# variables.tf e o README para o fluxo de apply em duas fases). Tambem exige
# local.newrelic_configured: sem essa segunda condicao, preencher so
# uptime_check_url (sem newrelic_account_id/newrelic_api_key) tentaria criar
# este recurso contra as credenciais placeholder ("0"/"NRAK-PLACEHOLDER" -
# ver o comentario no provider "newrelic" acima) e derrubaria o apply inteiro
# com um erro de autenticacao da API do New Relic.
resource "newrelic_synthetics_monitor" "uptime" {
  count = var.uptime_check_url != "" && local.newrelic_configured ? 1 : 0

  name             = "${local.prefixo}-oficina-api-uptime"
  type             = "SIMPLE"
  uri              = var.uptime_check_url
  locations_public = ["AWS_US_EAST_1"]
  period           = "EVERY_5_MINUTES"
  status           = "ENABLED"
  verify_ssl       = true
}
