# Folder List
- multi-cluster-thanos: how to create multi eks cluster for thanos lab [link](https://panlm.github.io/EKS/solutions/monitor/POC-prometheus-ha-architect-with-thanos/)
- eks-cluster-in-china-region: verified to create eks cluster in AWS China regions
- eks-graviton: lab for graviton ec2 node in eks cluster
- eks-win: lab for windows ec2 node in eks cluster for gmsa domainless scenario

# refer
- https://github.com/aws-ia/terraform-aws-eks-blueprints/tree/main/patterns/blue-green-upgrade

# quick guide
- refer: https://panlm.github.io/EKS/cluster/eks-cluster-with-terraform/
- quick create a route53 hosted zone
```sh
curl -sL -o /tmp/func-create-hosted-zone.sh https://panlm.github.io/CLI/functions/func-create-hosted-zone.sh
source /tmp/func-create-hosted-zone.sh

DATE=$(TZ=EAT-8 date +%m%d)
PARENT_DOMAIN_NAME=eks${DATE}.aws.panlm.xyz
create-hosted-zone -n ${PARENT_DOMAIN_NAME}
```


