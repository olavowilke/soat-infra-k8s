# Publicados para infra-database e lambda-auth consumirem via `data`, sem
# acoplar remote states entre os repositorios (ADR-0005).
resource "aws_ssm_parameter" "vpc_id" {
  name  = "${local.ssm_base}/network/vpc-id"
  type  = "String"
  value = module.vpc.vpc_id
}

# CSV (nao StringList): os consumidores fazem split(",", ...) diretamente.
resource "aws_ssm_parameter" "private_subnet_ids" {
  name  = "${local.ssm_base}/network/private-subnet-ids"
  type  = "String"
  value = join(",", module.vpc.private_subnets)
}

resource "aws_ssm_parameter" "db_client_sg_id" {
  name  = "${local.ssm_base}/network/db-client-sg-id"
  type  = "String"
  value = aws_security_group.db_client.id
}

resource "aws_ssm_parameter" "vpc_link_id" {
  name  = "${local.ssm_base}/network/vpc-link-id"
  type  = "String"
  value = aws_apigatewayv2_vpc_link.cluster.id
}

resource "aws_ssm_parameter" "nlb_listener_arn" {
  name  = "${local.ssm_base}/network/nlb-listener-arn"
  type  = "String"
  value = aws_lb_listener.app.arn
}

resource "aws_ssm_parameter" "cluster_name" {
  name  = "${local.ssm_base}/cluster/name"
  type  = "String"
  value = module.eks.cluster_name
}

resource "aws_ssm_parameter" "cluster_endpoint" {
  name  = "${local.ssm_base}/cluster/endpoint"
  type  = "String"
  value = module.eks.cluster_endpoint
}

# Publicado para a pipeline da aplicacao (oficina-api, Tarefa 6) montar a tag
# da imagem sem hardcode de conta/regiao — mesmo padrao ADR-0005 usado pelos
# demais parametros desta stack.
resource "aws_ssm_parameter" "ecr_repository_url" {
  name  = "${local.ssm_base}/registry/repository-url"
  type  = "String"
  value = aws_ecr_repository.oficina_api.repository_url
}
