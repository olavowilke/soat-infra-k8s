output "cluster_name" {
  description = "Nome do cluster kind criado"
  value       = kind_cluster.oficina.name
}

output "kubeconfig_path" {
  description = "Caminho do kubeconfig gerado pelo provider kind"
  value       = kind_cluster.oficina.kubeconfig_path
}

output "api_url" {
  description = "URL local da API (NodePort)"
  value       = "http://localhost:30080/api/swagger-ui.html"
}

output "mailhog_url" {
  description = "URL local da UI do Mailhog (NodePort)"
  value       = "http://localhost:30825"
}
