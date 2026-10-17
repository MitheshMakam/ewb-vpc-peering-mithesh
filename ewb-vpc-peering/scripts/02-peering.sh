#!/usr/bin/env bash
# Phase 2: create + accept peering, add routes on all three route tables.
# Run only AFTER you captured the baseline failure.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-south-1}"
source ../ids.env
STUDENT="${STUDENT:?set STUDENT=\"Your Name\"}"

PCX=$(aws ec2 create-vpc-peering-connection --vpc-id "$VPC_A" --peer-vpc-id "$VPC_B" \
  --tag-specifications "ResourceType=vpc-peering-connection,Tags=[{Key=Name,Value=ewb-a-b-peer},{Key=Project,Value=EWB-VPC-Peering},{Key=Student,Value=$STUDENT}]" \
  --query VpcPeeringConnection.VpcPeeringConnectionId --output text)
echo "export PCX=$PCX" >> ../ids.env
aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id "$PCX" >/dev/null
aws ec2 wait vpc-peering-connection-exists --vpc-peering-connection-ids "$PCX"

aws ec2 create-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null  # App-A -> VPC B
aws ec2 create-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null  # return path
aws ec2 create-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16 --vpc-peering-connection-id "$PCX" >/dev/null  # bastion -> App-B (ProxyJump)

aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids "$PCX" \
  --query 'VpcPeeringConnections[0].{Id:VpcPeeringConnectionId,Status:Status.Code,Req:RequesterVpcInfo.CidrBlock,Acc:AccepterVpcInfo.CidrBlock}' --output table
aws ec2 describe-route-tables --route-table-ids "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV" \
  --query 'RouteTables[].{Table:Tags[?Key==`Name`]|[0].Value,Routes:Routes[].[DestinationCidrBlock,GatewayId,VpcPeeringConnectionId]}' --output json
echo "NEXT: run tests (see README step 4)."
