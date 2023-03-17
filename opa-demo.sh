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

# Prompt the user for action
echo "************************"
read -p "Do you want to deploy or destroy your OPA Demo? (deploy/destroy) " action

# Conditionally execute the action
if [ "$action" == "deploy" ]; then
echo "************************"
echo "Starting OPA Demo build"
echo "Please note the base build takes around 15 minutes to complete."
echo "************************"

cd setup
$terraform init
echo "************************"
echo "something here to let people know something is happening"
echo "************************"
$terraform apply -auto-approve
cd ..
echo "************************"
echo "Setup phase complete!"
echo "************************"

echo "************************"
echo "Starting build phase."
echo "************************"
cd base
$terraform init
echo "************************"
echo "something here to let people know something is happening"
echo "************************"
$terraform apply -auto-approve
cd ..
echo "************************"
echo "Build phase complete!"
echo "You now have a working OPA Demo!"
echo "But before you go..."
echo "************************"

echo "************************"
# Do you want to deploy OPA Utils?
read -p "Do you want to deploy OPA Utils? (yes/no) " answer
# Conditionally apply the changes to the infrastructure
if [ "$answer" == "yes" ]; then
echo "************************"
    echo "Great! Starting OPA Utils deployment."
    echo "Please note the OPA Utils deployment takes around 5 minutes to complete."
    echo "************************"
    cd utils
    $terraform init
    echo "************************"
    echo "something here to let people know something is happening"
    echo "************************"
    $terraform apply -auto-approve
    cd ..
    echo "************************"
    echo "OPA Utils deployment complete!"
    echo "************************"
else
    echo "************************"
    echo "Boo! OPA Utils not deployed."
    echo "************************"
fi

echo "************************"
echo "One last question..."
# Do you want to deploy OPA Kubernetes?
read -p "Do you want to deploy OPA Kubernetes? (yes/no) " answer

# Conditionally apply the changes to the infrastructure
if [ "$answer" == "yes" ]; then
    echo "************************"
    echo "Great! Starting OPA Kubernetes deployment."
    echo "Please note the OPA Kubernetes deployment takes around 20 minutes to complete."
    echo "************************"
    cd kubernetes
    $terraform init
    echo "************************"
    echo "something here to let people know something is happening"
    echo "************************"
    $terraform apply -auto-approve
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
echo "Deplyment is fully complete. Enjoy your new environment and don't forget to destroy it when you are finished!"
echo "************************"

elif [ "$action" == "destroy" ]; then
echo "************************"
  echo "Destroying OPA Kubernetes, if it exists."
  echo "************************"
  cd kubernetes
  $terraform destroy -auto-approve
  cd ..
  echo "************************"
  echo "Destroying OPA Utils, if it exists."
  echo "************************"
  cd utils
  $terraform destroy -auto-approve
  cd ..
  echo "************************"
  echo "Destroying OPA Base, if it exists."
  echo "************************"
  cd base
  $terraform destroy -auto-approve
  cd ..
  echo "************************"
  echo "Destroying OPA Setup, if it exists."
  echo "************************"
  cd setup
  $terraform destroy -auto-approve
  cd ..
  echo "************************"
  echo "OPA demo environment destroyed."
  echo "************************"
else
  # Invalid action
  echo "************************"
  echo "Invalid action specified."
  echo "************************"
fi