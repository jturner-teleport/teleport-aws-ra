variable "teleport_addr" {
  description = "Teleport proxy address, e.g. example.teleport.sh:443"
  type        = string
}

variable "teleport_identity_file" {
  description = "Path to a tbot/MachineID identity file used to auth the Teleport provider."
  type        = string
  default     = "identity"
}

# AWS per-account credentials for Option A (static keys) in providers.tf.
# Optional (default null) so Option B (assume-role) users can leave them unset.
variable "provider_1_access_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "provider_1_secret_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "provider_2_access_key" {
  type      = string
  sensitive = true
  default   = null
}

variable "provider_2_secret_key" {
  type      = string
  sensitive = true
  default   = null
}
