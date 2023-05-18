
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
  echo "Both -deploy and -destroy options cannot be specified simultaneously."
  usage
fi

if $deploy; then
  echo "************************"
  echo "Starting OPA Demo build"
  echo "Please note the base build takes around 5 minutes to complete."
  echo "************************"
  sleep 3 # Waits 3 seconds.

  cd setup
  $terraform init
  echo "************************"
  echo "Deploying setup components required to complete full deployment."
  echo "************************"
  $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  echo "************************"
  echo "Setup phase complete!"
  echo "************************"
  echo "Waiting for 20 seconds to ensure AWS Roles and Policies are available"
  sleep 20 # Waits 20 seconds.
  echo "************************"
  echo "Starting build phase."
  echo "************************"
  cd base
  $terraform init
  echo "************************"
  echo "Deploying main Okta demo environment including Okta and AWS components."
  echo "************************"
  sleep 3 # Waits 3 seconds.
  $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  echo "************************"
  echo "Build phase complete!"
  echo "But before you go..."
  echo "************************"

  if $deploy_ad_joined; then
    echo "************************"
    echo "Great! Starting AD Joined deployment."
    echo "Please note the AD Joined deployment takes around 15 minutes to complete."
    echo "************************"
    cd ad-joined
    $terraform init
    $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
    cd ..
    echo "************************"
    echo "AD Joined deployment complete!"
    echo "************************"
  else
    echo "************************"
    echo "Boo! AD Joined not deployed."
    echo "************************"
  fi

  if $deploy_utils; then
    echo "************************"
    echo "Great! Starting OPA Utils deployment."
    echo "Please note the OPA Utils deployment takes around 5 minutes to complete."
    echo "************************"
    cd utils
    $terraform init
    $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
    cd ..
    echo "************************"
    echo "OPA Utils deployment complete!"
    echo "************************"
  else
    echo "************************"
    echo "Boo! OPA Utils not deployed."
    echo "************************"
  fi

  if $deploy_kubernetes; then
    echo "************************"
    echo "Great! Starting OPA Kubernetes deployment."
    echo "Please note the OPA Kubernetes deployment takes around 20 minutes to complete."
    echo "************************"
    cd kubernetes
    $terraform init
    $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
    cd ..
    echo "************************"
    echo "OPA Kubernetes deployment complete!"
    echo "************************"
  else
    echo "************************"
    echo "Boo! OPA Kubernetes not deployed."
    echo "************************"
  fi

  echo "************************"
  echo "Deployment is fully complete. Enjoy your new environment and don't forget to destroy it when you are finished!"
  echo "************************"

elif $destroy; then
  echo "************************"
  echo "Destroying OPA Kubernetes, if it exists."
  echo "************************"
  cd kubernetes
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  echo "************************"
  echo "Destroying OPA Utils, if it exists."
  echo "************************"
  cd utils
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"
  cd ..

  echo "************************"
  echo "Destroying AD Joined, if it exists."
  echo "************************"
  cd ad-joined
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"
  cd ..

  echo "************************"
  echo "Destroying OPA Base, if it exists."
  echo "************************"
  cd base
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  echo "************************"
  echo "Destroying OPA Setup, if it exists."
  echo "************************"
  cd setup
  $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

  cd ..
  echo "************************"
  echo "OPA demo environment destroyed."
  echo "************************"
fi



# # ------------------ OLD Code Below ------------------

# #!/bin/bash

# # Set Environment Variable to Fix Ansible Fork Issue
# export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES

# # Set the location of the Terraform executable
# #terraform=/usr/local/bin/terraform

# # Navigate to the directory containing the Terraform configuration files
# #cd /path/to/terraform/config

# # Try to detect the location of the Terraform executable
# terraform=$(which terraform)

# # If Terraform is not installed or the location cannot be found, display an error message and exit
# if [ -z "$terraform" ]; then
#   echo "Terraform not found. Please install Terraform and ensure it is in your PATH."
#   exit 1
# fi

# # Navigate to the directory containing the Terraform configuration files
# cd "$(dirname "$($terraform version -json | jq -r '.terraform_version')")"

# # Prompt the user for action
# echo "************************"
# read -p "Do you want to deploy or destroy your OPA Demo? (deploy/destroy) " action

# # Conditionally execute the action
# if [ "$action" == "deploy" ]; then
# echo "************************"
# echo "Starting OPA Demo build"
# echo "Please note the base build takes around 5 minutes to complete."
# echo "************************"
# sleep 3 # Waits 3 seconds.

# cd setup
# $terraform init
# echo "************************"
# echo "Deploying setup components required to complete full deployment."
# echo "************************"
# $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"

# cd ..
# echo "************************"
# echo "Setup phase complete!"
# echo "************************"
# echo "Waiting for 20 seconds to ensure AWS Roles and Policies are available"
# sleep 20 # Waits 20 seconds.
# echo "************************"
# echo "Starting build phase."
# echo "************************"
# cd base
# $terraform init
# echo "************************"
# echo "Deploying main Okta demo environment including Okta and AWS components."
# echo "************************"
# sleep 3 # Waits 3 seconds.
# $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"

# cd ..
# echo "************************"
# echo "Build phase complete!"
# echo "But before you go..."
# echo "************************"

# echo "************************"
# # Do you want to deploy AD Joined?
# read -p "Do you want to deploy AD Joined? (yes/no) " answer
# # Conditionally apply the changes to the infrastructure
# if [ "$answer" == "yes" ]; then
# echo "************************"
#     echo "Great! Starting AD Joined deployment."
#     echo "Please note the AD Joined deployment takes around 15 minutes to complete."
#     echo "************************"
#     cd ad-joined
#     $terraform init
#     $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
#     cd ..
#     echo "************************"
#     echo "AD Joined deployment complete!"
#     echo "************************"
# else
#     echo "************************"
#     echo "Boo! AD Joined not deployed."
#     echo "************************"
# fi

# echo "************************"
# # Do you want to deploy OPA Utils?
# read -p "Do you want to deploy OPA Utils? (yes/no) " answer
# # Conditionally apply the changes to the infrastructure
# if [ "$answer" == "yes" ]; then
# echo "************************"
#     echo "Great! Starting OPA Utils deployment."
#     echo "Please note the OPA Utils deployment takes around 5 minutes to complete."
#     echo "************************"
#     cd utils
#     $terraform init
#     $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
#     cd ..
#     echo "************************"
#     echo "OPA Utils deployment complete!"
#     echo "************************"
# else
#     echo "************************"
#     echo "Boo! OPA Utils not deployed."
#     echo "************************"
# fi

# echo "************************"
# echo "One last question..."
# # Do you want to deploy OPA Kubernetes?
# read -p "Do you want to deploy OPA Kubernetes? (yes/no) " answer

# # Conditionally apply the changes to the infrastructure
# if [ "$answer" == "yes" ]; then
#     echo "************************"
#     echo "Great! Starting OPA Kubernetes deployment."
#     echo "Please note the OPA Kubernetes deployment takes around 20 minutes to complete."
#     echo "************************"
#     cd kubernetes
#     $terraform init
#     $terraform apply -auto-approve -var-file="../setup/terraform.tfvars"
#     cd ..
#     echo "************************"
#     echo "OPA Kubernetes deployment complete!"
#     echo "************************"
# else
#     echo "************************"
#     echo "Boo! OPA Kubernetes not deployed."
#     echo "************************"
# fi
# echo "************************"
# echo "Deplyment is fully complete. Enjoy your new environment and don't forget to destroy it when you are finished!"
# echo "************************"

# elif [ "$action" == "destroy" ]; then
# echo "************************"
#   echo "Destroying OPA Kubernetes, if it exists."
#   echo "************************"
#   cd kubernetes
#   $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

#   cd ..
#   echo "************************"
#   echo "Destroying OPA Utils, if it exists."
#   echo "************************"
#   cd utils
#   $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"
#   cd ..

#   echo "************************"
#   echo "Destroying AD Joined, if it exists."
#   echo "************************"
#   cd ad-joined
#   $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"
#   cd ..


#   echo "************************"
#   echo "Destroying OPA Base, if it exists."
#   echo "************************"
#   cd base
#   $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

#   cd ..
#   echo "************************"
#   echo "Destroying OPA Setup, if it exists."
#   echo "************************"
#   cd setup
#   $terraform destroy -auto-approve -var-file="../setup/terraform.tfvars"

#   cd ..
#   echo "************************"
#   echo "OPA demo environment destroyed."
#   echo "************************"
# else
#   # Invalid action
#   echo "************************"
#   echo "Invalid action specified."
#   echo "************************"
# fi