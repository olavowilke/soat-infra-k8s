# Backend remoto parcial: a pipeline injeta bucket/key/region com
# `terraform init -backend-config=...` (ver .github/workflows/cd.yml).
# Localmente use `terraform init -backend=false` apenas para validar.
terraform {
  backend "s3" {}
}
