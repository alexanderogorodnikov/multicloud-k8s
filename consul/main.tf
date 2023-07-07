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

resource "helm_release" "consul_dc1" {
  provider   = helm.aks
  name       = "consul"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "consul"
  version    = "1.0.2"
  #
  values = [
    file("dc1.yaml")
  ]
}
#
data "kubernetes_secret" "aks_federation_secret" {
  provider = kubernetes.aks
  metadata {
    name = "consul-federation"
  }
  #
  depends_on = [helm_release.consul_dc1]
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

provider "helm" {
  alias                  = "gke"
  kubernetes {
    host  = "https://${data.google_container_cluster.gke.endpoint}"
    token = data.google_client_config.default.access_token
    cluster_ca_certificate = base64decode(
      data.google_container_cluster.gke.master_auth[0].cluster_ca_certificate,
    )
  }
}

resource "kubernetes_secret" "gke_federation_secret" {
  provider = kubernetes.gke
  metadata {
    name = "consul-federation"
  }

  data = data.kubernetes_secret.aks_federation_secret.data
}

resource "helm_release" "consul_dc2" {
  provider   = helm.gke
  name       = "consul"
  repository = "https://helm.releases.hashicorp.com"
  chart      = "consul"
  version    = "1.0.2"

  values = [
    file("dc2.yaml")
  ]

  depends_on = [
    data.kubernetes_secret.aks_federation_secret
  ]
}
