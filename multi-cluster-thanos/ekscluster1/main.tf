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
  count = fileexists("${path.cwd}/../../../thanos-example/POC/prometheus/values-${module.eks_cluster.eks_cluster_id}-1.yaml") ? 1 : 0

  cluster_name = module.eks_cluster.eks_cluster_id
  cluster_oidc = module.eks_cluster.eks_cluster_oidc_arn
  depends_on = [
    module.eks_cluster.eks_blueprints_addons,
  ]  
}

module "eks_thanos" {
  source = "../modules/eks_thanos"
  count = fileexists("${path.cwd}/../../../thanos-example/POC/s3-config/thanos-s3-config-${module.eks_cluster.eks_cluster_id}.yaml") ? 1 : 0

  cluster_name = module.eks_cluster.eks_cluster_id
  cluster_oidc = module.eks_cluster.eks_cluster_oidc_arn
  depends_on = [
    module.eks_cluster.eks_blueprints_addons,
  ]
}

# helm install thanos
resource "helm_release" "thanos_query" {
  count = length(module.eks_thanos) == 0 ? 0 : 1
  name       = "thanoslab-query"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "thanos"
  namespace  = "${module.eks_thanos[0].thanos_namespace}"
  wait       = false

  values = [
    file("${path.cwd}/../../../thanos-example/POC/thanos-values/thanoslab-query.yaml")
  ]
  depends_on = [
    module.eks_thanos.thanos_s3_config,
    # kubernetes_secret.prometheus_secret,
  ]
}

resource "helm_release" "thanos_ekscluster" {
  for_each = length(module.eks_thanos) == 0 ? [] : toset( ["ekscluster1", "ekscluster2", "ekscluster3"] )

  name       = "thanoslab-${each.key}"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "thanos"
  namespace  = "${module.eks_thanos[0].thanos_namespace}"
  wait       = false

  values = [
    file("${path.cwd}/../../../thanos-example/POC/thanos-values/thanoslab-${each.key}.yaml"),
  ]
  depends_on = [
    module.eks_thanos.thanos_s3_config,
    module.eks_thanos.thanos_receive_sa,
    module.eks_thanos.thanos_store_sa
  ]
}
