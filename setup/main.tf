// Terraform & Ansible Script to automate Okta Privileged Access Demo Environment
// Author: Daniel Harris @ Okta

// Initial Configuration
// Required Terraform Providers

terraform {
  required_providers {

    aws = {
      source = "hashicorp/aws"
      version = "4.58.0"
    }
  }
}

// Terraform Provider Configuration
// Amazon Web Services - Static Credentials for Base Setup
provider "aws" {
  //alias  = "opa-aws-setup"
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

// AWS Base Setup Phase
// Use AWS Static Credentials to setup environment; 
// Create opa-role
// Create opa-policy
// Assign opa-policy to opa-role

// AWS - Create IAM Role for OPA Build
// AWS - Static Credentials
resource "aws_iam_role" "opa-build-role" {
  name = "opa-build-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "elasticbeanstalk.amazonaws.com",
            "ec2.amazonaws.com"
          ],
          AWS = "arn:aws:iam::${var.aws_account_number}:user/opa-user"
        }
      },
    ]
  })
}

// AWS - Create IAM Policy for OPA Build
// AWS - Static Credentials
resource "aws_iam_policy" "opa-build-policy" {
  name        = "opa-build-policy"
  path        = "/"
  description = "opa-build-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
        {
            Effect = "Allow",
            Action = [
                "iam:*",
                "elasticbeanstalk:*",
                "sts:AssumeRole",
                "s3:*",
                "cloudformation:*",
                "ec2:*",
                "elasticloadbalancing:*",
                "autoscaling:*",
                "cloudwatch:*"
            ],
            Resource = "*"
        },
    ]
})
}

// AWS - Attach opa-build-policy to opa-build-role
// AWS - Static Credentials
resource "aws_iam_role_policy_attachment" "opa-build-attach" {
  role       = aws_iam_role.opa-build-role.name
  policy_arn = aws_iam_policy.opa-build-policy.arn
}

