# You should update the below variables

aws_region          = "cn-northwest-1"
environment_name    = "zhy"
cluster_version     = "1.27"
hosted_zone_name    = "eks1217.aws.panlm.xyz" # your Existing Hosted Zone
eks_admin_role_name = "panlm" # Additional role admin in the cluster (usually the role I use in the AWS console)

gitops_addons_org      = "https://github.com/aws-samples"
gitops_addons_repo     = "eks-blueprints-add-ons"
gitops_addons_path     = "argocd/bootstrap/control-plane/addons"
gitops_addons_basepath = "argocd/"

# EKS Blueprint Workloads ArgoCD App of App repository
#gitops_workloads_org      = "git@github.com:aws-samples"
#gitops_workloads_repo     = "eks-blueprints-workloads"
#gitops_workloads_revision = "main"
#gitops_workloads_path     = "envs/dev"


#Secret manager secret for github ssk jey
#aws_secret_manager_git_private_ssh_key_name = "github-blueprint-ssh-key"

# for china region eks suffix
cluster_iam_role_dns_suffix = "amazonaws.com"
