variable "region" {
  default     = "us-east1"
  type        = string
  description = "Region for the resource."
}

variable "location" {
  default = "us-east1-c"
  description = "Location represents region/zone for the resource."
}
variable "location2" {
  default = "us-east1-b"
  description = "Location represents region/zone for the resource."
}
variable "location3" {
  default = "us-east1-d"
  description = "Location represents region/zone for the resource."
}

variable "project_id" {
  description = "The GCP project to use for integration tests"
  type        = string
  default     = "project-ccastrillon"
}

variable "network_name" {
  type        = string  
  default     = "tf-lab"
}
variable "group1_name" {
  type        = string
  default     = "group1"
}

variable "gw_group1" {
  type        = string
  default     = "gw-group1"
}

variable "cloud-nat-group1" {
  type        = string
  default     = "nat-group1"
}

variable "mig_name" {
  type        = string
  default     = "cepf-infra-lb-group1-mig"
}

variable "lb_name" {
  type        = string
  default     = "cepf-infra-lb"
}

variable "backend_name" {
  type        = string
  default     = "cepf-infra-lb-backend-default"
}

variable "database_name" {
  type        = string  
  default     = "cepf-instance"
}

variable "database_version" {
  type        = string
  default     = "POSTGRES_14"
}

variable "db_edition" {
  default     = "ENTERPRISE"
}

variable "db_password" {
  type        = string
  default     = "postgres"
}



