#!/bin/bash

# Set Environment Variable to Fix Ansible Fork Issue
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

# Set the location of the Terraform executable
#terraform=/usr/local/bin/terraform

# Navigate to the directory containing the Terraform configuration files
#cd /path/to/terraform/config

# Try to detect the location of the Terraform executable
terraform=$(which terraform)

# If Terraform is not installed or the location cannot be found, display an error message and exit
if [ -z "$terraform" ]; then
  echo "Terraform not found. Please install Terraform and ensure it is in your PATH."
  exit 1
fi

# Navigate to the directory containing the Terraform configuration files
cd "$(dirname "$($terraform version -json | jq -r '.terraform_version')")"

# Function to log messages
log() {
  local timestamp=$(date +"%Y-%m-%d %T")
  local log_message=$1
  echo "[${timestamp}] ${log_message}"
  echo "[${timestamp}] ${log_message}" >> script.log
}


usage() {
  echo "Usage: $0 [-deploy | -destroy] [-a] [-u] [-k]"
  echo "Options:"
  echo "  -deploy     Deploy the OPA Demo environment."
  echo "  -destroy    Destroy the OPA Demo environment."
  echo "  -a          Deploy AD Joined component."
  echo "  -u          Deploy OPA Utils component."
  echo "  -k          Deploy OPA Kubernetes component."
  exit 1
}

deploy=false
destroy=false
deploy_ad_joined=false
deploy_utils=false
deploy_kubernetes=false

while [ $# -gt 0 ]; do
  case "$1" in
    -deploy)
      deploy=true
      ;;
    -destroy)
      destroy=true
      ;;
    -a)
      deploy_ad_joined=true
      ;;
    -u)
      deploy_utils=true
      ;;
    -k)
      deploy_kubernetes=true
      ;;
    *)
      usage
      ;;
  esac
  shift
done

if ! $deploy && ! $destroy; then
  usage
fi

if $deploy && $destroy; then
  log "Both -deploy and -destroy options cannot be specified simultaneously."
  usage
fi

if $deploy; then
  log "************************"
  log "Starting OPA Demo build"
  log "Please note the base build takes around 5 minutes to complete."
  log "************************"
  sleep 3 # Waits 3 seconds.

  cd setup
  $terraform init
  log "************************"
  log "Deploying setup components required to complete full deployment."
  log "************************"
  $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  log "************************"
  log "Setup phase complete!"
  log "************************"
  log "Waiting for 20 seconds to ensure AWS Roles and Policies are available"
  sleep 20 # Waits 20 seconds.
  log "************************"
  log "Starting build phase."
  log "************************"
  cd base
  $terraform init
  log "************************"
  log "Deploying main Okta demo environment including Okta and AWS components."
  log "************************"
  sleep 3 # Waits 3 seconds.
  $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  log "************************"
  log "Build phase complete!"
  log "But before you go..."
  log "************************"

  if $deploy_ad_joined; then
    log "************************"
    log "Great! Starting AD Joined deployment."
    log "Please note the AD Joined deployment takes around 15 minutes to complete."
    log "************************"
    cd ad-joined
    $terraform init
    $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
    cd ..
    log "************************"
    log "AD Joined deployment complete!"
    log "************************"
  else
    log "************************"
    log "Boo! AD Joined not deployed."
    log "************************"
  fi

  if $deploy_utils; then
    log "************************"
    log "Great! Starting OPA Utils deployment."
    log "Please note the OPA Utils deployment takes around 5 minutes to complete."
    log "************************"
    cd utils
    $terraform init
    $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
    cd ..
    log "************************"
    log "OPA Utils deployment complete!"
    log "************************"
  else
    log "************************"
    log "Boo! OPA Utils not deployed."
    log "************************"
  fi

  if $deploy_kubernetes; then
    log "************************"
    log "Great! Starting OPA Kubernetes deployment."
    log "Please note the OPA Kubernetes deployment takes around 20 minutes to complete."
    log "************************"
    cd kubernetes
    $terraform init
    $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
    cd ..
    log "************************"
    log "OPA Kubernetes deployment complete!"
    log "************************"
  else
    log "************************"
    log "Boo! OPA Kubernetes not deployed."
    log "************************"
  fi

  log "************************"
  log "Deployment is fully complete. Enjoy your new environment and don't forget to destroy it when you are finished!"
  log "************************"

elif $destroy; then
  log "************************"
  log "Destroying OPA Kubernetes, if it exists."
  log "************************"
  cd kubernetes
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  log "************************"
  log "Destroying OPA Utils, if it exists."
  log "************************"
  cd utils
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"
  cd ..

  log "************************"
  log "Destroying AD Joined, if it exists."
  log "************************"
  cd ad-joined
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"
  cd ..

  log "************************"
  log "Destroying OPA Base, if it exists."
  log "************************"
  cd base
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  log "************************"
  log "Destroying OPA Setup, if it exists."
  log "************************"
  cd setup
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  log "************************"
  log "OPA demo environment destroyed."
  log "************************"
fi
