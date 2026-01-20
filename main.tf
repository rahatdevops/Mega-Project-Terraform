provider "aws" {
  region = "ap-southeast-1"
}

########################
# VPC
########################
resource "aws_vpc" "rahat_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "rahat-vpc"
  }
}

########################
# Subnets (Public)
########################
resource "aws_subnet" "rahat_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.rahat_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.rahat_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-southeast-1a", "ap-southeast-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name                                   = "rahat-subnet-${count.index}"
    "kubernetes.io/cluster/rahat-cluster" = "shared"
    "kubernetes.io/role/elb"              = "1"
  }
}

########################
# Internet Gateway
########################
resource "aws_internet_gateway" "rahat_igw" {
  vpc_id = aws_vpc.rahat_vpc.id

  tags = {
    Name = "rahat-igw"
  }
}

########################
# Route Table
########################
resource "aws_route_table" "rahat_route_table" {
  vpc_id = aws_vpc.rahat_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.rahat_igw.id
  }

  tags = {
    Name = "rahat-route-table"
  }
}

resource "aws_route_table_association" "rahat_association" {
  count          = 2
  subnet_id      = aws_subnet.rahat_subnet[count.index].id
  route_table_id = aws_route_table.rahat_route_table.id
}

########################
# Security Groups
########################
resource "aws_security_group" "rahat_cluster_sg" {
  name   = "rahat-cluster-sg"
  vpc_id = aws_vpc.rahat_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rahat-cluster-sg"
  }
}

resource "aws_security_group" "rahat_node_sg" {
  name   = "rahat-node-sg"
  vpc_id = aws_vpc.rahat_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Change to YOUR_IP/32 in production
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rahat-node-sg"
  }
}

########################
# IAM Roles
########################
resource "aws_iam_role" "rahat_cluster_role" {
  name = "rahat-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rahat_cluster_policy" {
  role       = aws_iam_role.rahat_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "rahat_cluster_vpc_policy" {
  role       = aws_iam_role.rahat_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

resource "aws_iam_role" "rahat_node_group_role" {
  name = "rahat-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.rahat_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.rahat_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.rahat_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ebs_policy" {
  role       = aws_iam_role.rahat_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

########################
# EKS Cluster
########################
resource "aws_eks_cluster" "rahat" {
  name     = "rahat-cluster"
  role_arn = aws_iam_role.rahat_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.rahat_subnet[*].id
    security_group_ids = [aws_security_group.rahat_cluster_sg.id]
  }

  timeouts {
    create = "60m"
    delete = "60m"
  }
}

########################
# Node Group
########################
resource "aws_eks_node_group" "rahat" {
  cluster_name    = aws_eks_cluster.rahat.name
  node_group_name = "rahat-node-group"
  node_role_arn   = aws_iam_role.rahat_node_group_role.arn
  subnet_ids      = aws_subnet.rahat_subnet[*].id
  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  remote_access {
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.rahat_node_sg.id]
  }

  depends_on = [
    aws_eks_cluster.rahat
  ]
}

########################
# EBS CSI Addon
########################
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.rahat.name
  addon_name   = "aws-ebs-csi-driver"


  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.rahat
  ]



}
