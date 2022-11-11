locals {
  # List of roles that will be assigned to the pulbisher service account
  publisher_roles = toset([
    "roles/storage.objectCreator",
    "roles/storage.objectViewer",
    "roles/artifactregistry.writer",
  ])
}

# GCR registry 
resource "google_artifact_registry_repository" "registry" {
  provider = google-beta
  project = var.project_id

  description = "Trager artifacts registry"
  location = var.registry_location
  repository_id = var.registry_name
  format = "DOCKER"
}

# Service account to be used for federated auth to publish to GCR
resource "google_service_account" "github_actions_user" {
  account_id   = "github-actions-user"
  display_name = "Service Account impersonated in GitHub Actions"
}

# Role binding to allow publisher to publish images
resource "google_artifact_registry_repository_iam_member" "github_actions_user_storage_role_binding" {
  provider   = google-beta
  project    = var.project_id
  location   = var.registry_location
  repository = google_artifact_registry_repository.registry.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.github_actions_user.email}"
}

# Identiy pool for GitHub action based identity's access to Google Cloud resources
resource "google_iam_workload_identity_pool" "github_pool" {
  provider                  = google-beta
  workload_identity_pool_id = "github-pool"
}

# Configuration for GitHub identiy provider
resource "google_iam_workload_identity_pool_provider" "github_provider" {
  provider                           = google-beta
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.aud"        = "assertion.aud"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
  oidc {
    issuer_uri        = "https://token.actions.githubusercontent.com"
    allowed_audiences = []
  }
}

# IAM policy bindings to the service account resources created by GitHub identify
resource "google_service_account_iam_member" "pool_impersonation" {
  provider           = google-beta
  service_account_id = google_service_account.github_actions_user.id
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.git_repo}"
}
