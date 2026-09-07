# Autenticacao dos providers helm/kubernetes sem depender de kubeconfig local
# nem de um cluster alcancavel em tempo de `validate`/`plan`.
data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# Pre-requisito do HPA (Horizontal Pod Autoscaler) usado pela aplicacao.
# Nao instalamos o AWS Load Balancer Controller: o NLB e gerenciado pelo
# Terraform nesta arquitetura, e um controller a menos e uma peca a menos
# para quebrar na demonstracao.
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  # Versão do chart fixada: sem isso, cada `helm_release` sem drift pode
  # instalar uma versão diferente a cada apply (a mais recente publicada no
  # repositório no momento), e o HPA depende inteiramente deste addon para
  # ler CPU/memória dos pods — uma mudança silenciosa de versão aqui é uma
  # mudança silenciosa na disponibilidade do autoscaling.
  version   = "3.14.0"
  namespace = "kube-system"

  depends_on = [module.eks]
}
