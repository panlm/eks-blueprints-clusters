#!/bin/bash
#set -e
set -x

# Get the directory of the currently executing script (shell1.sh)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# remove helm install 
CLUSTER_NAME=$(terraform output -raw eks_cluster_id)
KUBECTL_CONFIG=$(terraform output -raw configure_kubectl)
eval ${KUBECTL_CONFIG}
# remove thanos / prometheus 
for ns in thanos monitoring ; do
  helm list -n ${ns} --no-headers |awk '{print $1}' |while read i ; do
    helm uninstall -n ${ns} $i
  done
done

{ "$SCRIPT_DIR/tear-down-applications.sh"; } || {
  echo "Error occurred while deleting application"

  # Ask the user if they want to continue
  read -p "Do you want to continue with cluster deletion (y/n)? " choice
  case "$choice" in
    y|Y ) echo "Continuing with the rest of shell1.sh";;
    * ) echo "Exiting.."; exit;;
  esac
}


#terraform destroy -target="module.eks_cluster.module.gitops_bridge_bootstrap" -auto-approve

# Then Tear down the cluster
terraform destroy -target="module.eks_cluster.module.kubernetes_addons" -auto-approve || (echo "error deleting module.eks_cluster.module.kubernetes_addons" && exit -1)
terraform destroy -target="module.eks_cluster.module.eks_blueprints_platform_teams" -auto-approve || (echo "error deleting module.eks_cluster.module.eks_blueprints_platform_teams" && exit -1)
terraform destroy -target="module.eks_cluster.module.eks_blueprints_dev_teams" -auto-approve || (echo "error deleting module.eks_cluster.module.eks_blueprints_dev_teams" && exit -1)
terraform destroy -target="module.eks_cluster.module.eks_blueprints_ecsdemo_teams" -auto-approve || (echo "error deleting module.eks_cluster.module.eks_blueprints_ecsdemo_teams" && exit -1)

terraform destroy -target="module.eks_cluster.module.gitops_bridge_bootstrap" -auto-approve || (echo "error deleting module.eks_cluster.module.gitops_bridge_bootstrap" && exit -1)
terraform destroy -target="module.eks_cluster.module.gitops_bridge_metadata" -auto-approve || (echo "error deleting module.eks_cluster.module.gitops_bridge_metadata" && exit -1)

terraform destroy -target="module.eks_cluster.module.eks_blueprints_addons" -auto-approve || (echo "error deleting module.eks_cluster.module.eks" && exit -1)

terraform destroy -target="module.eks_cluster.module.ebs_csi_driver_irsa" --auto-approve
terraform destroy -target="module.eks_cluster.module.vpc_cni_irsa" --auto-approve
terraform destroy -target="module.eks_cluster.module.eks" -auto-approve || (echo "error deleting module.eks_cluster.module.eks" && exit -1)

terraform destroy -auto-approve || (echo "error deleting terraform" && exit -1)

# remove ebs volumes used by thanos / prometheus
echo "###"
echo "### ensure EBS State is available and Tag:Name is related to the lab correctly"
echo "### execute script $SCRIPT_DIR/tear-down-ebs.sh to delete volumes manually"
echo "###"
aws ec2 describe-volumes \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=owned" \
  --query 'Volumes[*].{col1_Command:`aws ec2 delete-volume --volume-id`, col2_VolumeID:VolumeId, col3_comment:`#`, col4_State:State, col5_Name:Tags[?Key==`Name`].Value | [0]}' --output=text |tee $SCRIPT_DIR/tear-down-ebs.sh
          
echo "Tear Down OK"
set +x
