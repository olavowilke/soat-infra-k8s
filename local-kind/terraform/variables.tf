variable "cluster_name" {
  description = "Nome do cluster kind"
  type        = string
  default     = "oficina"
}

variable "node_image" {
  description = "Imagem do nó kind (versão do Kubernetes)"
  type        = string
  default     = "kindest/node:v1.31.0"
}

variable "app_image" {
  description = "Imagem da aplicação a carregar no cluster (deve existir localmente ou no registry)"
  type        = string
  default     = "oficina-api:latest"
}

variable "k8s_manifests_path" {
  description = "Caminho para os manifestos Kubernetes (kustomize)"
  type        = string
  default     = "../k8s"
}
