// AWS Variables

variable "aws_region" {
  type    = string
  sensitive   = true
}

variable "aws_access_key" {
  type    = string
  sensitive   = true
}

variable "aws_secret_key" {
  type    = string
  sensitive   = true
}

variable "windows_username" {
  type    = string
  sensitive   = true
}

variable "windows_password" {
  type    = string
  sensitive   = true
}

variable "domain_name" {
  type = string
  sensitive   = true
}

variable "aws_key_pair" {
  type = string
  sensitive   = true
}

variable "aws_role_arn" {
  type = string
  sensitive = true
}

// Okta Variables

variable "okta_org" {
  type = string
  sensitive   = true
}

variable "okta_admintoken" {
  type = string
  sensitive   = true
}

variable "okta_environment" {
  type    = string
  sensitive   = true
  default = "oktapreview.com"
}

variable "okta_demouser_id" {
  type = string
  sensitive   = true
}

variable "okta_asa_app_id" {
  type = string
  sensitive   = true
}

// OPA Variables

variable "opa_key" {
  type = string
  sensitive   = true
}

variable "opa_secret" {
  type = string
  sensitive   = true
}

variable "opa_team" {
  type    = string
  sensitive   = true
}
