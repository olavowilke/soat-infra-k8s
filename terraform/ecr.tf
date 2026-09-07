# Repositorio ECR onde a pipeline da aplicacao (oficina-api, Tarefa 6) publica
# a imagem Docker. Nenhuma outra stack deste projeto provisiona ECR — ficava
# faltando aqui, e sem ele o `docker push` da pipeline da aplicacao nao tem
# para onde ir (o "deploy automatico" exigido pelo enunciado da Fase 3 parava
# no primeiro push).
resource "aws_ecr_repository" "oficina_api" {
  name                 = "${local.prefixo}-oficina-api"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# Sem isso o registro cresce sem limite (imagens sao publicadas a cada push
# em homolog/main) — um vazamento de custo em camera lenta, nao um erro
# funcional imediato.
resource "aws_ecr_lifecycle_policy" "oficina_api" {
  repository = aws_ecr_repository.oficina_api.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expira imagens sem tag apos 7 dias"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Mantem no maximo as 20 imagens com tag mais recentes"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-", "homolog", "prod"]
          countType     = "imageCountMoreThan"
          countNumber   = 20
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
