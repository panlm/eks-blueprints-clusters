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

resource "helm_release" "prometheus" {
  name       = "${module.eks_cluster.eks_cluster_id}-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "${kubernetes_namespace.ns["monitoring"].metadata[0].name}"

  values = [
    # file("../../../thanos-example/POC/prometheus/values-ekscluster1-1.yaml"),
    # file("../../../thanos-example/POC/prometheus/values-ekscluster1-2.yaml")
    file("values-ekscluster1-1.yaml"),
    file("values-ekscluster1-2.yaml")
  ]
  depends_on = [kubernetes_service_account.prometheus_sa]
}

# resource "helm_release" "thanos" {
# }

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

resource "kubernetes_namespace" "ns" {
  # for_each = {
  #   ns1 = "thanos"
  #   ns2 = "monitoring"
  # }
  for_each = toset( ["thanos", "monitoring"] )
  metadata {
    name = each.key
  }
}

# policy for s3 admin 
module "s3_admin_policy" {
  source = "terraform-aws-modules/iam/aws//modules/iam-policy"

  name        = "s3-admin-policy"
  path        = "/"
  description = "access s3 from prometheus sidecar"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:*",
        ]
        Resource = "*"
      }
    ]
  })

}

# prometheus service account: prometheus-sa
module "prometheus_sa_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name_prefix = "${module.eks_cluster.eks_cluster_id}-prometheus-sa-"
  role_policy_arns = {
    policy = module.s3_admin_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks_cluster.eks_cluster_oidc_arn
      namespace_service_accounts = ["monitoring:prometheus-sa"]
    }
  }
  tags = module.eks_cluster.eks_cluster_local_tags
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_service_account" "prometheus_sa" {
  metadata {
    name = "prometheus-sa"
    namespace = "${kubernetes_namespace.ns["monitoring"].metadata[0].name}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.prometheus_sa_irsa.iam_role_arn}"
    }
  }
  depends_on = [module.prometheus_sa_irsa]
}



# thanos service account: thanos-store-sa / thanos-receive-sa
module "thanos_sa_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  for_each = toset( ["thanos-store-sa", "thanos-receive-sa"] )

  role_name_prefix = "${module.eks_cluster.eks_cluster_id}-${each.key}-"
  role_policy_arns = {
    policy = module.s3_admin_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = module.eks_cluster.eks_cluster_oidc_arn
      namespace_service_accounts = ["thanos:${each.key}"]
    }
  }
  tags = module.eks_cluster.eks_cluster_local_tags
  depends_on = [kubernetes_namespace.ns]
}

resource "kubernetes_service_account" "thanos_sa" {
  for_each = toset( ["thanos-store-sa", "thanos-receive-sa"] )

  metadata {
    name = "${each.key}-sa"
    namespace = "${kubernetes_namespace.ns["thanos"].metadata[0].name}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.thanos_sa_irsa[each.key].iam_role_arn}"
    }
  }
  depends_on = [module.thanos_sa_irsa]
}


