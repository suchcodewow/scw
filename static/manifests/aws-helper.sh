#!/bin/bash

#TODO: Provide a menu driven interaction to create environment, get current front-end URL, start/stop cluster, cleanup and delete resources
#TODO: If we want to get fancy with text color in echo statements: https://stackoverflow.com/questions/5947742/how-to-change-the-output-color-of-echo-in-linux
#TODO: support a "debug" or "dry-run" type of switch so it goes through the motions without actually running the aws or eksctl commands, but just outputs the command that would've run

#variables
MY_REGION=$(aws ec2 describe-availability-zones --output text --query 'AvailabilityZones[0].[RegionName]')
INSTANCE_TYPE=m5.xlarge
AVAILABILITY_ZONE=$(aws ec2 describe-instance-type-offerings --location-type "availability-zone" --filters Name=instance-type,Values=$INSTANCE_TYPE | jq -r '.InstanceTypeOfferings[0].Location')
#User=$(aws sts get-caller-identity --query "Account" --output text)

#eksctl
echo "Getting eksctl utility to create EKS cluster..."
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

#Clone the AWS alliance git repo that has some additional utility and files we'll use
echo "Pulling down resources from GIT for DTOrders"
git clone https://github.com/dt-alliances-workshops/aws-modernization-dt-orders-setup.git

#Get the name of the company for this POC
#TODO: Provide validation that the company name will be bash-friendly (i.e. no spaces)
echo "Provide the company name (no spaces please or other weird character)"
read CO_NAME
#Make sure there are no spaces
while [[ ! "$CO_NAME" =~ ^[A-Za-z0-9_]+ ]]
do
    echo "I said NO spaces or other weird characters. Only A-Z, a-z, 0-9, and _ allowed. Try again genius! Or, just type q or Q to quit."
    read CO_NAME
done

if [[ "$CO_NAME" =~ \[qQ] ]]; then
    exit 0
fi

#Create a key-pair
echo "Generating key-pair..."
aws ec2 create-key-pair --key-name $CO_NAME-poc-ssh --key-type rsa --key-format pem --query "KeyMaterial" --output text > $CO_NAME-poc-ssh.pem

echo "Your private key is located at ~/$CO_NAME-poc-ssh.pem."

#Create the EKS cluster (2-node)
echo "Creating your cluster... hang tight!!"
eksctl create cluster --with-oidc --ssh-access --version=1.21 --managed --name=$CO_NAME-eks-cluster --tags "Purpose=dynatrace-$CO_NAME-poc" --ssh-public-key $CO_NAME-poc-ssh --region=$MY_REGION --node-type=$INSTANCE_TYPE

#Deploy the DTOrder app
echo "Running ./aws-modernization-dt-orders-setup/app-scripts/start-k8.sh to deploy DTOrders"
cd ./aws-modernization-dt-orders-setup/app-scripts
./start-k8.sh

#Example kubectl get svc command that is basis for getting the external ip/address for the frontend service
#[cloudshell-user@ip-10-0-55-173 app-scripts]$ kubectl get svc -n staging
#NAME       TYPE           CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)        AGE
#catalog    ClusterIP      10.100.11.18     <none>                                                                    8080/TCP       84s
#customer   ClusterIP      10.100.83.167    <none>                                                                    8080/TCP       84s
#frontend   LoadBalancer   10.100.183.187   acd481e2a394c4cc793ecf01e15f4cd8-1808594165.us-east-1.elb.amazonaws.com   80:31570/TCP   81s
#order      ClusterIP      10.100.54.99     <none>                                                                    8080/TCP       82s

#Get the ip for the frontend service
EXTERNAL_IP=$(kubectl get svc -n staging | grep frontend | awk '{print $4}')

#Return to home directory
cd ~

echo "Environment setup is completed!! Whew, that was a lot of work!!"
echo "Your frontend URL is http://$EXTERNAL_IP"

#TODO: For reference this is the eksctl command to delete our cluster and related resources (may still have manually release the elastic IP)
#eksctl delete cluster --name=$CO_NAME-eks-cluster --wait
