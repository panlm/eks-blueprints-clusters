
locals {
  cluster_name = var.cluster_name
  cluster_oidc = var.cluster_oidc
  namespace_name = "thanos"
}

### create namespace
resource "kubernetes_namespace" "ns_thanos" {
  metadata {
    name = "${local.namespace_name}"
  }
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

  role_name_prefix = "${local.cluster_name}-${each.key}-"
  role_policy_arns = {
    policy = module.s3_admin_policy.arn
  }
  oidc_providers = {
    main = {
      provider_arn               = "${local.cluster_oidc}"
      namespace_service_accounts = [
        "${local.namespace_name}:${each.key}-ekscluster1",
        "${local.namespace_name}:${each.key}-ekscluster2",
        "${local.namespace_name}:${each.key}-ekscluster3",
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
    namespace = "${local.namespace_name}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.thanos_sa_irsa["thanos-store"].iam_role_arn}"
    }
  }
}

resource "kubernetes_service_account" "thanos_receive_sa" {
  for_each = toset( ["ekscluster2", "ekscluster3"] )

  metadata {
    name = "thanos-receive-${each.key}"
    namespace = "${local.namespace_name}"
    annotations = {
      "eks.amazonaws.com/role-arn" = "${module.thanos_sa_irsa["thanos-receive"].iam_role_arn}"
    }
  }
}

# create secret key for s3 config
resource "kubernetes_secret" "thanos_secret" {
  for_each = toset( ["ekscluster1", "ekscluster2", "ekscluster3"] )

  metadata {
    name = "thanos-s3-config-${each.key}"
    namespace = "${local.namespace_name}"
  }

  data = fileexists("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${each.key}.yaml") ? {
    # "thanos-s3-config-${each.key}" = "${file("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${each.key}.yaml")}"
    "objstore.yml" = "${file("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${each.key}.yaml")}"
  } : {}
}
