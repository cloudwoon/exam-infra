provider "aws" {
  region = "ap-northeast-2"
}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  
  name                 = "exam-vpc"
  cidr                 = "10.0.0.0/16"
  azs                  = ["ap-northeast-2a", "ap-northeast-2c"]
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets       = ["10.0.101.0/24", "10.0.102.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    Name = "exam-vpc"
  }
}

resource "aws_security_group" "api_server_sg" {
  vpc_id = module.vpc.vpc_id

  // 보안 그룹 규칙 설정
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "eks_service_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_service_role" {
  name               = "eks-service-role"
  assume_role_policy = data.aws_iam_policy_document.eks_service_role.json
}

resource "aws_eks_cluster" "exam_cluster" {
  name     = "exam-cluster"
  role_arn = aws_iam_role.eks_service_role.arn

  vpc_config {
    subnet_ids = module.vpc.private_subnets
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_attachment" {
  role       = aws_iam_role.eks_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_eks_node_group" "exam_node_group" {
  cluster_name    = aws_eks_cluster.exam_cluster.name
  node_group_name = "exam-node-group"
  node_role_arn   = aws_iam_role.eks_service_role.arn
  subnet_ids      = module.vpc.private_subnets

  scaling_config {
    desired_size = 1
    max_size     = 2
    min_size     = 1
  }
}

module "eks_cluster" {
  source = "terraform-aws-modules/eks/aws"
  
  cluster_name    = aws_eks_cluster.exam_cluster.name
  cluster_version = "1.21"
  vpc_id          = module.vpc.vpc_id
  subnets         = module.vpc.private_subnets
}

resource "aws_db_subnet_group" "exam_db_subnet_group" {
  name       = "exam-db-subnet-group"
  subnet_ids = module.vpc.private_subnets

  tags = {
    Name = "exam-db-subnet-group"
  }
}

resource "aws_db_instance" "exam_db" {
  identifier            = "exam-db"
  instance_class        = "db.t2.micro"
  allocated_storage     = 20
  engine                = "mysql"
  engine_version        = "8.0.25"
  db_subnet_group_name  = aws_db_subnet_group.exam_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.api_server_sg.id]

  username = "admin"
  password = "password"
}

resource "aws_eip" "nat_gateway_eip" {
  vpc      = true
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.nat_gateway_eip.id
  subnet_id     = module.vpc.private_subnets[0]
}

resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Bastion server security group"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "bastion_server" {
  ami           = "ami-081a36454cdf357cb"
  instance_type = "t2.micro"
  subnet_id     = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  key_name                    = "test-key.pem"
  security_groups             = [aws_security_group.bastion_sg.name]

  tags = {
    Name = "bastion-server"
  }
}
