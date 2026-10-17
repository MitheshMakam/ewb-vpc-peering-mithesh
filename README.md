# AWS VPC Peering: EWB Cloud Labs Project 01

**Name:** _Mithesh Makam_  **Batch:** _BATCH-1_  **Region:** ap-south-1  **Completed:** _17/10/2026_

Two private VPCs connected with VPC peering, administered through one public bastion (SSH ProxyJump).

## Architecture

| Resource | Name | CIDR / IP |
|---|---|---|
| VPC A | ewb-vpc-a | 10.10.0.0/16 |
| Public subnet | ewb-a-public | 10.10.1.0/24 |
| Private subnet | ewb-a-private | 10.10.2.0/24 |
| VPC B | ewb-vpc-b | 10.20.0.0/16 |
| Private subnet | ewb-b-private | 10.20.1.0/24 |
| Bastion | ewb-bastion | 10.10.1.10 + public IPv4 |
| App-A | ewb-app-a | 10.10.2.10 |
| App-B | ewb-app-b | 10.20.1.10 |

Actual IDs (fill from `ids.env`): VPC A `vpc-…`, VPC B `vpc-…`, peering `pcx-…`, instances `i-…` (x3).

Diagram: _add `docs/architecture.png` (draw it in draw.io or copy the workbook page 3 layout)._

## How it was built

Scripts in `scripts/` mirror the workbook (run from inside `scripts/`; needs AWS CLI configured for the lab account):

1. `01-build-network.sh`: VPCs, subnets, IGW, route tables, security groups, key pair, instances
2. `02-peering.sh`: peering request/accept + routes on all 3 route tables
3. `03-controlled-failure.sh remove|restore`: ICMP failure and recovery test
4. `04-cleanup.sh`: teardown

The same steps can be done in the console; screenshots below are from my own run.

## Routing and security design

- **Route tables:** `ewb-rt-a-private` 10.20.0.0/16 → pcx; `ewb-rt-b-private` 10.10.0.0/16 → pcx (return path); `ewb-rt-a-public` 0.0.0.0/0 → IGW plus 10.20.0.0/16 → pcx.
- **Security groups (inbound):** bastion SSH from my /32; App-A SSH from 10.10.1.10/32, ICMP echo from 10.20.1.10/32; App-B SSH from 10.10.1.10/32, ICMP echo from 10.10.2.10/32.

## Evidence

> Replace each placeholder with your real screenshot, labelled with host, test and result. Never include the .pem key.

| # | Evidence | File |
|---|---|---|
| CP01 | Subnet associations + public default route; private RT has only local | `screenshots/01-routes-a.png` |
| CP02 | 3 instance IDs/IPs; no public IP on App-A/B | `screenshots/02-instances.png` |
| T01 | Baseline: App-A `ping -c 4 10.20.1.10` fails (before peering) | `screenshots/03-baseline-fail.png` |
| CP03 | Peering Active, both VPC IDs | `screenshots/04-peering-active.png` |
| CP04 | All 3 route tables + associations | `screenshots/05-route-tables.png` |
| T02 | App-A → App-B ping, 0% loss | `screenshots/06-ping-forward.png` |
| T03 | App-B → App-A ping, 0% loss | `screenshots/07-ping-reverse.png` |
| T04 | `ssh ewb-app-b` via bastion | `screenshots/08-ssh-app-b.png` |
| T05 | No public IPv4 on App-A / App-B | `screenshots/09-isolation.png` |
| SG | Inbound rules of each security group | `screenshots/10-security-groups.png` |
| F01 | ICMP rule removed → ping fails | `screenshots/11-failure.png` |
| F02 | Rule restored → ping recovers | `screenshots/12-recovery.png` |
| CLN | Cleanup: no tagged resources left | `screenshots/13-cleanup.png` |

## Answers (be ready for viva)

1. **Why a return route?** Peering is a link, not magic: the reply from App-B to 10.10.x.x needs a route back to VPC A, otherwise replies are dropped.
2. **Why is the App-B SSH source the bastion's private IP?** ProxyJump makes the bastion open a new SSH connection to App-B, so App-B sees the bastion's private address (10.10.1.10) as the source.
3. **Why doesn't Active peering guarantee ping?** Traffic also needs routes on both sides and a security group rule allowing ICMP on the destination (and NACLs if customised).
4. **Can VPC B use VPC A's internet gateway over peering?** No. Peering is non-transitive and does not forward traffic to a gateway in the peer VPC.

## Controlled failure

Removed only App-B's ICMP echo rule (source 10.10.2.10/32): pings from App-A stopped, SSH still worked. Restoring the exact rule brought replies back. This shows security groups, not the peering link, were gating the traffic.

