// Terraform & Ansible Script to automate Okta Privileged Access
// Author: Daniel Harris @ Okta
// Main OPA Feature Set

// Initial Configuration
// Required Terraform Providers

terraform {
  required_providers {
    okta = {
      source = "okta/okta"
      version = "3.34.0"
    }
    aws = {
      source = "hashicorp/aws"
      version = "4.58.0"
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
// Okta

provider "okta" {
  org_name  = var.okta_org
  base_url  = var.okta_environment
  api_token = var.okta_admintoken
  }

# // Amazon Web Services - Static Credentials for Base Setup
# provider "aws" {
#   //alias  = "opa-aws-setup"
#   region     = var.aws_region
#   access_key = var.aws_access_key
#   secret_key = var.aws_secret_key
# }

// Amazon Web Services - Assume Role for Provisioning Setup
provider "aws" {
  alias = "opa-aws-build"
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

// Demo Setup 

// Okta - Look up Demo User ID (from config.tfvars)
data "okta_user" "demouser" {
  user_id = "${var.okta_demouser_id}"
}

// Okta - Create Attribute Domain Password Terraform
resource "okta_user_schema_property" "domain-password-terraform" {
  index       = "activeDirectoryIdentity"
  title       = "Active Directory Identity"
  type        = "array"
  array_type  = "string" 
  description = "activeDirectoryIdentity"
  master      = "OKTA"
  permissions = "READ_WRITE"
}

// Okta - Create Attribute Domain Passwordless Terrafom
resource "okta_user_schema_property" "domain-passwordless-terraform" {
  index       = "activeDirectoryPasswordlessIdentity"
  title       = "Active Directory Passwordless Identity"
  type        = "array"
  array_type  = "string" 
  description = "activeDirectoryPasswordlessIdentity"
  master      = "OKTA"
  permissions = "READ_WRITE"
}

resource "null_resource" "okta-attribute-update" {
  provisioner "local-exec" {
      command = <<EOT
        curl -s -X POST https://${var.okta_org}.${var.okta_environment}/api/v1/users/${var.okta_demouser_id} \
             -H 'Accept: application/json' \
             -H 'Content-Type: application/json' \
             -H 'Authorization: SSWS ${var.okta_admintoken}' \
             -d '{
                "profile": {
                      "activeDirectoryPasswordlessIdentity": [
                            "svc-iis@opa-domain.com"
                          ],
                      "activeDirectoryIdentity": [
                            "Administrator@opa-domain.com"
                           ]
                    }
                }'
EOT
  }
  depends_on = [
    okta_user_schema_property.domain-password-terraform, okta_user_schema_property.domain-passwordless-terraform
  ]
}

data "okta_user_profile_mapping_source" "okta-mapping-source" {}

// Okta - Map new user attributes to ASA Application Profile
resource "okta_profile_mapping" "opa-ad-joined-attributes-mapping" {
  source_id          = "${data.okta_user_profile_mapping_source.okta-mapping-source.id}"
  target_id          = var.okta_asa_app_id
  delete_when_absent = false
  always_apply = true

  mappings {
    id         = "activeDirectoryIdentity"
    expression = "user.activeDirectoryIdentity"
    push_status = "PUSH"
  }

  mappings {
    id         = "activeDirectoryPasswordlessIdentity"
    expression = "user.activeDirectoryPasswordlessIdentity"
    push_status = "PUSH"
  }
  depends_on = [
    okta_user_schema_property.domain-password-terraform, okta_user_schema_property.domain-passwordless-terraform
  ]
}

// Okta - Create OPA Full Administrators group
resource "okta_group" "opa_admins" {
  name        = "OPA Full Administrators"
  description = "Okta Priviledged Access Full Administrators"
}

// Okta - Create OPA System Administrators group
resource "okta_group" "systemadministrators" {
  name        = "OPA System Administrators"
  description = "Okta Priviledged Access System Administrators"
}

// Okta - Create OPA DevOps group
resource "okta_group" "opa_devops" {
  name        = "OPA DevOps"
  description = "Okta Priviledged Access DevOps Team Members"
}

// Okta - Create OPA Cloud Operations group
resource "okta_group" "opa_cloudops" {
  name        = "OPA Cloud Operations"
  description = "Okta Priviledged Access Cloud Operations Team Members"
}


// Okta - Assign ASA/OPA Demo User (from config.tfvars) to OPA Full Administrator Group
resource "okta_group_memberships" "opa_fulladmin_memberships" {
  group_id = okta_group.opa_admins.id
  users = [
    data.okta_user.demouser.user_id
  ]
}

// Okta - Look up ASA/OPA Application ID (from config.tfvars)
data "okta_app" "okta_asa_app_id" {
  id = "${var.okta_asa_app_id}"
}

// Okta - Assign OPA Groups to ASA/OPA Application
resource "okta_app_group_assignments" "okta_asa_group_assignment" {
  app_id   = "${var.okta_asa_app_id}"
  group {
    id = okta_group.opa_admins.id
    priority = 1
  }
  group {
    id = okta_group.systemadministrators.id
    priority = 2
  }
  group {
    id = okta_group.opa_devops.id
    priority = 3
  }
  group {
    id = okta_group.opa_cloudops.id
    priority = 3
  }
}

// OPA - Create Gateway Setup Token
resource "oktapam_gateway_setup_token" "opa-gateway-token" {
    description = "OPA gateway token"
    labels = {env:"terraform-${local.timestamp}"}
}

// OPA - Create OPA-Gateway Project
resource "oktapam_project" "opa-gateway" {
    name = "opa-gateway"
    create_server_users = true
    forward_traffic = true
    gateway_selector = "env=terraform-${local.timestamp}"
    rdp_session_recording = true
    ssh_session_recording = true
}

// OPA - Create OPA-Gateway Project Enrollment Tokem
resource "oktapam_server_enrollment_token" "opa-gateway-enrollment-token" {
    description = "OPA Gateway Enrollment Token"
    project_name = oktapam_project.opa-gateway.name
}

// OPA - Assign 'everyone' group to the OPA-Gateway Project
// Future - Change to Okta Based Groups
resource "oktapam_project_group" "opa-everyone-group" {
  group_name    = "everyone"
  project_name  = oktapam_project.opa-gateway.name
  create_server_group = true
  server_access = true
  server_admin  = true
}

// OPA - Create OPA-Domain-Joined Project
resource "oktapam_project" "opa-domain-joined" {
    name = "opa-domain-joined"
    create_server_users = true
    forward_traffic = true
    gateway_selector = "env=terraform-${local.timestamp}"
    rdp_session_recording = true
    ssh_session_recording = true
}

// OPA - Assign 'everyone' to OPA-Domain-Joined project
// Future - Change to Okta Based Groups
resource "oktapam_project_group" "opa-everyone-group-domain-joined" {
  group_name    = "everyone"
  project_name  = oktapam_project.opa-domain-joined.name
  create_server_group = false
  server_access = true
  server_admin  = false
}

// OPA - Create OPA-Linux project
resource "oktapam_project" "opa-linux" {
    name = "opa-linux"
    create_server_users = true
    forward_traffic = true
    gateway_selector = "env=terraform-${local.timestamp}"
    rdp_session_recording = true
    ssh_session_recording = true
}

// OPA - Assign 'everyone' to OPA-Linux project
// Future - Change to Okta Based Groups
resource "oktapam_project_group" "opa-everyone-group-linux" {
  group_name    = "everyone"
  project_name  = oktapam_project.opa-linux.name
  create_server_group = true
  server_access = true
  server_admin  = true
}

// OPA - Create OPA-Linux Project Enrollment Tokem
resource "oktapam_server_enrollment_token" "opa-linux-enrollment-token" {
    description = "OPA Linux Enrollment Token"
    project_name = oktapam_project.opa-linux.name
}

// OPA - Create OPA-Windows Project
resource "oktapam_project" "opa-windows-target" {
    name = "opa-windows"
    create_server_users = true
    forward_traffic = true
    gateway_selector = "env=terraform-${local.timestamp}"
    rdp_session_recording = true
    ssh_session_recording = true
    require_preauth_for_creds = true
}

// OPA - Assign 'everyone' to OPA-Windows Project
// Future - Change to Okta Based Groups
resource "oktapam_project_group" "opa-everyone-group-windows" {
  group_name    = "everyone"
  project_name  = oktapam_project.opa-windows-target.name
  create_server_group = true
  server_access = true
  server_admin  = false
}

// OPA - Create Local OPA Group called Dev - For Kubernetes Demo
resource "oktapam_group" "opa-dev-group" {
  name = "dev"
}

// OPA - Add Demo User to Dev Group - For Kubernetes Demo
// TO DO
// WAITING FOR PRODUCT

// OPA - Create OPA-Windows Project Enrollment Token
resource "oktapam_server_enrollment_token" "opa-windows-enrollment-token" {
    description = "OPA Windows Enrollment Token"
    project_name = oktapam_project.opa-windows-target.name
}

# # // OPA - Fetch Bearer Token
# # // OPA - Create Shell Script
# resource "local_file" "opa-bearer-script-create" {
#   filename = "./opa-bearer.sh"
#   content =  <<-EOT
#   #!/bin/bash
#   curl --location --request POST 'https://app.scaleft.com/v1/teams/${var.opa_team}/service_token' \
# --header 'Content-Type: application/json' \
# --data-raw '{
#     "key_id": "${var.opa_key}",
#     "key_secret": "${var.opa_secret}"
# }'
# EOT
# }

# # // OPA - Call Bearer Token Shell Script
# data "external" "opa-bearer-script-execute" {
#   program = [ "bash", "./opa-bearer.sh" ]

# depends_on = [
#   local_file.opa-bearer-script-create
# ]
# }

# # // OPA - Store Bearer Token
# output "opa-bearer-token" {
#   value = data.external.opa-bearer-script-execute.result.bearer_token
# }

# // OPA - Fetch Bearer Token
# resource "null_resource" "opa-bearer-token" {
#   provisioner "local-exec" {
#       command = <<EOT
#         curl -s -o /opa-bearer-token-output.json POST https://app.scaleft.com/v1/teams/${var.opa_team}/service_token \
#              -H 'Content-Type: application/json' \
#              -H 'Authorization: Bearer' \
#              -d '{
#     "key_id": "${var.opa_key}",
#     "key_secret": "${var.opa_secret}"
# }'
# EOT
#   }
# }

# // OPA - Delete Gateway
# resource "null_resource" "opa-gateway-delete" {
#   provisioner "local-exec" {
#       command = <<EOT
#         curl -s -X DELETE https://app.scaleft.com/v1/teams/${var.opa_team}/gateways/${data.oktapam_gateways.opa-gateway.gateways[0].id} \
#              -H 'Content-Type: application/json' \
#              -H 'Authorization: Bearer ${opa-bearer-token.value}' \
#              -d '{
#     "key_id": "${var.opa_key}",
#     "key_secret": "${var.opa_secret}"
# }'
# EOT
#   }
# }

# // OPA - Create Sudo Entitlement
# resource "null_resource" "opa-sudo-entitlement-create" {
#   provisioner "local-exec" {
#       command = <<EOT
#         curl -s -X POST https://app.scaleft.com/v1/teams/${var.opa_team}/entitlements/sudo \
#              -H 'Accept: application/json' \
#              -H 'Content-Type: application/json' \
#              -H 'Authorization: Bearer ${data.external.opa-bearer-script-execute.result.bearer_token}' \
#              -d '{
#     "name": "APT-GET-UPDATE",
#     "add_env": [],
#     "description": "Grant access to: apt-get update",
#     "opt_no_exec": false,
#     "opt_no_passwd": true,
#     "opt_run_as": "root",
#     "opt_set_env": false,
#     "commands": [],
#     "structured_commands": [
#         {
#             "args": "update",
#             "args_type": "custom",
#             "command": "/usr/bin/apt-get",
#             "command_type": "executable"
#         }
#     ],
#     "sub_env": []
# }'
# EOT
#   }

# depends_on = [
#   data.external.opa-bearer-script-execute
# ]
# }

// OPA - Assign Sudo Entitlement to Project Group
// TO DO

// OPA - Create self-signed certificate for password-less authentication to windows ad joined machines
resource "oktapam_ad_certificate_request" "opa_ad_self_signed_cert" {
  type         = "self_signed"
  display_name = "opa_ad_cert"
  common_name  = "opa"
  details {
   ttl_days = 90
  }
}

// Local - Copy OPA AD Certificate locally to copy onto Domain Controller
resource "local_file" "opa_ad_self_signed_cert" {
  content = oktapam_ad_certificate_request.opa_ad_self_signed_cert.content
  filename = "temp/certs/opa_ss.cer"
}

// Create Random String
resource "random_string" "random-string" {
  length           = 8
  special          = false
  upper            = false
}


// AWS - Build Phase
// AWS - Use AssumeRole to increase security

// AWS - Create IAM Role for opa-utils
// AWS - AssumeRole Credentials
resource "aws_iam_role" "opa-utils-iam-role" {
  provider = aws.opa-aws-build
  name = "opa-utils-iam-role"
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
          ]
        }
      },
    ]
  })
}

// AWS - Create IAM Policy for opa-utils
// AWS - AssumeRole Credentials
resource "aws_iam_policy" "opa-utils-iam-policy" {
  provider = aws.opa-aws-build
  name        = "opa-utils-iam-policy"
  path        = "/"
  description = "opa-utils-iam-policy"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
        {
            Effect = "Allow",
            Action = [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:DeleteObject",
                "s3:ListAllMyBuckets",
                "s3:createBucket",
                "s3:deleteBucket",
                "s3-object-lambda:*",
                "s3:GetBucketLocation"
            ],
            Resource = "*"
        },
        {
            Action = [
                "iam:CreateInstanceProfile",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:AddRoleToInstanceProfile",
                "iam:PassRole",
                "iam:AttachRolePolicy",
                "iam:CreateRole",
                "iam:DeleteInstanceProfile"
            ],
            Effect = "Allow",
            Resource = "*"
        }
    ]
})
}

// AWS - Attach policies to opa-utils-role
// AWS - AssumeRole Credentials
resource "aws_iam_role_policy_attachment" "opa-utils-iam-role-attach" {
  provider = aws.opa-aws-build
  role       = aws_iam_role.opa-utils-iam-role.name
  policy_arn = aws_iam_policy.opa-utils-iam-policy.arn
}

resource "aws_iam_role_policy_attachment" "ebs-admin-role-attach" {
  provider = aws.opa-aws-build
  role       = aws_iam_role.opa-utils-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess-AWSElasticBeanstalk"
}

resource "aws_iam_role_policy_attachment" "ebswebtier-admin-role-attach" {
  provider = aws.opa-aws-build
  role       = aws_iam_role.opa-utils-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "ebsmulti-admin-role-attach" {
  provider = aws.opa-aws-build
  role       = aws_iam_role.opa-utils-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "ebsworkertier-admin-role-attach" {
  provider = aws.opa-aws-build
  role       = aws_iam_role.opa-utils-iam-role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

// AWS - Create Instance Profile
// AWS - AssumeRole Credentials
resource "aws_iam_instance_profile" "opa-instance-profile" {
  provider = aws.opa-aws-build
  name = "opa-instance-profile"
  role = aws_iam_role.opa-utils-iam-role.name
}

resource "local_file" "opa-utils-instance-profile-name" {
  content = aws_iam_instance_profile.opa-instance-profile.name
  filename = "opa-utils-instance-profile-name.txt"

  provisioner "local-exec" {
    when    = destroy
    command = "rm opa-utils-instance-profile-name.txt"
  }
}

// Create AWS S3 Bucket for Session Replay
// AWS - AssumeRole Credentials
resource "aws_s3_bucket" "opa-s3-bucket-session-replay" {
  provider = aws.opa-aws-build
  bucket        = "opautils${random_string.random-string.result}"
  force_destroy = true
}

resource "local_file" "opa-s3-bucket-name" {
  content = aws_s3_bucket.opa-s3-bucket-session-replay.id
  filename = "opa-s3-bucket-name.txt"

  provisioner "local-exec" {
    when    = destroy
    command = "rm opa-s3-bucket-name.txt"
  }
}

resource "local_file" "opa-s3-bucket-region" {
  content = aws_s3_bucket.opa-s3-bucket-session-replay.region
  filename = "opa-s3-bucket-region.txt"

   provisioner "local-exec" {
    when    = destroy
    command = "rm opa-s3-bucket-region.txt"
  }
}

// AWS - Create OPA Demo Network on AWS (VPC, Internet Gateway, Route, Subnet, Interfaces)
// AWS - Create VPC
// AWS - AssumeRole Credentials
resource "aws_vpc" "opa-vpc" {
  provider = aws.opa-aws-build
  cidr_block = "172.16.0.0/16"

  tags = {
    Name = "opa-vpc"
    Project = "opa-terraform"
  }
}

// AWS - Create Internet Gateway
// AWS - AssumeRole Credentials
resource "aws_internet_gateway" "opa-internet-gateway" {
  provider = aws.opa-aws-build
  vpc_id = "${aws_vpc.opa-vpc.id}"

  tags = {
  Name = "opa-internet-gateway"
  Project = "opa-terraform"
  }
}

// AWS - Create Route
// AWS - AssumeRole Credentials
resource "aws_route" "opa-route" {
  provider = aws.opa-aws-build
  route_table_id         = "${aws_vpc.opa-vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.opa-internet-gateway.id}"
}

// AWS - Create Subnet
// AWS - AssumeRole Credentials
resource "aws_subnet" "opa-subnet" {
  provider = aws.opa-aws-build
  vpc_id            = aws_vpc.opa-vpc.id
  cidr_block        = "172.16.10.0/24"
  availability_zone = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "opa-subnet"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-GW-Interfact Network Interface
// AWS - AssumeRole Credentials
resource "aws_network_interface" "opa-gw-interface" {
  provider = aws.opa-aws-build
  subnet_id   = aws_subnet.opa-subnet.id
  private_ips = ["172.16.10.100"]
  security_groups = [aws_security_group.opa-gateway.id]

  tags = {
    Name = "opa-gw-interface"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Domain-Controller Network Interface
// AWS - AssumeRole Credentials
resource "aws_network_interface" "opa-dc-interface" {
  provider = aws.opa-aws-build
  subnet_id   = aws_subnet.opa-subnet.id
  private_ips = ["172.16.10.150"]
  security_groups = [aws_security_group.opa-domain-controller.id]

 tags = {
    Name = "opa-dc-interface"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Linux-Target Network Interface
// AWS - AssumeRole Credentials
resource "aws_network_interface" "opa-linux-target-interface" {
  provider = aws.opa-aws-build
  subnet_id   = aws_subnet.opa-subnet.id
  private_ips = ["172.16.10.200"]
  security_groups = [aws_security_group.opa-linux-target.id]

 tags = {
    Name = "opa-linux-interface"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Linux-Target-2 Network Interface
// AWS - AssumeRole Credentials
resource "aws_network_interface" "opa-linux-target-2-interface" {
  provider = aws.opa-aws-build
  subnet_id   = aws_subnet.opa-subnet.id
  private_ips = ["172.16.10.205"]
  security_groups = [aws_security_group.opa-linux-target-2.id]

 tags = {
    Name = "opa-linux-interface-2"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Windows-Target Network Interface
// AWS - AssumeRole Credentials
resource "aws_network_interface" "opa-windows-target-interface" {
  provider = aws.opa-aws-build
  subnet_id   = aws_subnet.opa-subnet.id
  private_ips = ["172.16.10.210"]
  security_groups = [aws_security_group.opa-windows-target.id]

 tags = {
    Name = "opa-windows-target-interface"
    Project = "opa-terraform"
  }
}

// AWS - Look Up Latest Ubuntu Image on AWS
// AWS - AssumeRole Credentials
data "aws_ami" "ubuntu" {
  provider = aws.opa-aws-build
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

// AWS - Look Up Latest Windows Image on AWS
// AWS - AssumeRole Credentials
data "aws_ami" "windows" {
  provider = aws.opa-aws-build
  most_recent = true
  
  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
 }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
 }
  owners = ["801119661308"] # Canonical
 }

// General - Timestamp
locals {
  timestamp = formatdate("DDMMYYYY", timestamp())
}

// AWS - Create OPA-Gateway
// AWS - AssumeRole Credentials
resource "aws_instance" "opa-gateway" {
  provider = aws.opa-aws-build
  ami                           = data.aws_ami.ubuntu.id
  instance_type                 = "t2.medium"
  iam_instance_profile          = aws_iam_instance_profile.opa-instance-profile.name 
  key_name                      = var.aws_key_pair
  user_data_replace_on_change   = true
  user_data                     = <<EOF
#!/bin/bash -x
sudo apt-get update
sudo apt-get -y install resolvconf
echo "nameserver 172.16.10.150" > /etc/resolvconf/resolv.conf.d/head
sudo resolvconf -u
sudo mkdir -p /etc/sft
hostnamectl set-hostname opa-gateway-${local.timestamp}

echo "Retrieve information about new packages"
sudo apt-get update
sudo apt-get install -y curl

echo "Stable Branch"
echo "Add APT Key"
curl https://dist.scaleft.com/GPG-KEY-OktaPAM-2023 | gpg --dearmor | sudo cat >/usr/share/keyrings/oktapam-2023-archive-keyring.gpg
echo "Create List"
printf "deb [signed-by=/usr/share/keyrings/oktapam-2023-archive-keyring.gpg] https://dist.scaleft.com/repos/deb focal okta" | sudo tee /etc/apt/sources.list.d/oktapam-stable.list > /dev/null
sudo apt-get update

echo "Install Gateway"
sudo apt-get install -y scaleft-gateway
echo ${oktapam_gateway_setup_token.opa-gateway-token.token} > /var/lib/sft-gatewayd/setup.token

cd /etc/sft/
cat > sft-gatewayd.yaml <<EEOFF
# Sample configuration file for sft-gatewayd, the Advanced Server Access Gateway
# service. Copy this file to sft-gatewayd.yaml and uncomment any customizations
# you need to make.

# You must specify a setup token either in this config file or a separate
# SetupTokenFile. All other configuration values are optional and have sensible
# defaults.

# ----------------------------------------
# Enrollment Token
# These options control how you add an enrollment token to your gateway. You
# must enable either SetupToken or SetupTokenFile.
# ----------------------------------------
# Specifies the setup token directly. When using this option, we recommend 
# restricting read permissions to this configuration file (e.g. 0600 on Linux).
#SetupToken: yoursetuptoken

# Specifies the path to a separate file containing the enrollment token.
# SELinux users may label this file with: sft_gatewayd_setuptoken_t
#SetupTokenFile: /path/to/setup/token


# ----------------------------------------
# Logs
# This option controls how the gateway logs events.
# ----------------------------------------
# Controls the verbosity of the logs. We recommend setting this to info
# Valid log levels include: error, warn, info, debug
#LogLevel: info


# ----------------------------------------
# Connections
# These options control how the gateway manages connections.
# ----------------------------------------
# Specifies the network address & port clients can use to access the gateway.
# If not specified, the gateway uses the address indicated by the network
# interface or cloud provider metadata.
#AccessAddress: "1.1.1.1"
#AccessPort: 7234

# Specifies the network address & port the gateway uses to listen for
# connections. Use the default (0.0.0.0) to listen on every interface.
#ListenAddress: “0.0.0.0”
#ListenPort: 7234

# Forces the gateway to use the bundled certificate store (instead of the OS
# certificate store) to secure HTTP requests with TLS. This also includes
# requests to the Advanced Server Access cloud service. To use the OS
# certificate store, set to false.
#TLSUseBundledCAs: true

# Controls whether the gateway accepts SSH and RDP proxy traffic.
# If enabled, SSH and RDP connection requests aren’t routed through the gateway
# won’t listen for proxy traffic requests.
#RefuseConnections: false

# Specifies the URL of an HTTP CONNECT proxy used for outbound network
# connectivity to Advanced Server Access. Alternatively, use the HTTPS_PROXY
# environment variable to configure this proxy.
#ForwardProxy: https://proxy.mycompany.example

# ----------------------------------------
LDAP:
# LDAP
# These options control how the gateway establishes secure connections with
# LDAP servers (usually Active Directory). By default, the gateway starts
# TLS, but doesn’t perform any certificate validation.
# ----------------------------------------
# Upgrades Active Directory/LDAP server communications to TLS. If disabled,
# communication with the server is not encrypted.
  StartTLS: false

# This option is to use LDAPS protocol for AD connection, enabling this setting is not recommended. StartTLS is the preferred communication protocol.
# LDAPS is the non-standardized "LDAP over SSL" protocol that in contrast with StartTLS only allows communication over
# a secure port such as 636. It establishes the secure connection before there is any communication with the LDAP server.
# Only one connection protocol can be set in config: UseLDAPS or StartTLS. If using LDAPS then set StartTLS to false.
#  UseLDAPS: false

# Default value is set to 636
# If UseLDAPS option is true then this port value is used to make LDAPS(LDAP over SSL) connection
#  LDAPSPort: 636

# Perform validation on certificates received from the AD/LDAP server. If
# enabled, the gateway looks for certificates at the path specified for
# TrustedCAsDir. If no certificates are found, the gateway rejects all
# connections.
#  ValidateCertificates: false

# Specifies the path to a directory containing public certificates of a
# Certificate Authority (usually managed within Active Directory and distributed
# via Group Policy). The directory and certificates must be readable by the
# sft-gatewayd user and the certificates must be PEM encoded. Subdirectories are
# not checked.
#  TrustedCAsDir: /etc/sft/trusted-ldap-certs/

# ----------------------------------------
RDP:
# RDP
# These options control how the gateway manages RDP sessions. To accept any RDP
# connections, you must enable either TrustedCAsDir or
# DangerouslyIgnoreServerCertificates.
# ----------------------------------------
# Enables RDP functionality in the gateway. Disabled by default as RDP
# requires extra configuration.
  Enabled: true

# Restricts the gateway from validating server certificates when connecting to
# an RDP host. This flag is dangerous in non-test environments, but may be
# required if the RDP host has any self-signed certificates.
  DangerouslyIgnoreServerCertificates: true

# Specifies the path to a directory containing public certificates signed by a
# Certificate Authority (usually managed within Active Directory and distributed
# via Group Policy). The directory and certificates must be readable by the
# sft-gatewayd user and the certificates must be PEM encoded. Subdirectories are
# not checked.
#  TrustedCAsDir: /etc/sft/trusted-rdp-certs/

# Controls the number of concurrent RDP sessions allowed by the gateway. Users
# are unable to connect after the gateway reaches this value.
#  MaximumActiveSessions: 20

# Controls the log level of RDP-internal logs. These messages are useful when
# diagnosing issues, but might clutter logs. Set to false to label all internal
# RDP log messages as debug.
#  VerboseLogging: true

# ----------------------------------------
# Session Capture
# ----------------------------------------
# Specifies thresholds to sign and flush logs for an active session.
# The flush interval must include a time unit (ms, s, m, h)
# The buffer size is in bytes.
#SessionLogFlushInterval: 10s
#SessionLogMaxBufferSize: 262144

#Specifies the log file name prefix format. The format string annotations refer to the options that the customer provided:
LogFileNameFormats:
  SSHRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"
  RDPRecording: "{{.Protocol}}~{{.StartTime}}~{{.TeamName}}~{{.ProjectName}}~{{.ServerName}}~{{.Username}}~"

# Variables are placed between double brackets and start with a period ( {{.Example}} ). The following variables are available:
# - StartTime: the time when the session recording starts in ISO 8601 standard format, e.g. "20060102T150405.9999"
# - Protocol: the connection protocol. e.g. "ssh", "rdp".
# - TeamName: the team name of current user
# - ProjectName: the name of the project which the target server belongs to 
# - ServerName: the hostname of the target server client connected to
# - UserName: the name of current user
# Note: The gateway will always append a TraceID suffix to the generated filename to enforce uniqueness

# Specifies a temp directory to store SSH session logs before upload.
#SessionLogTempStorageDirectory: "/tmp"

# Specifies where to store finalized session logs. Sessions can be stored as a
# local file or in an AWS or GCS bucket. You can specify multiple destinations.
# Valid types include: file, s3, gcs
# Example Local Storage:
#LogDestinations:
#  - Type: file
#    LogDir: /var/log/sft/sessions
#  - Type: file
#    LogDir: c:\Windows\system32\config\systemprofile\AppData\Local\ScaleFT\sft-gatewayd

# Example AWS Storage:
#LogDestinations:
#  - Type: s3
#    Bucket: BUCKET-NAME
#    Region: US-EAST-1
#    # Use of ec2 instance IAM Role credentials for s3 bucket access is recommended
#    # To use ec2 instance IAM Role credentials leave Profile, AccessKeyId, SecretKey and SessionToken BLANK
#    # Specify Profile for shared credentials
#    Profile: AWS-PROFILE-NAME
#    # Specify AccessKeyId, SecretKey, and SessionToken for static credentials
#    AccessKeyId: SECRET
#    SecretKey: SECRET
#    SessionToken: SECRET

# Example GCS Storage:
#LogDestinations:
#  - Type: gcs
#    Bucket: bucket-name
#    # Supply one of CredentialsFile or CredentialsJSON (or none to use instance credentials
#    CredentialsFile: /path/to/cred/file
#    CredentialsJSON: |
#       {
#          "some": "value",
#          "in": "json"
#       }
EEOFF

sudo service sft-gatewayd restart

echo "Install Server Tools"
sudo mkdir -p /var/lib/sftd
echo ${oktapam_server_enrollment_token.opa-gateway-enrollment-token.token} > /var/lib/sftd/enrollment.token
echo "CanonicalName: opa-gateway-${local.timestamp}" > /etc/sft/sftd.yaml
sudo apt-get update
sudo apt-get install -y scaleft-server-tools

echo "Install RDP Session Capture Rendering Software"
sudo apt-get install -y scaleft-rdp-transcoder

cd /etc/sft/
tee aws_convertlogs.sh <<EOFF
#!/bin/bash -x
#Watch for new session logs and convert them to asciinema (ssh) and mkv (rdp).
WATCHPATH="/var/log/sft/sessions"
DESTPATH="/mnt/aws/${aws_s3_bucket.opa-s3-bucket-session-replay.bucket}"
process-logs-ssh(){
sudo sft session-logs export --insecure --format asciinema --output "\$DESTPATH"/"\$file".cast "\$WATCHPATH"/"\$file"
}
process-logs-rdp(){
sudo sft session-logs export --insecure --format mkv --output "\$DESTPATH"/"\$file".mkv "\$WATCHPATH"/"\$file"
}
inotifywait -m "\$WATCHPATH" -e create 2>/dev/null |
while read dirpath action file; do
    if [[ \$file == *ssh~* ]]; then
            echo "ssh session capture found"
            echo "starting conversion process"
            process-logs-ssh
            echo "ssh session converted"
    elif [[ \$file == *rdp~* ]]; then
            echo "rdp session capture found"
            echo" starting conversion process"
            process-logs-rdp
            echo "rdp session converted"
    else
            echo "skipping unknown file type \$file"
    fi
done
EOFF

sudo chmod +x aws_convertlogs.sh
sudo chmod 777 /var/log/sft/sessions/

echo "Install and Configure Dependancies"
sudo apt-get update
sudo apt install s3fs awscli inotify-tools scaleft-client-tools -y
sudo mkdir -p /mnt/aws/${aws_s3_bucket.opa-s3-bucket-session-replay.bucket}
sudo chmod 777 /mnt/aws/${aws_s3_bucket.opa-s3-bucket-session-replay.bucket}

cat > /etc/fuse.conf << ___EOF___
user_allow_other
___EOF___

echo "Create Service"
sudo touch /etc/systemd/system/aws_convertlogs.service
cat > /etc/systemd/system/aws_convertlogs.service << __EOF__
[Unit]
Description=Watch for new ASA session logs and convert then.

[Service]
ExecStart=/etc/sft/aws_convertlogs.sh
Restart=always
RestartSec=5s

[Install]
WantedBy=multi-user.target
__EOF__

sudo systemctl enable aws_convertlogs.service

echo "Mount S3 Bucket using S3FS"
sudo s3fs -o allow_other,iam_role=${aws_iam_role.opa-utils-iam-role.name},endpoint=${aws_s3_bucket.opa-s3-bucket-session-replay.region},url="https://s3-${aws_s3_bucket.opa-s3-bucket-session-replay.region}.amazonaws.com" ${aws_s3_bucket.opa-s3-bucket-session-replay.bucket} /mnt/aws/${aws_s3_bucket.opa-s3-bucket-session-replay.bucket}
echo "Add to fstab so it mounts after a reboot"
echo "s3fs#${aws_s3_bucket.opa-s3-bucket-session-replay.bucket} /mnt/aws/${aws_s3_bucket.opa-s3-bucket-session-replay.bucket} fuse _netdev,allow_other,iam_role=${aws_iam_role.opa-utils-iam-role.name},endpoint=${aws_s3_bucket.opa-s3-bucket-session-replay.region},url="https://s3-${aws_s3_bucket.opa-s3-bucket-session-replay.region}.amazonaws.com" 0 0" >> /etc/fstab
reboot
sudo s3fs -o allow_other,iam_role=${aws_iam_role.opa-utils-iam-role.name},endpoint=${aws_s3_bucket.opa-s3-bucket-session-replay.region},url="https://s3-${aws_s3_bucket.opa-s3-bucket-session-replay.region}.amazonaws.com" ${aws_s3_bucket.opa-s3-bucket-session-replay.bucket} /mnt/aws/${aws_s3_bucket.opa-s3-bucket-session-replay.bucket}

EOF

  tags = {
    Name = "opa-gateway-${local.timestamp}"
    Project = "opa-terraform"
  }

    network_interface {
    network_interface_id = aws_network_interface.opa-gw-interface.id
    device_index         = 0
  }
}

// AWS - Create OPA-Gateway Security Group
// AWS - AssumeRole Credentials
resource "aws_security_group" "opa-gateway" {
  provider = aws.opa-aws-build
  name        = "opa-gateway"
  description = "Ports required for OPA gateway"
  vpc_id      = aws_vpc.opa-vpc.id

  ingress {
    description      = "TCP 7234"
    from_port        = 7234
    to_port          = 7234
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

   ingress {
    description      = "TCP 22"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "opa-gateway"
    Project = "opa-terraform"
  }
}

// Local - Create Ansible Variables File used for Domain Controller Configuration
resource "local_file" "ansible_vars_tf" {
  content  = <<-DOC
windows_domain_controller_info:
  domain_name: ${var.domain_name}
  domain_admin_password: ${var.windows_password}
  domain_admin_user: ${var.windows_username}@${var.domain_name}
  safe_mode_password: ${var.windows_password}
  state: domain_controller
certificate_info:
  win_cert_dir: C:\
  local_cert_dir: ../../temp/certs/
  ss_file_name: opa_ss.cer
  DOC
  filename = "ansible/vars/vars.yml"
}

// AWS - Create OPA-Domain-Controller
// AWS - AssumeRole Credentials
resource "aws_instance" "opa-domain-controller" {
  provider = aws.opa-aws-build
  ami           = data.aws_ami.windows.id
  instance_type = "t2.medium"
  key_name      = var.aws_key_pair
  
  tags = {
    Name        = "opa-domain-controller"
    Project     = "opa-terraform"
  }

  user_data = <<EOF
  <powershell>
  $admin = [adsi]("WinNT://./${var.windows_username}, user")
  $admin.PSBase.Invoke("SetPassword", "${var.windows_password}")
  Invoke-Expression ((New-Object System.Net.Webclient).DownloadString('https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1'))
  Enable-WSManCredSSP -Role Server -Force
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  Install-PackageProvider -Name NuGet -Force
  Install-Module PowerShellGet -AllowClobber -Force
  </powershell>
  EOF

  provisioner "local-exec" {
    working_dir = "ansible"
    command     = "sleep 120;cp hosts.default hosts; sed -i '' -e 's/USERNAME/${var.windows_username}/g' -e 's/PASSWORD/${var.windows_password}/g' -e 's/PUBLICIP/${aws_instance.opa-domain-controller.public_ip}/g' hosts;ansible-playbook -v -i hosts playbooks/windows_dc.yml"
  }

  network_interface {
    network_interface_id = aws_network_interface.opa-dc-interface.id
    device_index         = 0
  }
}

// AWS - Create OPA-Domain-Controller Security Group
// AWS - AssumeRole Credentials
resource "aws_security_group" "opa-domain-controller" {
  provider = aws.opa-aws-build
  name        = "opa-domain-controller"
  description = "Ports required for OPA Domain Controller"
  vpc_id      = aws_vpc.opa-vpc.id
  
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

    description = "Allow incoming RDP connections"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32"]
    description = "Allow incoming TCP DNS connections"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32"]
    description = "Allow incoming UDP DNS connections"
  }

  ingress {
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32"]
    description = "Allow incoming TCP LDAP connections"
  }

  ingress {
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32"]
    description = "Allow incoming TCP LDAPS connections"
  }

   ingress {
    from_port   = 5986
    to_port     = 5986
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming WinRM connections"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "opa-domain-controller"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Linux-Target
// AWS - AssumeRole Credentials
resource "aws_instance" "opa-linux-target" {
  provider = aws.opa-aws-build
  ami                           = data.aws_ami.ubuntu.id
  instance_type                 = "t2.micro"
  key_name                      = var.aws_key_pair
  user_data_replace_on_change   = true
  user_data                     = <<EOF
#!/bin/bash
echo "Retrieve information about new packages"
sudo apt-get update
sudo apt-get install -y curl

echo "Stable Branch"
echo "Add APT Key"
curl https://dist.scaleft.com/GPG-KEY-OktaPAM-2023 | gpg --dearmor | sudo cat >/usr/share/keyrings/oktapam-2023-archive-keyring.gpg
echo "Create List"
printf "deb [signed-by=/usr/share/keyrings/oktapam-2023-archive-keyring.gpg] https://dist.scaleft.com/repos/deb focal okta" | sudo tee /etc/apt/sources.list.d/oktapam-stable.list > /dev/null
sudo apt-get update

echo "Install Server Tools"
sudo mkdir -p /var/lib/sftd
sudo mkdir -p /etc/sft
echo ${oktapam_server_enrollment_token.opa-linux-enrollment-token.token} > /var/lib/sftd/enrollment.token
echo "CanonicalName: opa-linux-target" | sudo tee /etc/sft/sftd.yaml
echo "Labels:" >> /etc/sft/sftd.yaml
echo "  role: devops" >> /etc/sft/sftd.yaml
echo "  env: staging" >> /etc/sft/sftd.yaml
sudo apt-get install scaleft-server-tools scaleft-client-tools
EOF
  
  tags = {
    Name        = "opa-linux-target"
    Project     = "opa-terraform"
  }

  network_interface {
    network_interface_id = aws_network_interface.opa-linux-target-interface.id
    device_index         = 0
  }
}

// AWS - Create OPA-Linux-Target Security Group
// AWS - AssumeRole Credentials
resource "aws_security_group" "opa-linux-target" {
  provider = aws.opa-aws-build
  name        = "opa-linux-target"
  description = "Ports required for OPA Linux Target"
  vpc_id      = aws_vpc.opa-vpc.id
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32"]
    description = "Allow incoming SSH connections"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "opa-linux-target"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Linux-Target-2
// AWS - AssumeRole Credentials
resource "aws_instance" "opa-linux-target-2" {
  provider = aws.opa-aws-build
  ami                           = data.aws_ami.ubuntu.id
  instance_type                 = "t2.micro"
  key_name                      = var.aws_key_pair
  user_data_replace_on_change   = true
  user_data                     = <<EOF
#!/bin/bash
echo "Retrieve information about new packages"
sudo apt-get update
sudo apt-get install -y curl

echo "Stable Branch"
echo "Add APT Key"
curl https://dist.scaleft.com/GPG-KEY-OktaPAM-2023 | gpg --dearmor | sudo cat >/usr/share/keyrings/oktapam-2023-archive-keyring.gpg
echo "Create List"
printf "deb [signed-by=/usr/share/keyrings/oktapam-2023-archive-keyring.gpg] https://dist.scaleft.com/repos/deb focal okta" | sudo tee /etc/apt/sources.list.d/oktapam-stable.list > /dev/null
sudo apt-get update

echo "Install Server Tools"
sudo mkdir -p /var/lib/sftd
sudo mkdir -p /etc/sft
echo ${oktapam_server_enrollment_token.opa-linux-enrollment-token.token} > /var/lib/sftd/enrollment.token
echo "CanonicalName: opa-linux-target-2" | sudo tee /etc/sft/sftd.yaml
echo "Labels:" >> /etc/sft/sftd.yaml
echo "  role: devops" >> /etc/sft/sftd.yaml
echo "  env: staging" >> /etc/sft/sftd.yaml
sudo apt-get install scaleft-server-tools
EOF
  
  tags = {
    Name        = "opa-linux-target-2"
    Project     = "opa-terraform"
  }

  network_interface {
    network_interface_id = aws_network_interface.opa-linux-target-2-interface.id
    device_index         = 0
  }
}

// AWS - Create OPA-Linux-Target-2 Security Group
// AWS - AssumeRole Credentials
resource "aws_security_group" "opa-linux-target-2" {
  provider = aws.opa-aws-build
  name        = "opa-linux-target-2"
  description = "Ports required for OPA Linux Target 2"
  vpc_id      = aws_vpc.opa-vpc.id
  
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32", "${aws_instance.opa-linux-target.private_ip}/32", "${aws_instance.opa-linux-target.public_ip}/32"]
    description = "Allow incoming SSH connections"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "opa-linux-target-2"
    Project = "opa-terraform"
  }
}

// AWS - Create OPA-Windows-Target
// AWS - AssumeRole Credentials
resource "aws_instance" "opa-windows-target" {
  provider = aws.opa-aws-build
  ami = data.aws_ami.windows.id
  instance_type = "t2.micro"
  key_name = var.aws_key_pair
  user_data_replace_on_change = true
  user_data = <<EOF
<script>
mkdir C:\Windows\System32\config\systemprofile\AppData\Local\scaleft
echo CanonicalName: opa-windows-target > C:\Windows\System32\config\systemprofile\AppData\Local\scaleft\sftd.yaml
echo ${oktapam_server_enrollment_token.opa-windows-enrollment-token.token}  > C:\windows\system32\config\systemprofile\AppData\Local\scaleft\enrollment.token
msiexec /qb /I https://dist.scaleft.com/server-tools/windows/latest/ScaleFT-Server-Tools-latest.msi
net stop scaleft-server-tools && net start scaleft-server-tools
</script>
  EOF
  
  tags = {
    Name        = "opa-windows-target"
    Project     = "opa-terraform"
  }

  network_interface {
    network_interface_id = aws_network_interface.opa-windows-target-interface.id
    device_index         = 0
  }
}

// AWS - Create OPA-Windows-Target Security Group
// AWS - AssumeRole Credentials
resource "aws_security_group" "opa-windows-target" {
  provider = aws.opa-aws-build
  name        = "opa-windows-target"
  description = "Ports required for OPA Windows Target"
  vpc_id      = aws_vpc.opa-vpc.id
  
  ingress {
    from_port   = 4421
    to_port     = 4421
    protocol    = "tcp"
    cidr_blocks = ["${aws_instance.opa-gateway.private_ip}/32", "${aws_instance.opa-gateway.public_ip}/32"]
    description = "Allow incoming Broker port connections"
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = "opa-windows-target"
    Project = "opa-terraform"
  }
}

// OPA - Creating gateway is not supported. Get the gateway id using datasource
data "oktapam_gateways" "opa-gateway" {
  contains = "opa-gateway-${local.timestamp}" # Filter gateway that contains given name
depends_on = [
  aws_instance.opa-domain-controller
]
}

// OPA - Create Active Directory Connection
resource "oktapam_ad_connection" "opa-ad-connection" {
  name                     = "opa-ad-connection"
  gateway_id               = data.oktapam_gateways.opa-gateway.gateways[0].id
  domain                   = var.domain_name
  service_account_username = "${var.windows_username}@${var.domain_name}"
  service_account_password = var.windows_password
  use_passwordless         = true
  certificate_id           = oktapam_ad_certificate_request.opa_ad_self_signed_cert.id
  #domain_controllers       = ["dc1.com", "dc2.com"] //Optional: DC used to query the domain
}

data "oktapam_project" "ad-domain-joined-project" {
  name = "opa-domain-joined"
}

// OPA - Create AD Joined Server Discovery Task
resource "oktapam_ad_task_settings" "opa_ad_task_settings" {
  connection_id            = oktapam_ad_connection.opa-ad-connection.id
  name                     = "opa-ad-job"
  is_active                = true
  frequency                = 1 # Every 12 hours Note: If 24 hours then start_hour_utc is required
  host_name_attribute      = "dNSHostName"
  access_address_attribute = "dNSHostName"
  os_attribute             = "operatingSystem"
  run_test                 = true
  rule_assignments {
    base_dn           = "ou=Domain Controllers,dc=${var.domain_name},dc=com"
    ldap_query_filter = "(objectCategory=Computer)"
    project_id        = oktapam_project.opa-domain-joined.project_id
    priority          = 1
  }
}