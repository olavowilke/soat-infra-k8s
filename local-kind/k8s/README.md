# Kubernetes — Oficina API

Manifestos para rodar a aplicação em Kubernetes (validado em **kind** local).
Recursos: `Namespace`, `ConfigMap`, `Secret`, `Deployment` + `Service` (app),
`StatefulSet` + `PVC` + `Service` (PostgreSQL), `Deployment` + `Service` (Mailhog)
e um `HorizontalPodAutoscaler`.

## Recursos criados

| Arquivo | Recurso(s) |
|---|---|
| `namespace.yaml` | `Namespace oficina` |
| `configmap.yaml` | `ConfigMap` (config não sensível) |
| `secret.yaml` | `Secret` (JWT, senha do banco, token de webhook, credenciais SMTP) |
| `postgres.yaml` | `Service` headless + `StatefulSet` + `PVC` (PostgreSQL 16) |
| `mailhog.yaml` | `Deployment` + `Service` (SMTP de dev, UI em NodePort 30825) |
| `deployment.yaml` | `Deployment` (2 réplicas, probes, requests/limits) + `Service` NodePort 30080 |
| `hpa.yaml` | `HorizontalPodAutoscaler` (CPU 60% / memória 75%, 2→6 réplicas) |
| `kustomization.yaml` | Agrega tudo e permite trocar a imagem |

As migrations do banco rodam no **startup da aplicação** via Flyway (não há Job separado).

## Pré-requisitos

- [kind](https://kind.sigs.k8s.io/) e `kubectl`
- `metrics-server` (necessário para o HPA)

## Subindo o cluster (kind) + metrics-server

```bash
kind create cluster --name oficina --config ../infra/kind-config.yaml

# metrics-server (com --kubelet-insecure-tls, exigido no kind)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

## Build + carregar a imagem no kind

```bash
docker build -t oficina-api:latest ../oficina-api
kind load docker-image oficina-api:latest --name oficina
```

## Deploy

```bash
kubectl apply -k .
kubectl -n oficina rollout status deploy/oficina-api
```

- API: `http://localhost:30080/api/swagger-ui.html` (mapeie a porta no `kind-config.yaml`)
- Mailhog UI: `http://localhost:30825`

## Demonstrar o autoscaling (HPA)

```bash
# terminal 1 — observar
kubectl get hpa,pods -n oficina -w
# terminal 2 — gerar carga
./load-test.sh http://localhost:30080 60s 50
```

Os pods devem escalar de 2 → até 6 sob carga e recuar após a estabilização.
