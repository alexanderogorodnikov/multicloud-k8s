# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.10.1"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.34.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.21.1"
    }
    google = {
      source  = "hashicorp/google"
      version = "4.70.0"
    }
  }
  required_version = ">= 0.14"
}

