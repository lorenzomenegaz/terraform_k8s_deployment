locals {
  org           = "test"
  account       = "production"
  vpc_name      = "test - SP - PROD-vpc"
  flb_log_group = "test-eks/fluentbit-logs"
  account_id    = data.aws_caller_identity.current.account_id
}

data "aws_vpc" "this" {
  id = "vpc-052efa0bf84d0aa55"
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this.id]
  }

  tags = {
    "test/tier" = "private"
  }
}


data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {}

locals {
  name        = "${local.name_prefix}-eks"
  name_prefix = "test"
  region      = "sa-east-1"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint = local.name
    tag       = "test"
  }

}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.13"

  cluster_name    = local.name
  cluster_version = "1.27"
  
  eks_managed_node_groups = {
    mg_m5 = {
      node_group_name = "managed-ondemand"
      instance_types  = ["m5.2xlarge"]
      subnet_ids      = ["subnet-0b1528c5ffc77335c", "subnet-094ce63afc47f18ee", "subnet-01758dc52aad19e4a"]
      desired_size    = 1
      max_size        = 10
      min_size        = 1
    }
  }

  iam_role_name            = "${local.name}-cluster-role" # Backwards compat
  iam_role_use_name_prefix = false

  vpc_id     = data.aws_vpc.this.id
  subnet_ids = ["subnet-0b1528c5ffc77335c", "subnet-094ce63afc47f18ee", "subnet-01758dc52aad19e4a"]

  cluster_endpoint_public_access = true
  # cluster_enabled_log_types      = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = "arn:aws:iam::${local.account_id}:role/CrossAccountAccess-SolvimmSquadAdminRole"
      username = "solvimm-squad-admin"
      groups   = ["system:masters"]
    },
    {
      rolearn  = "arn:aws:iam::${local.account_id}:role/AWSReservedSSO_SquadAppModernizationAdmin_a11b1c3e8ba3dc7c"
      username = "sso-administrator"
      groups   = ["system:masters"]
    },
    {
      rolearn  = "arn:aws:iam::${local.account_id}:role/eks-access"
      username = "sso-administrator"
      groups   = ["system:masters"]
    }
  ]

  # https://github.com/aws-ia/terraform-aws-eks-blueprints/issues/485
  # https://github.com/aws-ia/terraform-aws-eks-blueprints/issues/494
  kms_key_administrators = [
    data.aws_caller_identity.current.arn,
    #    "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_SquadAppModernizationAdmin_a11b1c3e8ba3dc7c",
    "arn:aws:iam::${local.account_id}:role/CrossAccountAccess-SolvimmSquadAdminRole"
  ]

  tags = local.tags
}

module "eks_addons" {
  source            = "aws-ia/eks-blueprints-addons/aws"
  version           = "~> 1.7"
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
  cluster_version   = module.eks.cluster_version


  eks_addons = {

    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }
  enable_aws_cloudwatch_metrics = true
  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    version = "2.6.0"
    set = [
      {
        name  = "vpcId"
        value = data.aws_vpc.this.id
      },
      {
        name  = "podDisruptionBudget.maxUnavailable"
        value = 1
      },
    ]
  }

  enable_metrics_server = true
  metrics_server = {
    chart_version = "3.8"
  }

  enable_aws_efs_csi_driver = true
  # Optional aws_efs_csi_driver_helm_config
  aws_efs_csi_driver = {
    repository     = "https://kubernetes-sigs.github.io/aws-efs-csi-driver/"
    chart_version  = "2.4.1"
  }

  tags = local.tags
}

data "aws_eks_addon_version" "latest" {
  for_each = toset(["kube-proxy", "vpc-cni"])

  addon_name         = each.value
  kubernetes_version = module.eks.cluster_version
  most_recent        = true
}

