# VPC dedicada ao cluster. Sub-redes publicas hospedam apenas o NAT Gateway;
# nos do EKS, RDS e a Lambda de autenticacao ficam nas privadas.
data "aws_availability_zones" "disponiveis" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${local.prefixo}-vpc"
  cidr = var.vpc_cidr

  azs             = slice(data.aws_availability_zones.disponiveis.names, 0, 2)
  public_subnets  = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(2) : cidrsubnet(var.vpc_cidr, 4, i + 2)]

  enable_nat_gateway = true
  # Um unico NAT em homolog reduz custo; producao usa um por AZ para nao
  # perder saida a internet se uma AZ cair.
  single_nat_gateway   = var.environment != "prod"
  enable_dns_hostnames = true

  # Tags exigidas pelo EKS/kubernetes para autodiscovery de sub-redes por
  # controllers de load balancer.
  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}
