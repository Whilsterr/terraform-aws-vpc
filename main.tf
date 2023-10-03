### Module Main

provider "aws" {
  region = var.aws_region
}

### Création VPC

resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_cidr_block
  tags = {
    name = "${var.vpc_name}-vpc"
    environment = "educatif"
    owner = "fuentematteo@gmail.com"
    terraform = true
  }
}

### Création Subnet

### Public

resource "aws_subnet" "public" {
  for_each = var.azs
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr_block, 4, each.value)
  availability_zone = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.vpc_name}-public-${var.aws_region}${each.key}"
    Terraform = true
  }
}

### Privé

resource "aws_subnet" "private" {
  for_each = var.azs
  vpc_id     = aws_vpc.vpc.id
  cidr_block = cidrsubnet(var.vpc_cidr_block, 4, 15-each.value)
  availability_zone = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.key}"
    Terraform = true
  }
}

### Internet Gateway

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-gateway"
    Terraform = true
  }
}

### AMI

data "aws_ami" "ami" {
  most_recent = true

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }
  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-2018.03.0.2021*"]
  }
}

### Security Groups

resource "aws_security_group" "sg" {

  vpc_id = aws_vpc.vpc.id
  name = "${var.vpc_name}-sg"
  description = "Security group"
  
}

### Security Groups Rules

resource "aws_security_group_rule" "sgr-ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr_block]
  security_group_id = aws_security_group.sg.id
  
}

resource "aws_security_group_rule" "sgr-ingress-ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
  
}

resource "aws_security_group_rule" "sgr-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.sg.id
  
}

### Key_Pair

resource "aws_key_pair" "ssh" {
  key_name   = "ops"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ0PFcgLUul7XPsbTstLzs8ZzPRQ/mFSTf/zLUzVCTPK matte@DESKTOP-H06TE1Q"
}

### Instance

resource "aws_instance" "nat" {
  for_each      = var.azs
  ami           = data.aws_ami.ami.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[each.key].id

  source_dest_check = false

  tags = {
    Name = "${var.vpc_name}-nat-${var.aws_region}${each.key}"
  }
}

### Table de routage