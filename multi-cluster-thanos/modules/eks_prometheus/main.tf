# provider "aws" {
#   region = var.aws_region
# }

locals {
  cluster_name = var.cluster_name
  cluster_oidc = var.cluster_oidc
  cluster_endpoint = var.cluster_endpoint
  cluster_ca_data = var.cluster_ca_data
}

# data "terraform_remote_state" "cluster" {
#   backend = "local"
#   config = {
#     path = "../${local.cluster_name}/terraform.tfstate"
#   }
# }


provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
  }
  alias = "ekscluster1"
}

# provider "kubernetes" {
#   host                   = data.terraform_remote_state.cluster["ekscluster2"].eks_cluster_endpoint
#   cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster["ekscluster2"].cluster_certificate_authority_data)

#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "aws"
#     args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster["ekscluster2"].outputs.eks_cluster_id]
#   }
#   alias = "ekscluster2"
# }
# provider "kubernetes" {
#   host                   = data.terraform_remote_state.cluster["ekscluster3"].eks_cluster_endpoint
#   cluster_ca_certificate = base64decode(data.terraform_remote_state.cluster["ekscluster3"].cluster_certificate_authority_data)

#   exec {
#     api_version = "client.authentication.k8s.io/v1beta1"
#     command     = "aws"
#     args        = ["eks", "get-token", "--cluster-name", data.terraform_remote_state.cluster["ekscluster3"].outputs.eks_cluster_id]
#   }
#   alias = "ekscluster3"
# }

provider "helm" {
  kubernetes {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", local.cluster_name]
    }
  }
}


# resource "helm_release" "nginx" {
#   name       = "nginx"
#   repository = "https://charts.bitnami.com/bitnami"
#   chart      = "nginx"

#   values = []
# }


### 
### install prometheus operator with helm
###
resource "helm_release" "prometheus" {
  # disable this resource if files does not exist
  count = fileexists("${path.cwd}/../../../thanos-example/POC/prometheus/values-${local.cluster_name}-1.yaml") ? 1 : 0

  name       = "${local.cluster_name}-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "${kubernetes_namespace.ns["monitoring"].metadata[0].name}"

  values = fileexists("${path.cwd}/../../../thanos-example/POC/prometheus/values-${local.cluster_name}-1.yaml") ? [
    file("${path.cwd}/../../../thanos-example/POC/prometheus/values-${local.cluster_name}-1.yaml"),
    file("${path.cwd}/../../../thanos-example/POC/prometheus/values-${local.cluster_name}-2.yaml")
  ] : []
  depends_on = [
    kubernetes_service_account.prometheus_sa,
    kubernetes_secret.prometheus_secret,
    var.blueprints_addons
  ]
}

### 
### install prometheus operator with helm
###
# resource "helm_release" "thanos" {
#   count = 0
#   depends_on = [
#     kubernetes_service_account.thanos_sa,
#     kubernetes_secret.thanos_secret
#   ]
# }


### create namespace
resource "kubernetes_namespace" "ns" {
  # for_each = {
  #   ns1 = "thanos"
  #   ns2 = "monitoring"
  # }
  for_each = toset( ["monitoring", "thanos"] )
  metadata {
    name = each.key
  }
}

# policy for s3 admin 
module "s3_admin_policy" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name_prefix = "s3-admin-policy-"
  path        = "/"
  description = "access s3 from prometheus sidecar"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:*"]
        Resource = "*"
      }
    ]
  })
}

# policy for AMP remote write
module "amp_remote_write_policy" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name_prefix = "amp-remote-rite-policy-"
  path        = "/"
  description = "access remote write to aws managed prometheus"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["aps:RemoteWrite"]
        Resource = "*"
      }
    ]
  })
}

# create role for service account: prometheus-sa
module "prometheus_sa_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name_prefix = "${local.cluster_name}-prometheus-sa-"
  role_policy_arns = {
    policy = module.s3_admin_policy.arn
    policy = module.amp_remote_write_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = "${local.cluster_oidc}"
      namespace_service_accounts = ["monitoring:prometheus-sa"]
    }
  }
  # tags = module.eks_cluster.eks_cluster_local_tags
}

# create service account
resource "kubernetes_service_account" "prometheus_sa" {
  metadata {
    name = "prometheus-sa"
    namespace = "monitoring"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.prometheus_sa_irsa.iam_role_arn}"
    }
  }
}

# create role for service account: thanos-store-sa / thanos-receive-sa
module "thanos_sa_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  for_each = toset( ["thanos-store-sa", "thanos-receive-sa"] )

  role_name_prefix = "${local.cluster_name}-${each.key}-"
  role_policy_arns = {
    policy = module.s3_admin_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = "${local.cluster_oidc}"
      namespace_service_accounts = ["${kubernetes_namespace.ns["thanos"].metadata[0].name}:${each.key}"]
    }
  }
  # tags = module.eks_cluster.eks_cluster_local_tags
}

# create servcie account
resource "kubernetes_service_account" "thanos_sa" {
  for_each = toset( ["thanos-store-sa", "thanos-receive-sa"] )

  metadata {
    name = "${each.key}"
    namespace = "thanos"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.thanos_sa_irsa[each.key].iam_role_arn}"
    }
  }
}

# create secret key for s3 config
resource "kubernetes_secret" "prometheus_secret" {
  count = fileexists("../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml") ? 1 : 0

  metadata {
    name = "thanos-s3-config-${local.cluster_name}"
    namespace = "monitoring"
  }

  data = fileexists("../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml") ? {
    "thanos-s3-config-${local.cluster_name}" = "${file("../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml")}"
  } : {}
}

# create secret key for s3 config
resource "kubernetes_secret" "thanos_secret" {
  count = fileexists("../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml") ? 1 : 0

  metadata {
    name = "thanos-s3-config-${local.cluster_name}"
    namespace = "thanos"
  }

  data = fileexists("../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml") ? {
    "thanos-s3-config-${local.cluster_name}" = "${file("../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml")}"
  } : {}
}


