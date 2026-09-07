# Caminho privado API Gateway -> cluster. O NLB e criado aqui em Terraform
# (e nao via Service type=LoadBalancer) porque o VPC Link precisa de um ARN
# de listener determinado em tempo de plan; um ELB criado por um controller
# do Kubernetes so existiria depois do apply da aplicacao.
resource "aws_lb" "interno" {
  name               = "${local.prefixo}-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = module.vpc.private_subnets
}

resource "aws_lb_target_group" "app" {
  name        = "${local.prefixo}-app"
  port        = var.node_port # 30080, o NodePort do Service
  protocol    = "TCP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"

  health_check {
    protocol            = "HTTP"
    path                = "/api/actuator/health/readiness"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 15
  }
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.interno.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# Anexa o target group diretamente ao ASG do node group, dispensando o
# AWS Load Balancer Controller (uma peca a menos para quebrar na demonstracao).
resource "aws_autoscaling_attachment" "nodes" {
  for_each               = module.eks.eks_managed_node_groups
  autoscaling_group_name = each.value.node_group_autoscaling_group_names[0]
  lb_target_group_arn    = aws_lb_target_group.app.arn
}

resource "aws_apigatewayv2_vpc_link" "cluster" {
  name               = "${local.prefixo}-vpc-link"
  subnet_ids         = module.vpc.private_subnets
  security_group_ids = [aws_security_group.vpc_link.id]
}
