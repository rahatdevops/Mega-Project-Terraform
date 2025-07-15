output "cluster_id" {
  value = aws_eks_cluster.rahat.id
}

output "node_group_id" {
  value = aws_eks_node_group.rahat.id
}

output "vpc_id" {
  value = aws_vpc.rahat_vpc.id
}

output "subnet_ids" {
  value = aws_subnet.rahat_subnet[*].id
}
