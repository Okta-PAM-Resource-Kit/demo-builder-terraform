module "prod" {
    source = "./prod"
    aws_region = var.aws_region
    aws_access_key = var.aws_access_key
    aws_secret_key = var.aws_secret_key
    opa_key = var.opa_key
    opa_secret = var.opa_secret
    opa_team = var.opa_team
}

module "dev" {
    source = "./dev"
    aws_region = var.aws_region
    aws_access_key = var.aws_access_key
    aws_secret_key = var.aws_secret_key
    opa_key = var.opa_key
    opa_secret = var.opa_secret
    opa_team = var.opa_team
}