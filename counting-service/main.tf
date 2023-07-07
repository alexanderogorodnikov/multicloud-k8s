### AKS Resources
#
data "terraform_remote_state" "aks" {
  backend = "local"
  config = {
    path = "../aks/terraform.tfstate"
  }
}

provider "azurerm" {
  features {}
}

data "azurerm_kubernetes_cluster" "cluster" {
  name                = data.terraform_remote_state.aks.outputs.kubernetes_cluster_name
  resource_group_name = data.terraform_remote_state.aks.outputs.resource_group_name
}

provider "kubernetes" {
  alias                  = "aks"
  host                   = data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.host
  username               = data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.username
  password               = data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.password
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.cluster_ca_certificate)

  experiments {
    manifest_resource = true
  }
}

provider "helm" {
  alias = "aks"
  kubernetes {
    host                   = data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.host
    client_certificate     = base64decode(data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.client_certificate)
    client_key             = base64decode(data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.client_key)
    cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.cluster.kube_admin_config.0.cluster_ca_certificate)
  }
}


### GKE Resources
data "terraform_remote_state" "gke" {
  backend = "local"
  config = {
    path = "../gke/terraform.tfstate"
  }
}


# Retrieve GKE cluster information
provider "google" {
  project = data.terraform_remote_state.gke.outputs.project_id
  region  = data.terraform_remote_state.gke.outputs.region
}

data "google_client_config" "default" {}

data "google_container_cluster" "gke" {
  name     = data.terraform_remote_state.gke.outputs.kubernetes_cluster_name
  location = data.terraform_remote_state.gke.outputs.region
}

provider "kubernetes" {
  alias = "gke"
  host  = "https://${data.google_container_cluster.gke.endpoint}"
  token = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(
    data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate,
  )
}


resource "kubernetes_pod" "counting" {
  provider = kubernetes.gke

  metadata {
    name = "counting"
    labels = {
      "app" = "counting"
    }
  }

  spec {
    container {
      image = "hashicorp/counting-service:0.0.2"
      name  = "counting"

      port {
        container_port = 9001
        name           = "http"
      }
    }
  }
}

resource "kubernetes_service" "counting" {
  provider = kubernetes.gke
  metadata {
    name      = "counting"
    namespace = "default"
    labels = {
      "app" = "counting"
    }
  }
  spec {
    selector = {
      "app" = "counting"
    }
    port {
      name        = "http"
      port        = 9001
      target_port = 9001
      protocol    = "TCP"
    }
    type = "ClusterIP"
  }
}

#resource "kubernetes_pod" "dashboard" {
#  provider = kubernetes.aks
#
#  metadata {
#    name = "dashboard"
#    annotations = {
#      "consul.hashicorp.com/connect-service-upstreams" = "counting:9001:dc2"
#      "consul.hashicorp.com/connect-inject"= "true"
#    }
#    labels = {
#      "app" = "dashboard"
#    }
#  }
#
#  spec {
#    container {
#      image = "hashicorp/dashboard-service:0.0.4"
#      name  = "dashboard"
#
#      env {
#        name  = "COUNTING_SERVICE_URL"
#        value = "http://localhost:9001"
#      }
#
#      port {
#        container_port = 9002
#        name           = "http"
#      }
#
#      
#    }
#    service_account_name = "dashboard"
#  }
#}
#

#esource "kubernetes_deployment" "dashboard" {
# provider = kubernetes.aks
#
# metadata {
#   name = "dashboard"
#   annotations = {
#     "consul.hashicorp.com/connect-service-upstreams" = "counting:9001:dc2"
#     "consul.hashicorp.com/connect-inject"= "true"
#   }
#   labels = {
#     "app" = "dashboard"
#   }
# }
# 
#
# spec {
#
#   replicas = 3
#   selector {
#     match_labels = {
#       app = "dashboard"
#     }
#   }
#
#   template {
#     metadata {
#       labels = {
#         app = "dashboard"
#       }
#     }
#
#   spec {
#     container {
#       image = "hashicorp/dashboard-service:0.0.4"
#       name  = "dashboard"
#
#       env {
#         name  = "COUNTING_SERVICE_URL"
#         value = "http://localhost:9001"
#       }
#
#       port {
#         container_port = 9002
#         name           = "http"
#       }
#
#
#     }
#   }
#   
# }
  #service_account_name = "dashboard"
#}

#}
#resource "kubernetes_service" "dashboard" {
#  provider = kubernetes.aks
#
#  metadata {
#    name      = "dashboard"
#    namespace = "default"
#    labels = {
#      "app" = "dashboard"
#    }
#  }
#
#  spec {
#    selector = {
#      "app" = "dashboard"
#    }
#    port {
#      port        = 8080
#      #port         = 666 
#      target_port = 9002
#    }
#
#    type             = "LoadBalancer"
#    #load_balancer_ip = ""
#  }
#}

resource "kubernetes_manifest" "ingress_dashboard" {
  provider = kubernetes.aks
  manifest = {
  "apiVersion" = "consul.hashicorp.com/v1alpha1"
  "kind" = "IngressGateway"
  "metadata" = {
    "name" = "ingress-gateway"
    "namespace" = "default"
  }
  "spec" = {
    "listeners" = [
      {
        "port" = 80
        "protocol" = "http"
        "services" = [
          {
            "name" = "dashboard"
          },
        ]
      },
    ]
  }
}
}

resource "kubernetes_manifest" "ingress_service_default" {
  provider = kubernetes.aks
  manifest = {
  "apiVersion" = "consul.hashicorp.com/v1alpha1"
  "kind" = "ServiceDefaults"
  "metadata" = {
    "name" = "dashboard"
    "namespace" = "default"
  }
  "spec" = {
    "protocol" = "http"
  }
}
}

##
#resource "kubernetes_manifest" "service_account_dashboard" {
#  provider = kubernetes.aks
#  manifest = {
#  "apiVersion" = "v1"
#  "kind" = "ServiceAccount"
#  "metadata" = {
#    "name" = "dashboard"
#    "namespace" = "default"
#  }
#}
#}

### tests

#resource "kubernetes_manifest" "ingress_static_server" {
#  provider = kubernetes.aks
#  manifest = {
#  "apiVersion" = "consul.hashicorp.com/v1alpha1"
#  "kind" = "IngressGateway"
#  "metadata" = {
#    "name" = "ingress-gateway"
#    "namespace" = "default"
#  }
#  "spec" = {
#    "listeners" = [
#      {
#        "port" = 8080
#        "protocol" = "http"
#        "services" = [
#          {
#            "name" = "static-server"
#          },
#        ]
#      },
#    ]
#  }
#}
#}
#
#
#resource "kubernetes_manifest" "ingress_service_default_static_server" {
#  provider = kubernetes.aks
#  manifest = {
#  "apiVersion" = "consul.hashicorp.com/v1alpha1"
#  "kind" = "ServiceDefaults"
#  "metadata" = {
#    "name" = "static-server"
#    "namespace" = "default"
#  }
#  "spec" = {
#    "protocol" = "http"
#  }
#}
#}
#
#
#resource "kubernetes_manifest" "service_account_dashboard_ss" {
#  provider = kubernetes.aks
#  manifest = {
#  "apiVersion" = "v1"
#  "kind" = "ServiceAccount"
#  "metadata" = {
#    "name" = "static-server"
#    "namespace" = "default"
#  }
#}
#}
#