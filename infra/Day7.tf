# Day 7: Application Load Balancer (ALB) + Target Group
# Day 7 Fix: Second Public Subnet in AZ 1b (for ALB AZ coverage)
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.4.0/24" # naya CIDR – overlap nahi
  map_public_ip_on_launch = true
  availability_zone       = "ap-south-1b"

  tags = {
    Name = "devops-portfolio-public-subnet-b"
  }
}

# Public Route Table Association for second subnet
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
# Target Group – instances ko health check karega
resource "aws_lb_target_group" "web_tg" {
  name     = "devops-portfolio-web-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = {
    Name = "devops-portfolio-web-tg"
  }
}

# ALB – public traffic handle karega
resource "aws_lb" "web_alb" {
  name               = "devops-portfolio-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ec2_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id] # public subnet mein ALB banta hai

  tags = {
    Name = "devops-portfolio-alb"
  }
}

# Listener – port 80 pe HTTP traffic forward karega
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Target Group Attachment – current EC2 instance ko attach karo
resource "aws_lb_target_group_attachment" "web" {
  target_group_arn = aws_lb_target_group.web_tg.arn
  target_id        = aws_instance.web.id # Day 4 ka EC2
  port             = 80
}

# Output: ALB DNS name (browser pe test karne ke liye)
output "alb_dns_name" {
  value       = aws_lb.web_alb.dns_name
  description = "Use this DNS in browser to access app via ALB"
}
