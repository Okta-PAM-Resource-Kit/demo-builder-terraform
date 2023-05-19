# Okta Privileged Access - Demo Setup

This repository will set up a fully working OPA demo environment. It leverages Terraform and Ansible to deploy and configure the environment.

This repository has been designed to be modular, this means that if you only need to deploy a single feature, like Kubernetes you can. Please read the instructions very carefully.

### Prerequisites

- Okta Demo Environment 
- OPA (ASA) Team integrated into your Okta Demo environment
- Ensure that your OPA Service Account is a member of the 'owners' group
- Note: For older ASA Teams please create the ASA application attributes as described here: https://help.okta.com/asa/en-us/Content/Topics/Adv_Server_Access/docs/ad-user-manage.htm
- Note: Please ensure that "Create Users", "Update Attributes" and "Deactivate Users" are enabled on your OPA Application within Okta.
- Note: Remove any existing OPA AD Joined Attributes from the Okta User Profile. These will be created automatically for you.

- OPA Client - Enrolled into your OPA Team with your Demo User
- RoyalTSX (macOS) (https://www.royalapps.com/ts/mac/download)
- Note: Open RoyalTSX, nagivate to Deafult Settings, right click on Remote Desktop and select Properties - Ensure 'TLS Encryption' is ticked.

- AWS Environment
- IAM User - Note this user only has the AssumeRole rights and rights to create IAM Roles and Policies.

    - Open IAM Console in AWS
    - Click: Users
    - Click: Add Users
    - Enter Name: opa-user
    - Click: Next
    - Select 'Attach Policies Directly'
    - Click: Create Policy - Note: New Tab Opens
    - Click: JSON
    - Paste the following and replace `XXX` with your AWS Account Number:

    ``` 
    {
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sts:AssumeRole",
                "iam:CreateInstanceProfile",
                "iam:DeleteInstanceProfile",
                "iam:GetRole",
                "iam:GetPolicyVersion",
                "iam:GetPolicy",
                "iam:RemoveRoleFromInstanceProfile",
                "iam:DeletePolicy",
                "iam:CreateRole",
                "iam:DeleteRole",
                "iam:AttachRolePolicy",
                "iam:AddRoleToInstanceProfile",
                "iam:CreatePolicy",
                "iam:ListInstanceProfilesForRole",
                "iam:DetachRolePolicy",
                "iam:ListPolicyVersions",
                "iam:ListAttachedRolePolicies",
                "iam:CreatePolicyVersion",
                "iam:ListRolePolicies",
                "iam:DeletePolicyVersion",
                "s3:ListBucket",
                "s3:GetObject",
                "s3:GetObjectVersion"
            ],
            "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": "sts:AssumeRole",
                "Resource": "arn:aws:iam::XXX:role/opa-build-role"
            }
        ]
    } 
    ``` 
    
    - Click: Next: Tags
    - Click: Next: Review
    - Enter Name: opa-assumerole
    - Click: Create Policy
    - Go Back to Create User Browser Tab
    - Click Refresh Icon
    - Filter: opa-assumerole
    - Select Policy
    - Click: Next
    - Click: Create User
    - Click opa-user
    - Click Security Credentials
    - Click: Create Access Key
    - Select: Local Code
    - Tick 'I understand the above recommendation and I was to process to create an access key'
    - Click: Next
    - Click: Create Access Key
    - Make a Note of Access Key and Access Secret for use later     

- AWS Key Pair in the correct region (https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html). This is only as a backup and will most likely never be required.
- Ensure you have space for 5 additional Elastic IPS and 3 VPCs

- Terraform CLI (https://learn.hashicorp.com/tutorials/terraform/install-cli)
- Ansible (https://formulae.brew.sh/formula/ansible) - For Domain Controller automation
- kubectl (https://kubernetes.io/docs/tasks/tools/) - For accessing EKS via CLI
- OpenLens (https://github.com/MuhammedKalkan/OpenLens/releases) - For accessing EKS via GUI

### Deployment

- Download the code locally into an accessible folder (eg; /users/daniel/opa-demo/)

- Navigate into the 'setup' directory
    - Rename 'terraform.example' to terraform.tfvars
    - Fill in all variables in 'terraform.tfvars'

- In your command line application of choice change into the top level directory of the code (eg; /users/daniel/opa-demo/)
- Type: `chmod +x opa-demo.sh` - only needs to be done once
- Type: `./opa-demo.sh ` to get usage information

Examples: 
`opa-demo.sh -deploy -a -u -k ` - Deploys base demo with AD Joined, Utils and Kubernetes
`opa-demo.sh` -deploy -u - Deploys base demo with only Utils


### Destroy

- In your command line application of choice change into the top level directory of the code (eg; /users/daniel/opa-demo/)
- Type: ./opa-demo.sh -destroy
- Follow the prompts

<!-- 
### Base Demo Deployment -  Runtime ~14m

Follow these steps to deploy standard OPA features.

- Download the code locally into an accessible folder
- Rename 'terraform.example' to terraform.tfvars
- Fill in all variables in 'terraform.tfvars'
- Open Terminal and change into the top level directory where the code resides. (Do not change into the Kubernetes directory)
- Run: `terraform init` - this will download and install all the required packages
- MacOS - Run: `export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`
- Run: `terraform apply` 
- Note: This can take around 15 minutes to fully deploy, so please be patient.

After you have completed the above steps you will have a standard working OPA Demo where you will be able to demo;

- Agent Based Server Management and Authentication
- AD Joined User Authentication
- Preauthorization
- Gateway Traversal

In order to save costs, please ensure that this environment has been destroyed when not in use. The beauty of Terraform is that is can be created very quickly again. To destroy the base deployment please run the following command:

- Run: `terraform destory`
- Note: After destruction please manually delete the opa-gateway from the Gateways menu as there is currently no API avaialble to manage this.

### Utilities (Session Capture) Deployment - Runtime ~5m

Follow these steps in order to deploy only the Utils features. 

Please note this section requires the Base Demo Deployment to be deployed as it relies heavily on the Gateway.

- Open Terminal and change into the Utils directory
- Rename 'terraform.example' to terraform.tfvars
- Fill in all variables in 'terraform.tfvars'
- Run: `terraform init` - this will download and install all the required packages
- Run: `terraform apply` 

After deployment is succesful, you should have an OPA Utils chiclet on your demonstration users dashboard within Okta. 

In order to save costs, please ensure that this environment has been destroyed when not in use. The beauty of Terraform is that is can be created very quickly again. To destroy the utils deployment please run the following command:

- Run: `terraform destory`

### Kubernetes Feature Deployment - Runtime ~18m

Follow these steps in order to deploy only the Kubernetes features. 

- Open Terminal and change into the Kubernetes directory
- Rename 'terraform.example' to terraform.tfvars
- Fill in all variables in 'terraform.tfvars'
- Run: `terraform init` - this will download and install all the required packages
- Run: `terraform apply` 
- Note: This can take around 30 minutes to fully deploy, so please be patient. There is a known OIDC configuration delay with AWS which is being worked on.

After you have completed the above steps you will have a working Kubernetes environment where you will be able to demo;

- Listing Clusters within SFT CLI
- Connecting to Clusters using Kubectl using OPA for Authentication
- Show different levels of Authorization

In order to save costs, please ensure that this environment has been destroyed when not in use. The beauty of Terraform is that is can be created very quickly again. To destroy the kubernetes deployment please run the following command:

- Run: `terraform destroy`


## Testing

### Agent Based Linux and Windows:

#### GUI Testing

- Log into Okta
- Open OPA Application
- Find 'opa-gateway' and click connect
- Find 'opa-linux-target' and click connect
- Create a preauthorization on the opa-windows project
- Find 'opa-windows-target' and click connect
- Click Connect when prompted

#### CLI Testing

- Open Terminal
- Type: `sft list-servers`
- Type: `sft ssh opa-gateway`
- Type: `sft ssh opa-linux-target`
- Type: `sft rdp opa-windows-target`

### AD Joined:

#### GUI Testing

- Log into Okta
- Open OPA Application
- Click Project
- Click opa-domain-joined
- Click Servers
- Click Connect against server
- From the drop down select svc-iis - This is a passwordless flow
- Click connect
- For a password flow, select the Administrator user and enter the password specified in your variables file

#### CLI Testing

Open Terminal
Type: `sft list-servers`
Type: `sft rdp <servername>` // Name of Domain Controller
Enter number that represents svc-iis - This is a passwordless flow
- For a password flow, select the Administrator number and enter the password specified in your variables file

### Kubernetes: 

- Open Terminal
- Type: sft k8s list-clusters
- Type: kubectl config get-contexts
- Type: kubectl config use-context xxx // xxx = name from previous command (eg: first.last@cluster-name.asa-team)
- Type: kubectl cluster-info

## Troubleshooting

- Region us-west-2 is prefered. Other regions may behave funky.

- If you get a python error during execution please run the following:

`export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`

- If you get a timeout error relating to the EKS Cluster, please run `terraform apply` again. This is a know issue with the AWS K8S Terraform Resource.

- If you have just created new AWS user and keys maybe you will get `Error: creating EC2 Instance: PendingVerification`. Keys can take some time to be active, you just need to wait a bit and try again. AWS sends you an email once it is ready to use.

- If you get `Error running command 'sleep 120;cp hosts.default hosts; sed -i '' -e │ 's/USERNAME/Administrator/g' -e 's/PASSWORD/blackcastle/g' -e
│ 's/PUBLICIP/3.72.18.124/g' hosts;ansible-playbook -v -i hosts │ playbooks/windows_dc.yml': exit status 4` your windows_password variable in terraform.tfvars is not complex enough.

- If your AD-joined passwordless RDP shows a smartcard error, first login with a password then try the passwordless again.

- If your session recording utils is not showing the recordings, try ssh into the gateway and run `sudo mount -a` to force mound the s3 filesystem.
  -->

## Thanks

- Felix Colaci
- Andy March
- Kyle Robinson
- Sachin Saxena
- Jacob Jones
- Adam Drayer
- Stephen Bennett
- Joe Ranson
- Grey Thrasher
- Shad Lutz
