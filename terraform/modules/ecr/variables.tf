# ECR Module - Variables

variable "project_name" {
  description = "Project name used as prefix for repository names"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "image_tag_mutability" {
  description = "Image tag mutability setting. MUTABLE or IMMUTABLE"
  type        = string
  default     = "MUTABLE"
  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE"
  }
}

variable "scan_on_push" {
  description = "Enable image scanning on push"
  type        = bool
  default     = true
}

variable "force_delete" {
  description = "Force delete ECR repos even with images (useful for dev/test)"
  type        = bool
  default     = false
}

variable "keep_image_count" {
  description = "Number of tagged images to keep"
  type        = number
  default     = 30
}

variable "untagged_image_days" {
  description = "Days to keep untagged images before cleanup"
  type        = number
  default     = 14
}

variable "enable_cross_account_access" {
  description = "Enable cross-account access to ECR repositories"
  type        = bool
  default     = false
}

variable "allowed_principals" {
  description = "List of AWS principals allowed to pull images (for cross-account)"
  type        = list(string)
  default     = []
}
