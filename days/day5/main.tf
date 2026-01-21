#DevopsMail day2: VPC with public/private subnets

provider "aws" {
  region = "us-east-1"
}

#VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "DevopsMail-VPC"
  }
}

# IGW
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "DevopsMail-IGW"
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "DevopsMail-Public-Subnet"
  }
}

# Private Subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "DevopsMail-Private-Subnet"
  }
}

# Route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "DevopsMail-Public-RT"
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Allow SSH asdn HTTP"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["77.90.103.73/32"]
  }

  ingress {
    description = "HTTP from anywhere (for demo)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "DevopsMail-Web-SG"
  }
}

# Key Pair
resource "aws_key_pair" "deployer" {
  key_name   = "devopsmail-key"
  public_key = file("~/.ssh/devopsmail-key.pub")
}

# EC2 Instance
resource "aws_instance" "web" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.ec2_ses_profile.name

  user_data = <<-EOF
                #!/bin/bash
                echo "User Data ran at $(date)" > /home/ec2-user/userdata.log
                yum update -y
                yum install -y httpd
                systemctl start httpd
                systemctl enable httpd
                echo "<h1>Hello $(hostname -f)</h1>" > /var/www/html/index.html

                #Send startup email
                aws ses send-email \
                  --region us-east-1 \
                  --from "simas.korolis@gmail.com" \
                  --to "simas.korolis@gmail.com" \
                  --subject "DevopsMail Startup" \
                  --text "Instance \$(hostname -f) Has been started at \$(date)" \
                  && echo "Email sent" >> /home/ec2-user/boot.log \
                  || echo "Email failed" >> /home/ec2-user/boot.log

                echo "User Data complete." >> /home/ec2-user/boot.log
                EOF

  tags = {
    Name = "DevopsMail-Web-Server"
  }
}

# Elastic IP
resource "aws_eip" "web" {
  domain     = "vpc"
  depends_on = [aws_instance.web]
}

# IAM Role for EC
resource "aws_iam_role" "ec2_ses_role" {
  name = "DevopsMail-EC2-SES-Role-day5"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# IAM Policy
resource "aws_iam_role_policy" "ses_send" {
  name = "allow-ses-send"
  role = aws_iam_role.ec2_ses_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ses:SendEmail",
          "ses:SendRawEmail"
        ]
        Resource = "*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_ses_profile" {
  name = "DevopsMail-EC2-SES_Profile-day5"
  role = aws_iam_role.ec2_ses_role.name
}