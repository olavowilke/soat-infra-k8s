# Provisiona o cluster Kubernetes local (kind) e implanta a aplicação + banco.
#
# Fluxo:
#   1. kind_cluster        -> cria o cluster com os NodePorts mapeados
#   2. metrics-server      -> habilita métricas (necessário para o HPA)
#   3. load da imagem      -> carrega a imagem da app no cluster kind
#   4. kubectl apply -k    -> aplica os manifestos (/k8s): banco, mailhog, app, HPA

resource "kind_cluster" "oficina" {
  name           = var.cluster_name
  node_image     = var.node_image
  wait_for_ready = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    node {
      role = "control-plane"

      extra_port_mappings {
        container_port = 30080
        host_port      = 30080
        protocol       = "TCP"
      }
      extra_port_mappings {
        container_port = 30825
        host_port      = 30825
        protocol       = "TCP"
      }
    }
  }
}

# metrics-server — pré-requisito do HorizontalPodAutoscaler.
resource "null_resource" "metrics_server" {
  depends_on = [kind_cluster.oficina]

  provisioner "local-exec" {
    command = "kubectl --context kind-${kind_cluster.oficina.name} apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  }

  # patch aplicado via --patch-file para evitar problemas de aspas do JSON no shell (cmd/PowerShell).
  # Caminho sem aspas: o diretorio nao tem espacos e as aspas escapadas eram passadas
  # literalmente pelo cmd /C, virando parte do nome do arquivo.
  provisioner "local-exec" {
    command = "kubectl --context kind-${kind_cluster.oficina.name} -n kube-system patch deployment metrics-server --type=json --patch-file ${abspath("${path.module}/metrics-server-patch.json")}"
  }
}

# Carrega a imagem local da aplicação no cluster kind.
resource "null_resource" "load_image" {
  depends_on = [kind_cluster.oficina]

  triggers = {
    image = var.app_image
  }

  provisioner "local-exec" {
    command = "kind load docker-image ${var.app_image} --name ${var.cluster_name}"
  }
}

# Aplica os manifestos Kubernetes (banco, mailhog, app, HPA) via kustomize.
resource "null_resource" "deploy_manifests" {
  depends_on = [
    null_resource.metrics_server,
    null_resource.load_image,
  ]

  triggers = {
    always = timestamp()
  }

  provisioner "local-exec" {
    command = "kubectl --context kind-${kind_cluster.oficina.name} apply -k ${var.k8s_manifests_path}"
  }
}
