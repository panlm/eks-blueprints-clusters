provider "aws" {
  region = var.aws_region
}

provider "kubernetes" {
  host                   = module.eks_cluster.eks_cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_id]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_cluster.eks_cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_cluster.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks_cluster.eks_cluster_id]
    }
  }
}

# create eks cluster
module "eks_cluster" {
  source = "../modules/eks_cluster"

  aws_region      = var.aws_region
  service_name    = basename(path.cwd)
  cluster_version = var.cluster_version

  argocd_route53_weight      = "100"
  route53_weight             = "100"
  ecsfrontend_route53_weight = "100"

  environment_name    = var.environment_name
  hosted_zone_name    = var.hosted_zone_name
  eks_admin_role_name = var.eks_admin_role_name

  aws_secret_manager_git_private_ssh_key_name = var.aws_secret_manager_git_private_ssh_key_name
  argocd_secret_manager_name_suffix           = var.argocd_secret_manager_name_suffix
  ingress_type                                = var.ingress_type

  gitops_addons_org      = var.gitops_addons_org
  gitops_addons_repo     = var.gitops_addons_repo
  gitops_addons_basepath = var.gitops_addons_basepath
  gitops_addons_path     = var.gitops_addons_path
  gitops_addons_revision = var.gitops_addons_revision

  # gitops_workloads_org      = var.gitops_workloads_org
  # gitops_workloads_repo     = var.gitops_workloads_repo
  # gitops_workloads_revision = var.gitops_workloads_revision
  # gitops_workloads_path     = var.gitops_workloads_path

}

# create prometheus
module "eks_prometheus" {
  source = "../modules/eks_prometheus"

  cluster_name = module.eks_cluster.eks_cluster_id
  cluster_oidc = module.eks_cluster.eks_cluster_oidc_arn
  cluster_endpoint = module.eks_cluster.eks_cluster_endpoint
  cluster_ca_data = module.eks_cluster.cluster_certificate_authority_data
  blueprints_addons = module.eks_cluster.eks_blueprints_addons
}

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

# create role for service account: thanos-store-sa / thanos-receive-sa
module "thanos_sa_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  for_each = toset( ["thanos-store", "thanos-receive"] )

  role_name_prefix = "${module.eks_cluster.eks_cluster_id}-${each.key}-"
  role_policy_arns = {
    policy = module.s3_admin_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = "${module.eks_cluster.eks_cluster_oidc_arn}"
      namespace_service_accounts = [
        "${module.eks_prometheus.ns_thanos}:${each.key}-ekscluster1",
        "${module.eks_prometheus.ns_thanos}:${each.key}-ekscluster2",
        "${module.eks_prometheus.ns_thanos}:${each.key}-ekscluster3",
      ]
    }
  }
  # tags = module.eks_cluster.eks_cluster_local_tags
}

# create servcie account
resource "kubernetes_service_account" "thanos_store_sa" {
  for_each = toset( ["ekscluster1", "ekscluster2", "ekscluster3"] )

  metadata {
    name = "thanos-store-${each.key}"
    namespace = "${module.eks_prometheus.ns_thanos}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.thanos_sa_irsa["thanos-store"].iam_role_arn}"
    }
  }
}

resource "kubernetes_service_account" "thanos_receive_sa" {
  for_each = toset( ["ekscluster2", "ekscluster3"] )

  metadata {
    name = "thanos-receive-${each.key}"
    namespace = "${module.eks_prometheus.ns_thanos}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.thanos_sa_irsa["thanos-receive"].iam_role_arn}"
    }
  }
}

# create secret key for s3 config
resource "kubernetes_secret" "thanos_secret" {
  # count = fileexists("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${module.eks_cluster.eks_cluster_id}.yaml") ? 1 : 0
  for_each = toset( ["ekscluster1", "ekscluster2", "ekscluster3"] )

  metadata {
    name = "thanos-s3-config-${each.key}"
    namespace = "${module.eks_prometheus.ns_thanos}"
  }

  data = fileexists("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${each.key}.yaml") ? {
    "thanos-s3-config-${each.key}" = "${file("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${each.key}.yaml")}"
  } : {}
}
