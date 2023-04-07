// Initial Configuration
// Required Terraform Providers

terraform {
  required_providers {
    okta = {
      source = "okta/okta"
      version = "3.39.0"
    }
    aws = {
      source = "hashicorp/aws"
      version = "4.26.0"
    }
    local = {
      source = "hashicorp/local"
      version = "2.2.3"
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

  // Amazon Web Services
provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

// Demo Setup

// Create OPA Utils OAuth application
resource "okta_app_oauth" "opa-utils-app" {
  label                      = "OPA Utils"
  type                       = "web"
  grant_types                = ["authorization_code"]
  response_types             = ["code"]
  // Okta requires at least one redirect URI to create an app
  redirect_uris              = ["myapp://callback"]
  // Since Okta forces us to create it with a redirect URI we have to ignore future changes, they will be detected as config drift.
  lifecycle {
    ignore_changes           = [redirect_uris]
  }
}

resource "okta_app_oauth_redirect_uri" "opa-utils-app-redirect" {
  app_id = okta_app_oauth.opa-utils-app.id
  uri    = "http://${aws_elastic_beanstalk_environment.eb-opa-utils-env.cname}/authorization-code/callback"
}

// Create OPA Util Bookmark application
resource "okta_app_bookmark" "opa-utils-bookmark-app" {
  label  = "OPA Utils"
  url    = "http://${aws_elastic_beanstalk_environment.eb-opa-utils-env.cname}"
}

// Okta - Assign everyone to OPA Utils bookmark application
resource "okta_app_group_assignments" "okta-everyone-opa-utils-bookmark-assignment" {
  app_id   = okta_app_bookmark.opa-utils-bookmark-app.id
  group {
    id = data.okta_everyone_group.okta-everyone.id
    priority = 1
  }
}

// Lookup Okta Everyone Group ID
data "okta_everyone_group" "okta-everyone" {}

// Okta - Assign everyone to OPA Utils
resource "okta_app_group_assignments" "okta-everyone-opa-utils-assignment" {
  app_id   = okta_app_oauth.opa-utils-app.id
  group {
    id = data.okta_everyone_group.okta-everyone.id
    priority = 1
  }
}

// Look Up Session Replay Bucket Name
data "local_file" "opa-s3-bucket-session-replay-name" {
  filename = "../base/opa-s3-bucket-name.txt"
}

// Look Up Session Replay Bucket Region
data "local_file" "opa-s3-bucket-session-replay-region" {
  filename = "../base/opa-s3-bucket-region.txt"
}

// Create AWS S3 Bucket
resource "aws_s3_bucket" "opa-s3-bucket" {
  bucket = "opa-utils.0.0.2.bucket${random_string.random-string.result}"
  force_destroy = true
}

resource "null_resource" "download-opa-utils" {
  provisioner "local-exec" {
    command = "curl -OL https://github.com/Okta-PAM-Resource-Kit/pam-utilities/releases/download/utils/pam-utilities.zip"
  }
  provisioner "local-exec" {
    when    = destroy
    command = "rm pam-utilities.zip"
  }
}

// Upload OPA Utils Source to AWS S3 Bucket
resource "aws_s3_object" "opa-s3-bucket-source-upload" {
  bucket = aws_s3_bucket.opa-s3-bucket.id
  key    = "beanstalk/pam-utilities.zip"
  source = "pam-utilities.zip"

  depends_on = [
    resource.null_resource.download-opa-utils
  ]
}

// Create Elastic Beanstalk Application
resource "aws_elastic_beanstalk_application" "eb-opa-utils-app" {
  name        = "opa-utils-app"
  description = "opa-utils-app"
}

// Create Random String
resource "random_string" "random-string" {
  length           = 8
  special          = false
  upper            = false
}

data "aws_elastic_beanstalk_solution_stack" "ebs_solution_stack_latest" {
  most_recent = true
  name_regex = "64bit Amazon Linux (.*) running Node.js (.*)$"
}

// Look Up OPA Utils Role Name
data "local_file" "opa-utils-instance-profile-name" {
  filename = "../base/opa-utils-instance-profile-name.txt"
}

// Create Elastic Beanstalk Environment
resource "aws_elastic_beanstalk_environment" "eb-opa-utils-env" {
  name                = "opa-utils-env"
  application         = aws_elastic_beanstalk_application.eb-opa-utils-app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.ebs_solution_stack_latest.name
  cname_prefix = "opa-utils${random_string.random-string.result}"
  version_label = "${aws_elastic_beanstalk_application.eb-opa-utils-app.name}"
  setting {
        namespace = "aws:autoscaling:launchconfiguration"
        name      = "IamInstanceProfile"
        value     = "${data.local_file.opa-utils-instance-profile-name.content}"  
      }
  setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "OKTA_OAUTH2_ISSUER"
        value     = "https://${var.okta_org}.${var.okta_environment}/oauth2/default"
      }
  setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "OKTA_OAUTH2_CLIENT_ID_WEB"
        value     = "${okta_app_oauth.opa-utils-app.client_id}"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "OKTA_OAUTH2_CLIENT_SECRET_WEB"
        value     = "${okta_app_oauth.opa-utils-app.client_secret}"
    }
  setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "SESSION_SECRET"
        value     = "wertyuikmnbv"
    }
  setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "SCOPES"
        value     = "openid profile email"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "BASE_URI"
        value     = "http://opa-utils${random_string.random-string.result}.${var.aws_region}.elasticbeanstalk.com"
    }
  setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "TOKEN_AUD"
        value     = "api://default"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "AWS_ACCESS_KEY_ID"
        value     = "${var.aws_access_key}"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "AWS_SECRET_ACCESS_KEY"
        value     = "${var.aws_secret_key}"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "GCP_PROJECT_ID"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "GCP_EMAIL"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "GCP_PRIVATE"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "AWS_BUCKET"
        value     = "${data.local_file.opa-s3-bucket-session-replay-name.content}"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "AWS_REGION"
        value     = "${data.local_file.opa-s3-bucket-session-replay-region.content}"
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "GCP_BUCKET"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "ASA_ID"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "ASA_SECRET"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "ASA_TEAM"
        value     = ""
    }
    setting {
        namespace = "aws:elasticbeanstalk:application:environment"
        name      = "ASA_PROJECT_NAME"
        value     = ""
    }
  setting {
        namespace = "aws:elasticbeanstalk:environment"
        name = "LoadBalancerType"
        value = "application"
  }
  setting {
        namespace = "aws:autoscaling:launchconfiguration"
        name = "DisableIMDSv1"
        value = "true"
  }

  depends_on = [
    aws_elastic_beanstalk_application.eb-opa-utils-app,
    aws_elastic_beanstalk_application_version.eb-opa-utils-app-version
  ]
}

// Create Application Version
resource "aws_elastic_beanstalk_application_version" "eb-opa-utils-app-version" {
  name        = "opa-utils-app"
  application = "opa-utils-app"
  description = "opa-utils-app"
  bucket      = aws_s3_bucket.opa-s3-bucket.id
  key         = aws_s3_object.opa-s3-bucket-source-upload.id
}