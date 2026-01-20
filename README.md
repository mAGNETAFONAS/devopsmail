# DevOpsMail – AWS Learning Project

A hands-on AWS + DevOps portfolio project built over 10+ days.

## What It Demonstrates
- Secure VPC with public/private subnets
- EC2 automation with User Data
- Infrastructure as Code (Terraform)
- Free Tier–optimized architecture

## Structure
- `days/day1/`: AWS foundations, IAM, CLI, billing alarm
- `days/day2/`: VPC, subnets, route tables, security groups
- `days/day3/`: EC2 instance, Elastic IP, User Data script
- `days/day4/`: IAM roles and policies

## How to Use
1. Configure AWS CLI with least-privilege IAM user
2. Navigate to a day folder
3. Run `terraform init && terraform apply`

> ⚠️ Always set a $1 billing alarm before applying!