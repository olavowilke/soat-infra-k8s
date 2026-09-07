output "cluster_name" {
  description = "Nome do cluster EKS"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "Endpoint da API do cluster EKS"
  value       = module.eks.cluster_endpoint
}

output "vpc_link_id" {
  description = "ID do VPC Link usado pelo API Gateway"
  value       = aws_apigatewayv2_vpc_link.cluster.id
}

output "nlb_dns_name" {
  description = "DNS interno do NLB (diagnostico dentro da VPC)"
  value       = aws_lb.interno.dns_name
}

output "db_client_security_group_id" {
  description = "SG cracha vestido pelos clientes autorizados do RDS"
  value       = aws_security_group.db_client.id
}

output "ecr_repository_url" {
  description = "URL do repositorio ECR da oficina-api (Tarefa 6)"
  value       = aws_ecr_repository.oficina_api.repository_url
}
