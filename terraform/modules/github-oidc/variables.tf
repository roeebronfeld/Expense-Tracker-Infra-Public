# GitHub OIDC Module - Variables

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository in format owner/repo (e.g., roeebronfeld/Expense-Tracker)"
  type        = string
}

variable "github_branch" {
  description = "GitHub branch that can assume the role (e.g., main)"
  type        = string
  default     = "main"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "aws_account_id" {
  description = "AWS Account ID"
  type        = string
}
