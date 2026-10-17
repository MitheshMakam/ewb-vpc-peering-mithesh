#!/usr/bin/env bash
# Phase 1: VPC A, VPC B, subnets, IGW, route tables, security groups, key pair, 3 instances.
# NO peering yet -> capture the baseline failure (ping App-A -> App-B) after this script.
# Usage: STUDENT="Your Name" ./01-build-network.sh
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-south-1}"
AZ="${AZ:-${AWS_DEFAULT_REGION}a}"
STUDENT="${STUDENT:?set STUDENT=\"Your Name\"}"
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
IDS=../ids.env; : > "$IDS"

tags() { echo "ResourceType=$1,Tags=[{Key=Name,Value=$2},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT}]"; }
save() { echo "export $1=$2" | tee -a "$IDS"; }

MYIP="$(curl -s https://checkip.amazonaws.com | tr -d '[:space:]')/32"
echo "Bastion SSH will be allowed from: $MYIP"

# --- VPC A ---
VPC_A=$(aws ec2 create-vpc --cidr-block 10.10.0.0/16 --tag-specifications "$(tags vpc ewb-vpc-a)" --query Vpc.VpcId --output text); save VPC_A "$VPC_A"
SUB_A_PUB=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.1.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet ewb-a-public)" --query Subnet.SubnetId --output text); save SUB_A_PUB "$SUB_A_PUB"
SUB_A_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_A" --cidr-block 10.10.2.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet ewb-a-private)" --query Subnet.SubnetId --output text); save SUB_A_PRIV "$SUB_A_PRIV"
IGW=$(aws ec2 create-internet-gateway --tag-specifications "$(tags internet-gateway ewb-igw-a)" --query InternetGateway.InternetGatewayId --output text); save IGW "$IGW"
aws ec2 attach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"

RT_A_PUB=$(aws ec2 create-route-table --vpc-id "$VPC_A" --tag-specifications "$(tags route-table ewb-rt-a-public)" --query RouteTable.RouteTableId --output text); save RT_A_PUB "$RT_A_PUB"
aws ec2 associate-route-table --route-table-id "$RT_A_PUB" --subnet-id "$SUB_A_PUB" >/dev/null
aws ec2 create-route --route-table-id "$RT_A_PUB" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW" >/dev/null
RT_A_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_A" --tag-specifications "$(tags route-table ewb-rt-a-private)" --query RouteTable.RouteTableId --output text); save RT_A_PRIV "$RT_A_PRIV"
aws ec2 associate-route-table --route-table-id "$RT_A_PRIV" --subnet-id "$SUB_A_PRIV" >/dev/null

# --- VPC B (no IGW) ---
VPC_B=$(aws ec2 create-vpc --cidr-block 10.20.0.0/16 --tag-specifications "$(tags vpc ewb-vpc-b)" --query Vpc.VpcId --output text); save VPC_B "$VPC_B"
SUB_B_PRIV=$(aws ec2 create-subnet --vpc-id "$VPC_B" --cidr-block 10.20.1.0/24 --availability-zone "$AZ" --tag-specifications "$(tags subnet ewb-b-private)" --query Subnet.SubnetId --output text); save SUB_B_PRIV "$SUB_B_PRIV"
RT_B_PRIV=$(aws ec2 create-route-table --vpc-id "$VPC_B" --tag-specifications "$(tags route-table ewb-rt-b-private)" --query RouteTable.RouteTableId --output text); save RT_B_PRIV "$RT_B_PRIV"
aws ec2 associate-route-table --route-table-id "$RT_B_PRIV" --subnet-id "$SUB_B_PRIV" >/dev/null

# --- Security groups ---
SG_BASTION=$(aws ec2 create-security-group --group-name ewb-sg-bastion --description "EWB bastion" --vpc-id "$VPC_A" --tag-specifications "$(tags security-group ewb-sg-bastion)" --query GroupId --output text); save SG_BASTION "$SG_BASTION"
SG_APP_A=$(aws ec2 create-security-group --group-name ewb-sg-app-a --description "EWB App-A" --vpc-id "$VPC_A" --tag-specifications "$(tags security-group ewb-sg-app-a)" --query GroupId --output text); save SG_APP_A "$SG_APP_A"
SG_APP_B=$(aws ec2 create-security-group --group-name ewb-sg-app-b --description "EWB App-B" --vpc-id "$VPC_B" --tag-specifications "$(tags security-group ewb-sg-app-b)" --query GroupId --output text); save SG_APP_B "$SG_APP_B"

ssh_rule()  { aws ec2 authorize-security-group-ingress --group-id "$1" --protocol tcp --port 22 --cidr "$2" >/dev/null; }
icmp_rule() { aws ec2 authorize-security-group-ingress --group-id "$1" --ip-permissions "IpProtocol=icmp,FromPort=8,ToPort=0,IpRanges=[{CidrIp=$2}]" >/dev/null; }
ssh_rule  "$SG_BASTION" "$MYIP"
ssh_rule  "$SG_APP_A" 10.10.1.10/32
icmp_rule "$SG_APP_A" 10.20.1.10/32
ssh_rule  "$SG_APP_B" 10.10.1.10/32
icmp_rule "$SG_APP_B" 10.10.2.10/32

# --- Key pair (private key stays on your laptop only) ---
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/ewb-lab.pem ]; then
  aws ec2 create-key-pair --key-name ewb-lab --key-type rsa --query KeyMaterial --output text > ~/.ssh/ewb-lab.pem
  chmod 400 ~/.ssh/ewb-lab.pem
fi

# --- Instances ---
AMI=$(aws ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)
launch() { # name subnet ip sg public(yes|no)
  local pub="--no-associate-public-ip-address"; [ "$5" = yes ] && pub="--associate-public-ip-address"
  aws ec2 run-instances --image-id "$AMI" --instance-type "$INSTANCE_TYPE" --key-name ewb-lab \
    --subnet-id "$2" --private-ip-address "$3" --security-group-ids "$4" $pub \
    --tag-specifications "$(tags instance "$1")" --query 'Instances[0].InstanceId' --output text
}
BASTION_ID=$(launch ewb-bastion "$SUB_A_PUB" 10.10.1.10 "$SG_BASTION" yes); save BASTION_ID "$BASTION_ID"
APP_A_ID=$(launch ewb-app-a "$SUB_A_PRIV" 10.10.2.10 "$SG_APP_A" no);     save APP_A_ID "$APP_A_ID"
APP_B_ID=$(launch ewb-app-b "$SUB_B_PRIV" 10.20.1.10 "$SG_APP_B" no);     save APP_B_ID "$APP_B_ID"

aws ec2 wait instance-status-ok --instance-ids "$BASTION_ID" "$APP_A_ID" "$APP_B_ID"
BASTION_IP=$(aws ec2 describe-instances --instance-ids "$BASTION_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
save BASTION_IP "$BASTION_IP"

echo; echo "Done. Put $BASTION_IP in ~/.ssh/config (see ssh_config.example)."
echo "NEXT: capture Checkpoints 01-02 + baseline ping (App-A -> 10.20.1.10 must FAIL), then run 02-peering.sh"
