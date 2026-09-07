# Infraestrutura como Código — Terraform

Provisiona, do zero, o ambiente local da Oficina API em Kubernetes usando
**Terraform + kind**.

## O que é criado

| Recurso Terraform | O que provisiona |
|---|---|
| `kind_cluster.oficina` | Cluster Kubernetes local (kind) com NodePorts 30080/30825 mapeados para o host |
| `null_resource.metrics_server` | Instala o `metrics-server` (pré-requisito do HPA) |
| `null_resource.load_image` | Carrega a imagem `oficina-api:latest` no cluster |
| `null_resource.deploy_manifests` | Aplica os manifestos `/k8s` (banco StatefulSet, Mailhog, app, Service, HPA) via kustomize |

O **banco de dados** (PostgreSQL 16) é provisionado como `StatefulSet` + `PVC`
dentro do cluster (manifestos em `/k8s/postgres.yaml`), aplicado por este Terraform.

## Pré-requisitos

- [Terraform](https://developer.hashicorp.com/terraform) >= 1.5
- [Docker](https://www.docker.com/), [kind](https://kind.sigs.k8s.io/) e `kubectl` no PATH
- Imagem da aplicação buildada localmente:
  ```bash
  docker build -t oficina-api:latest ../oficina-api
  ```

## Como aplicar

```bash
cd infra
terraform init
terraform plan
terraform apply -auto-approve
```

Ao final, os `outputs` mostram a URL da API e do Mailhog. Estado local
(`terraform.tfstate`) — backend local, suficiente para o desafio.

Acompanhe o deploy:
```bash
kubectl --context oficina -n oficina get pods,svc,hpa
```

## Como destruir

```bash
terraform destroy -auto-approve
```

Remove o cluster kind por completo (e, com ele, todos os recursos e volumes).

## Variáveis principais

| Variável | Default | Descrição |
|---|---|---|
| `cluster_name` | `oficina` | Nome do cluster kind |
| `node_image` | `kindest/node:v1.31.0` | Versão do Kubernetes |
| `app_image` | `oficina-api:latest` | Imagem da app carregada no cluster |
| `k8s_manifests_path` | `../k8s` | Caminho dos manifestos kustomize |
