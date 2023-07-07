resource "random_pet" "prefix" {}

provider "azurerm" {
  features {}
}

# AKS managed identities
resource "azurerm_user_assigned_identity" "aks_control_plane" {
    name                = "id-${random_pet.prefix.id}-controlplane"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
}

resource "azurerm_user_assigned_identity" "aks_kublet" {
    name                = "id-${random_pet.prefix.id}-kublet"
    resource_group_name = azurerm_resource_group.main.name
    location            = azurerm_resource_group.main.location
}


resource "azurerm_resource_group" "main" {
  name     = "${random_pet.prefix.id}-aks"
  location = "canadacentral"

  tags = {
    environment = "Demo"
  }
}


### Kubernetes related roles assignement
resource "azurerm_role_assignment" "aks_control_plane_manage_identity" {
    scope                = azurerm_user_assigned_identity.aks_kublet.id
    role_definition_name = "Managed Identity Operator"
    principal_id         = azurerm_user_assigned_identity.aks_control_plane.principal_id
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${random_pet.prefix.id}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${random_pet.prefix.id}-k8s"

   # Identity type
  identity {
        type = "UserAssigned"
        identity_ids = [ 
            azurerm_user_assigned_identity.aks_control_plane.id
        ] 
    }
  
  kubelet_identity {
        user_assigned_identity_id = azurerm_user_assigned_identity.aks_kublet.id
        client_id = azurerm_user_assigned_identity.aks_kublet.client_id
        object_id = azurerm_user_assigned_identity.aks_kublet.principal_id
  }

  default_node_pool {
    name            = "default"
    node_count      = 3
    vm_size         = "Standard_D2_v2"
    os_disk_size_gb = 30
  }

  azure_active_directory_role_based_access_control {
        managed = true
        admin_group_object_ids = ["c46157d9-5dc9-47b8-9083-f4e3f6057b04"]
        azure_rbac_enabled = true
  }

  tags = {
    environment = "Demo"
  }
  # AKS UserAssigned identiTy must be created first
    depends_on = [
        azurerm_user_assigned_identity.aks_control_plane,
        azurerm_user_assigned_identity.aks_kublet,
        azurerm_role_assignment.aks_control_plane_manage_identity
    ]
}
