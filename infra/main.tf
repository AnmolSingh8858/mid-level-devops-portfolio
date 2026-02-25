# VPC - Main Network (from Day 3)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "devops-portfolio-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = { Name = "devops-portfolio-igw" }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1a"
  tags = { Name = "devops-portfolio-public-subnet-a" }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-south-1a"
  tags = { Name = "devops-portfolio-private-subnet-a" }
}
# Private Subnet in second AZ (for RDS AZ coverage)
resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"   # naya CIDR – previous se overlap nahi
  availability_zone = "ap-south-1b"   # dusra AZ

  tags = {
    Name = "devops-portfolio-private-subnet-b"
  }
}
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = { Name = "devops-portfolio-nat-eip" }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags = { Name = "devops-portfolio-nat-gateway" }
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "devops-portfolio-public-rt" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = { Name = "devops-portfolio-private-rt" }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

# NEW: Security Group for EC2 (SSH + HTTP/HTTPS)
resource "aws_security_group" "ec2_sg" {
  name        = "devops-portfolio-ec2-sg"
  description = "Allow SSH, HTTP, HTTPS from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
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
    Name = "devops-portfolio-ec2-sg"
  }
}

# NEW: EC2 Instance in Public Subnet
resource "aws_instance" "web" {
  ami                    = "ami-0f5ee92e2d63afc18"   # Ubuntu 22.04 in ap-south-1 (confirm console mein latest)
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_a.id
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true
    
 user_data = <<-EOT
    #!/bin/bash
    apt-get update -y
    apt-get install -y nodejs npm

    mkdir -p /app
    cd /app

    cat > server.js <<'NODE_EOF'
    const http = require('http');

    const hostname = '0.0.0.0';
    const port = 80;

    const server = http.createServer((req, res) => {
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/plain');
      res.end('Hello from DevOps Portfolio EC2!\\n');
    });

    server.listen(port, hostname, () => {
      console.log('Server running at http://' + hostname + ':' + port + '/');
    });
    NODE_EOF

    node server.js &
  EOT
  tags = {
    Name = "DevOps-Portfolio-EC2"
  }
}
# Outputs
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public_a.id
}

output "private_subnet_id" {
  value = aws_subnet.private_a.id
}

output "ec2_public_ip" {
  value = aws_instance.web.public_ip
}  

# ────────────────────────────────────────────────────────────────────────────────
# DAY 5: RDS PostgreSQL in Private Subnet + Connection Setup
# ────────────────────────────────────────────────────────────────────────────────

# DB Subnet Group – private subnets ke liye
resource "aws_db_subnet_group" "private" {
  name       = "devops-portfolio-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]  # ab 2 AZs cover

  tags = {
    Name = "devops-portfolio-db-subnet-group"
  }
}
# Security Group for RDS – sirf EC2 se connect allow
resource "aws_security_group" "rds_sg" {
  name        = "devops-portfolio-rds-sg"
  description = "Allow PostgreSQL from EC2 SG"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from EC2"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "devops-portfolio-rds-sg"
  }
}

# RDS PostgreSQL Instance – private subnet mein
resource "aws_db_instance" "postgres" {
  identifier             = "devops-portfolio-db"
  allocated_storage      = 20
  db_name                = "portfoliodb"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  username               = "adminuser"
  password               = "SuperSecurePass123!"   # production mein Secrets Manager use karna
  skip_final_snapshot    = true
  publicly_accessible    = false
  db_subnet_group_name   = aws_db_subnet_group.private.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  multi_az               = false

  tags = {
    Name = "devops-portfolio-postgres-db"
  }
}

# Outputs – RDS endpoint dekhne ke liye
output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "Use this to connect from EC2"
}
# ────────────────────────────────────────────────────────────────────────────────
# Day 6: Auto Scaling Group (ASG) + Launch Template
# ────────────────────────────────────────────────────────────────────────────────

# Launch Template (EC2 instances ka blueprint – user_data ke saath)
resource "aws_launch_template" "web_lt" {
  name_prefix   = "devops-portfolio-web-lt-"
  image_id      = "ami-0f5ee92e2d63afc18"   # Ubuntu 22.04 – ap-south-1 mein
  instance_type = "t3.micro"

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    apt-get update -y
    apt-get install -y nodejs npm

    mkdir -p /app
    cd /app

    npm init -y
    npm install express

    cat > server.js <<'NODE_EOF'
    const http = require('http');
    const express = require('express');
    const app = express();

    app.get('/', (req, res) => {
      res.send('Hello from Auto Scaled EC2 Instance!');
    });

    app.listen(80, '0.0.0.0', () => {
      console.log('Server running on port 80');
    });
    NODE_EOF

    node server.js &
  EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "devops-portfolio-asg-instance"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Auto Scaling Group (ASG) – instances ko scale karega
resource "aws_autoscaling_group" "web_asg" {
  name                = "devops-portfolio-web-asg"
  min_size            = 1
  max_size            = 3
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.public_a.id]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "devops-portfolio-asg-instance"
    propagate_at_launch = true
  }

  health_check_type         = "EC2"
  health_check_grace_period = 300
}

# Output: ASG name
output "asg_name" {
  value       = aws_autoscaling_group.web_asg.name
  description = "Auto Scaling Group name"
}
