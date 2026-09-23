provider "aws" {
  region                      = "sa-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "vpc" {
  source             = "terraform-aws-modules/vpc/aws"
  version            = "5.13.0"
  name               = "app"
  cidr               = "10.0.0.0/16"
  azs                = ["sa-east-1a", "sa-east-1b"]
  private_subnets    = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets     = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = true
}

resource "aws_lb" "web" {
  name               = "web"
  load_balancer_type = "application"
  subnets            = module.vpc.public_subnets
}

resource "aws_db_instance" "db" {
  engine                      = "postgres"
  instance_class              = "db.m7g.large"
  multi_az                    = true
  allocated_storage           = 100
  storage_type                = "gp3"
  username                    = "app"
  manage_master_user_password = true
}

resource "aws_s3_bucket" "assets" {
  bucket = "assets-example-123"
}

resource "aws_elasticache_replication_group" "cache" {
  replication_group_id = "cache"
  description          = "cache"
  engine               = "valkey"
  node_type            = "cache.r7g.large"
  num_cache_clusters   = 2
}

resource "aws_dynamodb_table" "t" {
  name         = "t"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  attribute {
    name = "pk"
    type = "S"
  }
}

resource "aws_cloudwatch_log_group" "lg" {
  name              = "/app"
  retention_in_days = 30
}
