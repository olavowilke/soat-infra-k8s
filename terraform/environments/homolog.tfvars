environment         = "homolog"
aws_region          = "us-east-1"
vpc_cidr            = "10.0.0.0/16"
kubernetes_version  = "1.31"
node_instance_types = ["t3.medium"]
capacity_type       = "ON_DEMAND"
# Dois nos, nao um. Com um unico t3.medium sobravam 730m de CPU alocavel
# (1930m menos 1200m dos pods de sistema, dos quais 750m sao do nri-bundle).
# Tres pods da API pedem 750m: faltavam 20m. Como o Deployment usa
# maxUnavailable: 0, o pod velho nao podia sair para abrir espaco e o rollout
# travava sempre que o HPA subia para 2 replicas no meio do deploy - o
# `kubectl rollout status` do CD da oficina-api estourava o timeout de 300s.
# max_size 3 deixa folga para o node group trocar de versao.
node_min_size     = 2
node_max_size     = 3
node_desired_size = 2
