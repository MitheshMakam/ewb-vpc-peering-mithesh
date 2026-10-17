#!/usr/bin/env bash
# Controlled failure: remove ONLY App-B's ICMP echo rule from 10.10.2.10/32, then restore it.
# Usage: ./03-controlled-failure.sh remove   -> then ping from App-A (expect NO replies)
#        ./03-controlled-failure.sh restore  -> then ping again (expect 4 replies)
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-south-1}"
source ../ids.env
PERM="IpProtocol=icmp,FromPort=8,ToPort=0,IpRanges=[{CidrIp=10.10.2.10/32}]"
case "${1:-}" in
  remove)  aws ec2 revoke-security-group-ingress    --group-id "$SG_APP_B" --ip-permissions "$PERM" && echo "ICMP rule removed. SSH rule untouched." ;;
  restore) aws ec2 authorize-security-group-ingress --group-id "$SG_APP_B" --ip-permissions "$PERM" && echo "ICMP rule restored." ;;
  *) echo "usage: $0 remove|restore"; exit 1 ;;
esac
