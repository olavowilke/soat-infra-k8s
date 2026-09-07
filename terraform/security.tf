# SG sem regras de ingresso: serve apenas como "cracha" que autoriza
# acesso ao RDS. Nos do EKS e a Lambda de autenticacao o vestem. Essa
# indirecao quebra a dependencia circular entre as stacks: o SG do banco
# (criado em infra-database) so precisa conhecer o ID deste cracha, nunca
# os recursos que o usam.
resource "aws_security_group" "db_client" {
  name        = "${local.prefixo}-db-client"
  description = "Identifica cargas autorizadas a acessar o RDS"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Saida liberada (RDS, Secrets Manager, ECR)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# SG do VPC Link do API Gateway: so precisa alcancar os nos do EKS dentro
# da VPC para entregar o trafego HTTP ao NLB interno.
resource "aws_security_group" "vpc_link" {
  name        = "${local.prefixo}-vpc-link"
  description = "Trafego do API Gateway ate o NLB interno / nos do EKS"
  vpc_id      = module.vpc.vpc_id

  egress {
    description = "Trafego TCP para qualquer carga dentro da VPC (NLB, nos do EKS)"
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
}

# O SG dos nos (gerenciado pelo modulo EKS) precisa aceitar o trafego que
# chega pelo VPC Link no NodePort da aplicacao.
resource "aws_security_group_rule" "nos_ingress_nodeport" {
  type                     = "ingress"
  security_group_id        = module.eks.node_security_group_id
  from_port                = var.node_port
  to_port                  = var.node_port
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_link.id
  description              = "NodePort da aplicacao a partir do VPC Link (API Gateway)"
}

# aws_lb.interno (nlb.tf) nao tem `security_groups` proprio - NLB nao tem uma
# identidade de SG "de cliente" que os probes de health check do target
# group herdem. Esses probes saem dos proprios nos/ENIs do NLB (IP privado
# dentro da VPC), NUNCA da SG do VPC Link (aws_security_group.vpc_link) -
# aquela SG so cobre o trafego real do API Gateway para o NLB, entregue por
# outro caminho. Sem esta regra, o unico ingress do node_security_group_id
# no NodePort exige a SG do VPC Link como origem; os health checks nao tem
# essa SG, batem em nenhuma regra, o alvo fica "unhealthy" no target group,
# e o NLB nao encaminha nada - com "terraform apply" reportando sucesso e
# nenhum log de erro (so o console do ALB/NLB mostraria "unhealthy"). Por
# isso liberamos o NodePort a partir de qualquer IP da VPC (nao so da SG do
# VPC Link): e a unica forma de dar aos health checks do NLB, cuja origem
# nao carrega uma SG reconhecivel, uma regra que combine.
resource "aws_security_group_rule" "nos_ingress_nodeport_health_check" {
  type              = "ingress"
  security_group_id = module.eks.node_security_group_id
  from_port         = var.node_port
  to_port           = var.node_port
  protocol          = "tcp"
  cidr_blocks       = [module.vpc.vpc_cidr_block]
  description       = "Health check do NLB interno no NodePort - origem e o ENI do proprio NLB, nao a SG do VPC Link"
}
