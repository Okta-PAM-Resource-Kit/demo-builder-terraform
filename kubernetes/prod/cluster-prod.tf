// Deploy Kubernetes Prod Cluster for Demo

// Required Terraform Providers
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.26.0"
    }
    local = {
      source = "hashicorp/local"
      version = "2.2.3"
    }
    oktapam = {
      source = "okta/oktapam"
      version = "0.2.2"
    }
    external = {
      source = "hashicorp/external"
      version = "2.2.2"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.13.1"
    }
  }
}

// Terraform Provider Configuration
// Amazon Web Services
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
    assume_role {
    role_arn     = var.aws_role_arn
    session_name = "opa-terraform-session"
  }
}

// Okta Priviledged Access
provider "oktapam" {
  oktapam_key = var.opa_key
  oktapam_secret = var.opa_secret
  oktapam_team = var.opa_team
}

// Kubernetes
provider "kubernetes" {
  host                   = data.aws_eks_cluster.opa-eks_cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.opa-eks_cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.opa-eks_cluster-auth.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", aws_eks_cluster.opa-eks_cluster.id]
    command     = "aws"
  }
}

// Start Environment Build Process

// OPA - Create Kubernetes Cluster in OPA
resource "oktapam_kubernetes_cluster" "opa-cluster" {
  auth_mechanism    = "OIDC_RSA2048"
  key		 	          = "opa-cluster"
  labels		        = { env = "prod"}
}

// AWS - Lookup EKS Cluster Information
data "aws_eks_cluster" "opa-eks_cluster" {
  name = aws_eks_cluster.opa-eks_cluster.id
}

data "aws_eks_cluster_auth" "opa-eks_cluster-auth" {
  name = aws_eks_cluster.opa-eks_cluster.id
}

// Local - Decode AWS EKS Base64 Encoded Certificate to be uploaded into OPA
locals {
    aws_eks_cert = base64decode("${data.aws_eks_cluster.opa-eks_cluster.certificate_authority[0].data}")
}

// OPA - Set EKS Cluster Connection Information 
resource "oktapam_kubernetes_cluster_connection" "opa-cluster" {
  cluster_id         = oktapam_kubernetes_cluster.opa-cluster.id
  api_url            = data.aws_eks_cluster.opa-eks_cluster.endpoint
  public_certificate = local.aws_eks_cert
}

// OPA - Create Cluster Group
resource "oktapam_kubernetes_cluster_group" "opa-cluster" {
  cluster_selector  = "env=prod"
  group_name		= "everyone"
  claims		= { group = "everyone" }
}

// AWS - Lookup AWS Availability Zones based upon current AWS Region
data "aws_availability_zones" "available" {}

// AWS - Create EKS Networking
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "opa-eks-vpc"

  cidr = "10.0.0.0/16"
  azs  = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    Name = "opa-eks-vpc"
    Project = "opa-terraform"
  }
}

// AWS - Create IAM role for Kubernetes clusters to make calls to other AWS services on your behalf to manage the resources that you use with the service.
resource "aws_iam_role" "opa-iam-role-eks-cluster" {
  name = "opa-cluster"
  assume_role_policy = <<POLICY
{
 "Version": "2012-10-17",
 "Statement": [
   {
   "Effect": "Allow",
   "Principal": {
    "Service": "eks.amazonaws.com"
   },
   "Action": "sts:AssumeRole"
   }
  ]
 }
POLICY
}

// Attaching the EKS-Cluster policies to the opa-cluster role.
resource "aws_iam_role_policy_attachment" "opa-eks-cluster-AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = "${aws_iam_role.opa-iam-role-eks-cluster.name}"
}

// Security group for network traffic to and from AWS EKS Cluster.
resource "aws_security_group" "opa-eks-cluster" {
  name        = "opa-eks"
  vpc_id      = module.vpc.vpc_id  

  egress {      
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {           
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] // My IP
  }
}

// Creating the EKS cluster
resource "aws_eks_cluster" "opa-eks_cluster" {
  name     = "opa-eks-cluster"
  role_arn =  "${aws_iam_role.opa-iam-role-eks-cluster.arn}"

  vpc_config {         
   security_group_ids = ["${aws_security_group.opa-eks-cluster.id}"]
   subnet_ids         = module.vpc.private_subnets
    }

  depends_on = [
    aws_iam_role_policy_attachment.opa-eks-cluster-AmazonEKSClusterPolicy,
   ]
}

// AWS - Configure OIDC Authentication for EKS 
resource "aws_eks_identity_provider_config" "opa-eks_cluster" {
  cluster_name = aws_eks_cluster.opa-eks_cluster.name

  oidc {
    client_id                     = "kubernetes"
    identity_provider_config_name = "okta"
    issuer_url                    = oktapam_kubernetes_cluster.opa-cluster.oidc_issuer_url
    username_claim                = "sub"
    # username_prefix               = "OPA-User:" 
    groups_claim                  = "group"
    # groups_prefix                 = "OPA-Group:"
  }
}

// Creating IAM role for EKS nodes to work with other AWS Services. 
resource "aws_iam_role" "opa-eks_nodes" {
  name = "opa-eks-node-group"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

// Attaching the different Policies to Node Members.
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.opa-eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.opa-eks_nodes.name
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.opa-eks_nodes.name
}

// Create EKS cluster node group
resource "aws_eks_node_group" "opa-node-group" {
  cluster_name    = aws_eks_cluster.opa-eks_cluster.name
  node_group_name = "opa-node-group-one"
  node_role_arn   = aws_iam_role.opa-eks_nodes.arn
  subnet_ids      = module.vpc.private_subnets
  instance_types   = ["t2.micro"]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
  ]
}

resource "kubernetes_cluster_role" "opa-eks_cluster_role" {
  metadata {
    name = "opa-eks-cluster-role-read-only"
  }

  rule {
      api_groups = [""]
      resources  = ["*"]
      verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "opa-eks-cluster-role-binding" {
  metadata {
    name = "opa-eks-cluster-role-binding"
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = "opa-eks-cluster-role-read-only"
  }
  subject {
    kind      = "Group"
    name      = "everyone"
    api_group = "rbac.authorization.k8s.io"
  }
}