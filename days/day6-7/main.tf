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
  key_name   = "devopsmail-key-1"
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

                #installing Cloudwatch agent
                yum install -y amazon-cloudwatch-agent

                #Cloudwatch
                cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<EOL
                {
                  "logs": {
                    "logs_collected": {
                      "files": {
                        "collect_list": [
                          {
                            "file_path": "/var/log/htttpd/access_log",
                            "log_group_name": "DevOpsMail/Web/Access",
                            "log_stream_name": "{instance_id}",
                            "timezone": "UTC"
                          },
                          {
                            "file_path": "/var/log/cloud-init-output.log",
                            "log_group_name": "DevOpsMail/Boot/Logs",
                            "log_stream_name": "{instance_id}",
                            "timezone": "UTC"
                          }
                        ]
                      }
                    }
                  }
                }
                EOL

                /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                  -a fetch-config \
                  -m ec2 \
                  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                  -s

                #Send startup email
                aws ses send-email \
                  --region us-east-1 \
                  --from "simas.korolis@gmail.com" \
                  --to "simas.korolis@gmail.com" \
                  --subject "DevopsMail Startup" \
                  --text "Instance \$(hostname -f) Has been started at \$(date). Cloudwatch agent is running" \
                  && echo "Email sent" >> /home/ec2-user/boot.log \
                  || echo "Email failed" >> /home/ec2-user/boot.log

                 # Upload User Data log to S3
                INSTANCE_ID=\$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
                TIMESTAMP=\$(date -u +%Y%m%d-%H%M%S)
                LOG_FILE="/var/log/cloud-init-output.log"
                BUCKET="devopsmail-simas-logs"

                if [ -f "\$LOG_FILE" ]; then
                  aws s3 cp "\$LOG_FILE" "s3://\$BUCKET/userdata-\$INSTANCE_ID-\$TIMESTAMP.log"
                  echo "✅ Log uploaded to S3"
                else
                  echo "❌ Log file not found"
                fi

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
  name = "DevopsMail-EC2-SES-Role-day6"

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

# IAM Policy with added s3 permissions
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
      },
      #S3 permissions
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.devopsmail.arn,
          "${aws_s3_bucket.devopsmail.arn}/*"
        ]
      }
    ]
  })
}

# IAM Cloudwatch Policy
resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "allow-cloudwatch-logs"
  role = aws_iam_role.ec2_ses_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Instance Profile
resource "aws_iam_instance_profile" "ec2_ses_profile" {
  name = "DevopsMail-EC2-SES_Profile-day6"
  role = aws_iam_role.ec2_ses_role.name
}

#Cloudwatch agent