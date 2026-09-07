variable "project" {
  description = "Prefixo de nomes dos recursos"
  type        = string
  default     = "oficina"
}

variable "environment" {
  description = "Ambiente logico (homolog | prod)"
  type        = string

  validation {
    condition     = contains(["homolog", "prod"], var.environment)
    error_message = "environment deve ser homolog ou prod."
  }
}

variable "aws_region" {
  description = "Regiao AWS"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "kubernetes_version" {
  description = "Versao do control plane do EKS"
  type        = string
  default     = "1.31"
}

variable "node_instance_types" {
  description = "Tipos de instancia do node group principal"
  type        = list(string)
  default     = ["t3.medium"]
}

variable "capacity_type" {
  description = "Modelo de capacidade do node group (ON_DEMAND | SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "node_min_size" {
  description = "Minimo de nos do node group principal"
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximo de nos do node group principal"
  type        = number
  default     = 2
}

variable "node_desired_size" {
  description = "Quantidade desejada de nos do node group principal"
  type        = number
  default     = 1
}

variable "node_port" {
  description = "NodePort do Service da aplicacao, alvo do NLB interno"
  type        = number
  default     = 30080
}

variable "newrelic_license_key" {
  description = "Chave de licenca do New Relic (vazio desativa a observabilidade)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "newrelic_account_id" {
  description = "ID da conta New Relic (NerdGraph). Vazio desativa dashboard, alertas e o monitor sintetico via Terraform."
  type        = string
  default     = ""
}

variable "newrelic_api_key" {
  description = "User API key do New Relic (NerdGraph). Vazio desativa dashboard, alertas e o monitor sintetico via Terraform."
  type        = string
  default     = ""
  sensitive   = true
}

variable "uptime_check_url" {
  description = <<-EOT
    URL publica da API (endpoint do API Gateway) usada pelo monitor sintetico
    de uptime. Fica vazia no primeiro apply desta stack: o endpoint so existe
    depois que a stack lambda-auth roda (ela vem DEPOIS de infra-k8s na ordem
    de apply). Ler /oficina/<env>/gateway/endpoint do SSM aqui criaria uma
    dependencia circular entre stacks — em vez disso, esta variavel e
    preenchida manualmente no tfvars e a stack e reaplicada numa segunda
    passada, depois que lambda-auth publica o endpoint. Vazio desativa o
    monitor sintetico.
  EOT
  type        = string
  default     = ""
}
