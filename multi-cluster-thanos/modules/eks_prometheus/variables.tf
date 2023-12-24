variable "cluster_name" {
  description = "eks cluster name"
  type        = string
  default     = ""
}

variable "cluster_oidc" {
  description = "eks cluster oidc arn"
  type        = string
  default     = ""
}

variable "cluster_endpoint" {
  description = "eks cluster endpoint"
  type        = string
  default     = ""
}

variable "cluster_ca_data" {
  description = "eks cluster ca data"
  type        = string
  default     = ""
}

variable "blueprints_addons" {
  description = "eks cluster ca data"
  type        = any
  default     = []
}
