
locals {
  cluster_name = var.cluster_name
  cluster_oidc = var.cluster_oidc
  cluster_endpoint = var.cluster_endpoint
  cluster_ca_data = var.cluster_ca_data
  service_account = "prometheus-sa"
  namespace_name = "monitoring"
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
  name       = "${local.cluster_name}-prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = "${local.namespace_name}"

  values = [
    file("${path.cwd}/../../../thanos-example/POC/prometheus/values-${local.cluster_name}-1.yaml"),
    file("${path.cwd}/../../../thanos-example/POC/prometheus/values-${local.cluster_name}-2.yaml")
  ]
  depends_on = [
    kubernetes_service_account.prometheus_sa,
    kubernetes_secret.prometheus_secret,
    var.blueprints_addons
  ]
}

### create namespace
resource "kubernetes_namespace" "ns_monitoring" {
  metadata {
    name = "${local.namespace_name}"
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
    additional = module.amp_remote_write_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = "${local.cluster_oidc}"
      namespace_service_accounts = ["${local.namespace_name}:${local.service_account}"]
    }
  }
  # tags = module.eks_cluster.eks_cluster_local_tags
}

# create service account
resource "kubernetes_service_account" "prometheus_sa" {
  metadata {
    name = "${local.service_account}"
    namespace = "${local.namespace_name}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.prometheus_sa_irsa.iam_role_arn}"
    }
  }
}

# create secret key for s3 config
resource "kubernetes_secret" "prometheus_secret" {
  metadata {
    name = "thanos-s3-config-${local.cluster_name}"
    namespace = "${local.namespace_name}"
  }

  data = {
    "thanos-s3-config-${local.cluster_name}" = "${file("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${local.cluster_name}.yaml")}"
  }
}

