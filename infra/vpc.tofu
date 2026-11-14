resource "aws_vpc" "sagemaker_ai_demo_vpc" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "sagemaker_ai_demo_igw" {
  vpc_id = aws_vpc.sagemaker_ai_demo_vpc.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}

resource "aws_route_table" "sagemaker_ai_demo_rtb_public" {
  vpc_id = aws_vpc.sagemaker_ai_demo_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sagemaker_ai_demo_igw.id
  }

  tags = {
    Name = "${var.name_prefix}-rtb-public"
  }
}

resource "aws_subnet" "sagemaker_ai_demo_subnet1_public" {
  vpc_id            = aws_vpc.sagemaker_ai_demo_vpc.id
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block        = var.subnet1_public_cidr

  tags = {
    Name = "${var.name_prefix}-subnet1-public"
  }
}

resource "aws_route_table_association" "sagemaker_ai_demo_subnet1_public_rtb_assoc" {
  subnet_id      = aws_subnet.sagemaker_ai_demo_subnet1_public.id
  route_table_id = aws_route_table.sagemaker_ai_demo_rtb_public.id
}

resource "aws_subnet" "sagemaker_ai_demo_subnet2_public" {
  vpc_id            = aws_vpc.sagemaker_ai_demo_vpc.id
  availability_zone = data.aws_availability_zones.available.names[1]
  cidr_block        = var.subnet2_public_cidr

  tags = {
    Name = "${var.name_prefix}-subnet2-public"
  }
}

resource "aws_route_table_association" "sagemaker_ai_demo_subnet2_public_rtb_assoc" {
  subnet_id      = aws_subnet.sagemaker_ai_demo_subnet2_public.id
  route_table_id = aws_route_table.sagemaker_ai_demo_rtb_public.id
}

resource "aws_nat_gateway" "sagemaker_ai_demo_ngw" {
  availability_mode = "regional"
  vpc_id            = aws_vpc.sagemaker_ai_demo_vpc.id

  tags = {
    Name = "${var.name_prefix}-ngw"
  }

  depends_on = [aws_internet_gateway.sagemaker_ai_demo_igw]
}

resource "aws_route_table" "sagemaker_ai_demo_rtb_private" {
  vpc_id = aws_vpc.sagemaker_ai_demo_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.sagemaker_ai_demo_ngw.id
  }

  tags = {
    Name = "${var.name_prefix}-rtb-private"
  }
}

resource "aws_subnet" "sagemaker_ai_demo_subnet1_private" {
  vpc_id            = aws_vpc.sagemaker_ai_demo_vpc.id
  availability_zone = data.aws_availability_zones.available.names[0]
  cidr_block        = var.subnet1_private_cidr

  tags = {
    Name = "${var.name_prefix}-subnet1-private"
  }
}

resource "aws_route_table_association" "sagemaker_ai_demo_subnet1_private_rtb_assoc" {
  subnet_id      = aws_subnet.sagemaker_ai_demo_subnet1_private.id
  route_table_id = aws_route_table.sagemaker_ai_demo_rtb_private.id
}

resource "aws_subnet" "sagemaker_ai_demo_subnet2_private" {
  vpc_id            = aws_vpc.sagemaker_ai_demo_vpc.id
  availability_zone = data.aws_availability_zones.available.names[1]
  cidr_block        = var.subnet2_private_cidr

  tags = {
    Name = "${var.name_prefix}-subnet2-private"
  }
}

resource "aws_route_table_association" "sagemaker_ai_demo_subnet2_private_rtb_assoc" {
  subnet_id      = aws_subnet.sagemaker_ai_demo_subnet2_private.id
  route_table_id = aws_route_table.sagemaker_ai_demo_rtb_private.id
}
