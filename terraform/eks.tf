# Cluster gerenciado com o modulo oficial. Endpoint publico porque a pipeline
# de CI/CD aplica manifestos Kubernetes de fora da VPC.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "${local.prefixo}-eks"
  cluster_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Simplifica a demonstracao: quem aplica o Terraform vira admin do cluster
  # sem precisar editar o aws-auth ConfigMap manualmente.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = {}
    eks-pod-identity-agent = {}
  }

  eks_managed_node_groups = {
    principal = {
      instance_types = var.node_instance_types
      capacity_type  = var.capacity_type

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size

      # Os nos vestem o mesmo cracha da Lambda de autenticacao para acessar
      # o RDS, sem que esta stack precise conhecer o SG do banco.
      vpc_security_group_ids = [aws_security_group.db_client.id]
    }
  }
}
