output "thanos_s3_config" {
  description = "The name of thanos secret."
  value       = kubernetes_secret.thanos_secret #["ekscluster1"].metadata[0].name
}

output "thanos_store_sa" {
  description = "The name of thanos store sa."
  value       = kubernetes_service_account.thanos_store_sa #["ekscluster1"].metadata[0].name
}

output "thanos_receive_sa" {
  description = "The name of thanos store sa."
  value       = kubernetes_service_account.thanos_receive_sa #["ekscluster1"].metadata[0].name
}

output "thanos_namespace" {
  description = "The name of thanos namespace."
  value       = kubernetes_namespace.ns_thanos.metadata[0].name
}


