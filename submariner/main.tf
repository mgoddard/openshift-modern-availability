provider "aws" {
  region = "{{aws_region}}"
}

module "ocp-ipi-aws-prep" {
  source     = "./ocp-ipi-aws-prep"
  aws_region = "{{aws_region}}"
  cluster_id = "{{cluster_id}}"
  ipsec_natt_port = 4500
  ipsec_ike_port = 500
  gw_instance_type = "m5n.large"
}

