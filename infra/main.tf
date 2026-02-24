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
