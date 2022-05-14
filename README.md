# azure-cloud-app-service-poc
A simple Proof Of Concept to deploy and configure a simple scalable application hosted on Microsoft Azure Cloud. This also includes auxiliary tasks such as CI/CD, IaC, Monitoring and testing (WIP).

## Task description
The task consist at serving a given application (as Docker image), in Azure, and configure it to be :
- accessible over the internet
- secured
- monitored
- scalable
- upgradable with 0 seconds downtime

## Script description
First, in order to run this script you must have :
- A working Azure account and Azure CLI set up
- Have Terraform >=v1.0.11 installed
- Have docker installed (to push the application container on the remote repository)
- Set the `application-prefix`, `container-image-name`, `container-file-name` and `container-registry-name` variables set (in your environment or via a `terraform.tfvars` file for example)
- Have your application's Docker image in archive format (or edit the `docker-push` local-exec resource in the tf file)

To run the script simply `terraform apply` it (after an `init` and `plan`).
The Terraform script will then :

1. Create a resource group
2. Create a specific User identity
3. Create a KeyVault (to handle ACR encryption) with strict access policies
4. Generate a new key in KeyVault that will be used to encrypt the (futur) ACR
5. Create a (Docker) container registry (ACR)
6. Pull the image from the given file and push it to the ACR
7. Create a service plan
8. Create a linux wep app in app service (associated with the service plan)
9. Create a staging slot (for blue/green deployment), identical and associated to the linux web app
10. Create an app insight service (for monitoring)
11. And finally print the hostname of the deployed application
