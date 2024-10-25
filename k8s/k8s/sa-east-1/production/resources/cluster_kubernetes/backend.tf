terraform {
  backend "s3" {
    bucket = "test-prod-terraform-state"
    key    = "test/sa-east-1/production/resources/cluster-kubernetes/terraform-state"
    region = "sa-east-1"
  }
}
