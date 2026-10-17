#!/usr/bin/env bash
# Cleanup in dependency order. SAVE YOUR EVIDENCE FIRST. Deletes only resources recorded in ids.env.
set -uo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-south-1}"
source ../ids.env
read -r -p "Delete all EWB lab resources in $AWS_DEFAULT_REGION? (yes/no) " a; [ "$a" = yes ] || exit 1

aws ec2 terminate-instances --instance-ids "$BASTION_ID" "$APP_A_ID" "$APP_B_ID" >/dev/null
aws ec2 wait instance-terminated --instance-ids "$BASTION_ID" "$APP_A_ID" "$APP_B_ID"

[ -n "${PCX:-}" ] && {
  aws ec2 delete-route --route-table-id "$RT_A_PRIV" --destination-cidr-block 10.20.0.0/16
  aws ec2 delete-route --route-table-id "$RT_B_PRIV" --destination-cidr-block 10.10.0.0/16
  aws ec2 delete-route --route-table-id "$RT_A_PUB"  --destination-cidr-block 10.20.0.0/16
  aws ec2 delete-vpc-peering-connection --vpc-peering-connection-id "$PCX"
}
for sg in "$SG_BASTION" "$SG_APP_A" "$SG_APP_B"; do aws ec2 delete-security-group --group-id "$sg"; done

# Non-main route tables: disassociate subnets, then delete
for rt in "$RT_A_PUB" "$RT_A_PRIV" "$RT_B_PRIV"; do
  for assoc in $(aws ec2 describe-route-tables --route-table-ids "$rt" --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text); do
    aws ec2 disassociate-route-table --association-id "$assoc"
  done
  aws ec2 delete-route-table --route-table-id "$rt"
done
for s in "$SUB_A_PUB" "$SUB_A_PRIV" "$SUB_B_PRIV"; do aws ec2 delete-subnet --subnet-id "$s"; done
aws ec2 detach-internet-gateway --internet-gateway-id "$IGW" --vpc-id "$VPC_A"
aws ec2 delete-internet-gateway --internet-gateway-id "$IGW"
aws ec2 delete-vpc --vpc-id "$VPC_A"; aws ec2 delete-vpc --vpc-id "$VPC_B"
aws ec2 delete-key-pair --key-name ewb-lab
echo "Remaining tagged resources (should be empty):"
aws ec2 describe-instances --filters Name=tag:Project,Values=EWB-VPC-Peering Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-vpcs --filters Name=tag:Project,Values=EWB-VPC-Peering --query 'Vpcs[].VpcId'
aws ec2 describe-volumes --filters Name=tag:Project,Values=EWB-VPC-Peering --query 'Volumes[].VolumeId'
echo "Local key: rm ~/.ssh/ewb-lab.pem when done. Also check Billing console."
