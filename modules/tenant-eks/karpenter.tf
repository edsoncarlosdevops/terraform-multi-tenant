# 
# KARPENTER: Tags nas Subnets + Outputs auxiliares
# 
# ATENCAO: Os manifests EC2NodeClass e NodePool foram movidos
# para environments/dev/main.tf porque precisam ser criados
# APOS a instalacao do controller Karpenter via Helm.
#
# As tags nas subnets ficam aqui pois sao recursos AWS e
# podem ser criados em paralelo com o cluster.
# 

#  Tags nas subnets para o Karpenter descobrir 
# Sem isso, o Karpenter nao sabe em quais subnets criar os nodes
resource "aws_ec2_tag" "karpenter_subnets" {
  for_each = { for idx, subnet_id in var.private_subnet_ids : idx => subnet_id }

  resource_id = each.value
  key         = "karpenter.sh/discovery"
  value       = local.name_prefix
}

