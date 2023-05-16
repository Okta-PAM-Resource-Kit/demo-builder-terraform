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


// General - Timestamp
locals {
  timestamp = formatdate("DDMMYYYY", timestamp())
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

// Look Up AWS Subnet ID
data "local_file" "aws-subnet-id" {
  filename = "../base/aws-subnet-id.txt"
}

// AWS - Create OPA-Domain-Controller Network Interface
// AWS - AssumeRole Credentials
resource "aws_network_interface" "opa-dc-interface" {
  provider = aws.opa-aws-build
  subnet_id   = data.local_file.aws-subnet-id.content
  private_ips = ["172.16.10.150"]
  security_groups = [aws_security_group.opa-domain-controller.id]

 tags = {
    Name = "opa-dc-interface"
    Project = "opa-terraform"
  }
}

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

// Look Up AWS VPC
data "local_file" "aws-vpc" {
  filename = "../base/aws-vpc.txt"
}

// Look Up GW Public IP
data "local_file" "gw-public" {
  filename = "../base/gw-public.txt"
}

// Look Up GW Private IP
data "local_file" "gw-private" {
  filename = "../base/gw-private.txt"
}

// AWS - Create OPA-Domain-Controller Security Group
// AWS - AssumeRole Credentials
resource "aws_security_group" "opa-domain-controller" {
  provider = aws.opa-aws-build
  name        = "opa-domain-controller"
  description = "Ports required for OPA Domain Controller"
  vpc_id      = data.local_file.aws-vpc.content
  
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
    cidr_blocks = ["${data.local_file.gw-private.content}/32", "${data.local_file.gw-public.content}/32"]
    description = "Allow incoming TCP DNS connections"
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["${data.local_file.gw-private.content}/32", "${data.local_file.gw-public.content}/32"]
    description = "Allow incoming UDP DNS connections"
  }

  ingress {
    from_port   = 389
    to_port     = 389
    protocol    = "tcp"
    cidr_blocks = ["${data.local_file.gw-private.content}/32", "${data.local_file.gw-public.content}/32"]
    description = "Allow incoming TCP LDAP connections"
  }

  ingress {
    from_port   = 636
    to_port     = 636
    protocol    = "tcp"
    cidr_blocks = ["${data.local_file.gw-private.content}/32", "${data.local_file.gw-public.content}/32"]
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
    base_dn           = "ou=Domain Controllers,dc=opa-domain,dc=com"
    ldap_query_filter = "(objectCategory=Computer)"
    project_id        = oktapam_project.opa-domain-joined.project_id
    priority          = 1
  }
}