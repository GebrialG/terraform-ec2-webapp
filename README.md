# terraform-ec2-webapp

A highly available web app on AWS, built entirely with Terraform: two nginx instances in two Availability Zones behind an Application Load Balancer. Instances are reached through AWS Systems Manager Session Manager, so there is no SSH, no key pair and no open management port.

This is my first Terraform and AWS CLI project. I built it phase by phase, verified each stage with the AWS CLI, and documented the design decisions and trade-offs below.

**Status:** core build complete (network, security, compute, load balancer). The deliberate break-and-fix exercises are still to come and will be added to this README.

## Architecture

                        Internet
                           |
                  [ Internet Gateway ]
                           |
   +-----------------------+------------------------+
   |  VPC 10.0.0.0/16                                |
   |                                                 |
   |        [ Application Load Balancer ]            |
   |        (HTTP :80, spans both public subnets)    |
   |              |                    |             |
   |   Public subnet A         Public subnet B       |
   |   10.0.1.0/24 (AZ a)      10.0.2.0/24 (AZ b)    |
   |   +---------------+       +---------------+     |
   |   |  EC2 + nginx  |       |  EC2 + nginx  |     |
   |   +---------------+       +---------------+     |
   +-------------------------------------------------+

**Traffic flow:** a browser sends a request to the ALB's DNS name. The ALB picks a healthy instance and forwards the request. The instance answers with an HTML page showing its own instance ID and Availability Zone, so refreshing the page shows traffic being spread across both instances.

**Access control (security group chaining):**

```text
Internet --(80 from anywhere)--> ALB security group
ALB security group --(80, source = ALB group)--> web security group --> EC2 instances
```

The instances have public IPs (needed for outbound internet access without a NAT Gateway) but accept inbound traffic only from the load balancer's security group, so they cannot be reached directly from the internet.

## What gets built

The project creates 23 AWS resources:

| Network | VPC (`10.0.0.0/16`), 2 public subnets in 2 AZs, internet gateway, public route table with `0.0.0.0/0` route, 2 route table associations |

| Security | ALB security group, web security group, 4 security group rules, IAM role, `AmazonSSMManagedInstanceCore` policy attachment, instance profile |

| Compute | 2 EC2 instances (Amazon Linux 2023, nginx installed at boot) |

| Load balancing | Application Load Balancer, target group with health checks, HTTP listener, 2 target group attachments |

## Repository layout

```text
versions.tf    # Terraform and provider version constraints
providers.tf   # AWS provider, region, default tags
variables.tf   # input variables
network.tf     # VPC, subnets, internet gateway, routing
security.tf    # security groups, rules, IAM role and instance profile
compute.tf     # AMI lookup and EC2 instances
user_data.sh   # boot script: installs nginx, writes the instance info page
alb.tf         # load balancer, target group, listener, attachments
outputs.tf     # ALB DNS name and instance IDs
README.md
```

## Prerequisites

- Terraform 1.5 or later
- AWS CLI v2, configured with credentials for an IAM user (not the root account)
- The [Session Manager plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html) for the AWS CLI (needed to open a shell on an instance)
- An AWS account with a budget alert set up

## Deploy

bash

git clone https://github.com/GebrialG/terraform-ec2-webapp.git
cd terraform-ec2-webapp

terraform init
terraform plan
terraform apply

Read the plan before typing `yes`. When the apply finishes, wait two to three minutes for the instances to boot and install nginx before testing.

### Variables

All variables have defaults, so a plain `terraform apply` works.

| Variable     | Default      | Purpose |
| `aws_region` | `eu-west-2` | Region to deploy into |
| `project_name` | `ec2-webapp` | Prefix for resource names and the `Project` tag |
| `vpc_cidr` | `10.0.0.0/16` | CIDR block for the VPC |
| `public_subnet_cidrs` | `["10.0.1.0/24", "10.0.2.0/24"]` | One public subnet per AZ |
| `instance_type` | `t3.micro` | EC2 instance type |

### Outputs

- `alb_dns_name`: the public address of the load balancer
- `instance_ids`: IDs of the two web instances

## Design decisions

- **Two Availability Zones from the start.** A subnet lives in one AZ, so spreading instances across two means the loss of one data centre group does not take the site down. An ALB also requires subnets in at least two AZs.
- **Security group chaining.** The web security group's only inbound rule references the ALB's security group instead of a CIDR range. Only the load balancer can reach the instances, and the rule does not break if IP addresses change.
- **Session Manager instead of SSH.** No inbound port 22, no key pair to manage or leak, and no lockout when my home IP changes. Access uses my IAM identity through the AWS API and is auditable.
- **Least-privilege instance role.** The instance profile carries only the AWS-managed SSM core policy. The trust policy allows only the EC2 service to assume the role.
- **IMDSv2 required and encrypted root volumes.** `http_tokens = "required"` blocks the metadata-service credential theft that IMDSv1 allows via SSRF, and the root EBS volume is encrypted at rest.
- **Dynamic AMI lookup.** An `aws_ami` data source finds the latest official Amazon Linux 2023 image instead of a hardcoded ID that goes stale.
- **Explicit `depends_on` for routing.** Instances depend on the route table associations, so the internet route exists before the boot script tries to install nginx. Without it, there is a race on first boot.
- **`user_data_replace_on_change`.** Boot scripts run only once, so changing the script replaces the instances and the new version actually runs.
- **Explicit egress rules.** Terraform removes AWS's default allow-all outbound rule when it creates a security group, so outbound rules are defined explicitly.
- **Faster health checks.** The target group uses a 15-second interval and a threshold of 2, so targets become healthy or unhealthy quickly while testing.
- **Default tags.** The provider's `default_tags` block tags every resource with `Project`, `Environment` and `ManagedBy`, which makes cost tracking and clean-up easier.

## Cost

Cost matters even in a small project. What bills and what doesn't:

- **Free:** the VPC, subnets, internet gateway, route tables, security groups and IAM resources.
- **Billed by the hour while they exist:** the Application Load Balancer, the two EC2 instances, and the public IPv4 addresses attached to them. Data transfer is billed by usage.
- **How I keep it low:** small `t3.micro` instances, no NAT Gateway, a monthly AWS Budget with email alerts, and `terraform destroy` at the end of every working session. Check current AWS pricing for exact rates.

## Tear down

bash

terraform destroy
terraform state list    # should print nothing


## Troubleshooting notes

Things that tripped me up, and what they taught me:

- **`aws ssm start-session` failed with "SessionManagerPlugin is not found".** The CLI can list instances without the plugin but needs it to open a shell, so the plugin must be installed separately.
- **AWS CLI commands returned empty output.** The CLI only searches its default region (`aws configure get region`), and shell variables like `$VPC_ID` are lost when a terminal closes and must be set again after each new `apply`, because new resources get new IDs.
- **`--query` returned nothing with no error.** The start of the query must match the command's output (`Subnets` for `describe-subnets`, `RouteTables` for `describe-route-tables`).
