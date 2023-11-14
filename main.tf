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
    Name = "${var.vpc_name}-igw"
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

resource "aws_security_group" "private_sg" {
  vpc_id      = aws_vpc.vpc.id
  name        = "${var.vpc_name}-private-sg"
  description = "Security group for instances in the private subnet"

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    security_groups  = [aws_security_group.sg.id]
  }
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    security_groups  = [aws_security_group.sg.id]
  }
}

### Security Groups Rules

resource "aws_security_group_rule" "sgr-ingress" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = [var.vpc_cidr_block]
  security_group_id = "${aws_security_group.sg.id}"
  
}

resource "aws_security_group_rule" "sgr-ingress-ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.sg.id}"
  
}

resource "aws_security_group_rule" "sgr-egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = "${aws_security_group.sg.id}"
  
}

### Key_Pair

resource "aws_key_pair" "ssh" {
  key_name   = "ops"
  public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ0PFcgLUul7XPsbTstLzs8ZzPRQ/mFSTf/zLUzVCTPK matte@DESKTOP-H06TE1Q"
}

### Instances

resource "aws_instance" "nat" {
  for_each      = var.azs
  ami           = data.aws_ami.ami.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public[each.key].id
  key_name      = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.sg.id]

  source_dest_check = false

  tags = {
    Name = "${var.vpc_name}-nat-${var.aws_region}${each.key}"
  }
}

resource "aws_instance" "natprive" {
  for_each      = var.azs
  ami           = data.aws_ami.ami.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.private[each.key].id
  key_name      = aws_key_pair.ssh.key_name
  vpc_security_group_ids = [aws_security_group.private_sg.id]

  tags = {
    Name = "${var.vpc_name}-natprive-${var.aws_region}${each.key}"
  }
}

### EIP/Association EIP

resource "aws_eip" "eipnatpub" {
  for_each = var.azs
  domain   = "vpc"
}

resource "aws_eip_association" "eip_assoc_pub" {
  for_each = var.azs
  instance_id   = aws_instance.nat[each.key].id
  allocation_id = aws_eip.eipnatpub[each.key].id
}

### Table de routage

resource "aws_route_table" "nat_route_table" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-public"
  }
}

resource "aws_route_table" "private_route_table" {
  for_each = var.azs
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.key}"
  }

}

resource "aws_route" "nat_route" {
  route_table_id            = aws_route_table.nat_route_table.id
  destination_cidr_block    = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.gw.id
}

resource "aws_route" "private_route" {
  for_each = var.azs
  route_table_id            = aws_route_table.private_route_table[each.key].id
  destination_cidr_block    = "0.0.0.0/0"
  network_interface_id      = aws_instance.nat[each.key].primary_network_interface_id
}

resource "aws_route_table_association" "a" {
  for_each = var.azs
  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.nat_route_table.id
}

resource "aws_route_table_association" "a_private" {
  for_each       = var.azs
  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private_route_table[each.key].id
}