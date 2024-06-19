resource "aws_vpc" "myvpc" {
    cidr_block = var.cidr  
}

resource "aws_subnet" "mysubnet1" {
    vpc_id = aws_vpc.myvpc.id
    cidr_block = var.subnet1_cidr
    availability_zone = "us-east-1a"
    map_public_ip_on_launch = true
}

resource "aws_subnet" "mysubnet2" {
    vpc_id = aws_vpc.myvpc.id
    cidr_block = var.subnet1_cidr
    availability_zone = "us-east-1b"
    map_public_ip_on_launch = true
}

resource "aws_internet_gateway" "internet_gateway" {
    vpc_id = aws_vpc.myvpc.id
}

resource "aws_route_table" "route_table" {
    
    vpc_id = aws_vpc.myvpc.id
    route {
        cidr_block= "0.0.0.0/0"
        gateway_id = aws_internet_gateway.internet_gateway.id
    }
}

resource "aws_route_table_association" "subnet1_route_table_assoc" {
    route_table_id = aws_route_table.route_table.id
    subnet_id = aws_subnet.mysubnet1.id  
}

resource "aws_route_table_association" "subnet2_route_table_assoc" {
    route_table_id = aws_route_table.route_table.id
    subnet_id = aws_subnet.mysubnet2.id  
}


resource "aws_security_group" "security_group" {
  vpc_id      = aws_vpc.myvpc.id
  revoke_rules_on_delete = true
}

resource "aws_vpc_security_group_ingress_rule" "security_group_ingress_http" {
  security_group_id = aws_security_group.security_group.id
  cidr_ipv4         = aws_vpc.myvpc.cidr_block
  from_port         = 80 # using port 80 (HTTP) instead of port 443 (HTTPS) as we don't have SSL certificate yet.
  ip_protocol       = "tcp"
  to_port           = 80
}

resource "aws_vpc_security_group_ingress_rule" "security_group_ingress_ssh" {
  security_group_id = aws_security_group.security_group.id
  cidr_ipv4         = aws_vpc.myvpc.cidr_block
  from_port         = 22 # using port 80 (HTTP) instead of port 443 (HTTPS) as we don't have SSL certificate yet.
  ip_protocol       = "tcp"
  to_port           = 22
}


resource "aws_vpc_security_group_egress_rule" "security_group_egress" {
  security_group_id = aws_security_group.security_group.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # semantically equivalent to all ports
}


resource "aws_s3_bucket" "s3_bucket" {
    bucket = "my-first-aws3-buckt"  
}

resource "aws_s3_bucket_ownership_controls" "s3_bucket_ownership_controls" {
    bucket = aws_s3_bucket.s3_bucket.id
    rule {
      object_ownership = "BucketOwnerPreferred"
    }
    }

resource "aws_s3_bucket_public_access_block" "s3_bucket_public_access_block" {
  bucket = aws_s3_bucket.s3_bucket.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_acl" "example" {
  depends_on = [
    aws_s3_bucket_ownership_controls.s3_bucket_ownership_controls,
    aws_s3_bucket_public_access_block.s3_bucket_public_access_block
    ]
  bucket = aws_s3_bucket.s3_bucket.id
  acl    = "public-read"
}


resource "aws_instance" "webserver1" {
  ami = "ami-033fabdd332044f06"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.security_group.id]
  subnet_id = aws_subnet.mysubnet1.id
  user_data = base64encode(file("ec2_startup_script.sh"))
  iam_instance_profile = aws_iam_role.ec2_iam_role.name
}


resource "aws_instance" "webserver2" {
  ami = "ami-033fabdd332044f06"
  instance_type = "t2.micro"
  vpc_security_group_ids = [aws_security_group.security_group.id]
  subnet_id = aws_subnet.mysubnet2.id
  user_data = base64encode(file("ec2_startup_script2.sh"))
  iam_instance_profile = aws_iam_role.ec2_iam_role.name
}

resource "aws_lb" "load_balancer" {
    name = "my-appl-load-balancer"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.security_group.id]
    subnets = [aws_subnet.mysubnet1.id, aws_subnet.mysubnet2.id]
    
}

resource "aws_lb_target_group" "alb_tgt_group" {
  name        = "my-appl-load-balancer-tgt-group"
  target_type = "alb"
  port        = 80
  protocol    = "TCP"
  vpc_id      = aws_vpc.myvpc.id
  health_check {
    path = "/"
    port = "traffic-port" # default
  }
}

resource "aws_lb_target_group_attachment" "alb_tgt_group_attachment" {
  target_group_arn = aws_lb_target_group.alb_tgt_group.arn
  target_id        = aws_instance.webserver1.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "alb_tgt_group_attachment2" {
  target_group_arn = aws_lb_target_group.alb_tgt_group.arn
  target_id        = aws_instance.webserver2.id
  port             = 80
}

resource "aws_lb_listener" "aws_load_bal_listener" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tgt_group.arn
  }
}

resource "aws_iam_role" "ec2_iam_role" {
  name = "ec2_iam_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })

}

resource "aws_iam_role_policy_attachment" "ec2_role_attachment" {
  role       = aws_iam_role.ec2_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

output "lb_output" {
  value = aws_lb.load_balancer.dns_name
  
}

