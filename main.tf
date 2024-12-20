provider "google" {
  region = var.region
  project = var.project_id
}

resource "google_sql_database_instance" "master" {
  name                 = var.database_name
  project              = var.project_id
  region               = var.region
  database_version     = var.database_version
  root_password        = var.db_password
  deletion_protection  = false

  settings{
    tier                 = "db-custom-1-3840"
    edition              = var.db_edition
  }
}
resource "google_compute_network" "default" {
  name                    = var.network_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "group1" {
  name                     = var.group1_name
  project                  = var.project_id
  ip_cidr_range            = "10.127.0.0/20"
  network                  = google_compute_network.default.self_link
  region                   = var.region
  private_ip_google_access = true
}

# Router and Cloud NAT are required for installing packages from repos (apache, php etc)
resource "google_compute_router" "group1" {
  name    = var.gw_group1
  network = google_compute_network.default.self_link
  region  = var.region
  project = var.project_id

}

module "cloud-nat-group1" {
  source     = "terraform-google-modules/cloud-nat/google"
  version    = "~> 5.0"
  router     = google_compute_router.group1.name
  project_id = var.project_id
  region     = var.region
  name       = var.cloud-nat-group1
}

data "google_compute_image" "my_image" {
  family  = "debian-11"
  project = "debian-cloud"
}

resource "google_compute_instance_template" "default" {
  name_prefix       = "instance-template-"
  machine_type      = "e2-medium"
  region            = var.region
  network_interface {
    network = google_compute_network.default.self_link
    subnetwork = var.group1_name
  } 
  // boot disk
  disk {
    source_image = data.google_compute_image.my_image.self_link
    auto_delete  = true
    boot         = true
  }
  shielded_instance_config {
  enable_secure_boot = true
  }
  metadata = {
    startup-script = <<-EOF1
      #! /bin/bash
      gsutil cp -r gs://cloud-training/cepf/cepf020/flask_cloudsql_example_v1.zip .
      apt-get install zip unzip wget python3-venv -y
      unzip flask_cloudsql_example_v1.zip
      cd flask_cloudsql_example/sqlalchemy
      wget https://dl.google.com/cloudsql/cloud_sql_proxy.linux.amd64 -O cloud_sql_proxy
      chmod +x cloud_sql_proxy
      export INSTANCE_HOST='127.0.0.1'
      export DB_PORT='5432'
      export DB_USER='postgres'
      export DB_PASS='postgres'
      export DB_NAME='cepf-db'
      CONNECTION_NAME=$(gcloud sql instances describe cepf-instance --format="value(connectionName)")
      nohup ./cloud_sql_proxy -instances=$${CONNECTION_NAME}=tcp:5432 &
      python3 -m venv env
      source env/bin/activate
      pip install -r requirements.txt
      sed -i 's/127.0.0.1/0.0.0.0/g' app.py
      sed -i 's/8080/80/g' app.py
      nohup python app.py &

      cat <<EOF > /var/www/html/index.html
      <pre>
      Name: $NAME
      IP: $IP
      Metadata: $METADATA
      </pre>
      EOF
    EOF1

  }
}


resource "google_compute_region_instance_group_manager" "default" { 
  name = var.mig_name
  base_instance_name = "app"
  region = var.region
  distribution_policy_zones = [var.location,var.location2,var.location3]
  version {
    instance_template = "${google_compute_instance_template.default.self_link}"
  }

#  target_pools = [google_compute_target_pool.default.id] 
  target_size = 2
  named_port {
    name = "customhttp"
    port = "8080"
  }
}

#resource "google_compute_instance_group_manager" "default" {
#  name               = var.mig_name
#  project            = var.project_id
#  description        = "compute VM Instance Group"
#  base_instance_name = "app"
#  zone = var.location
#  version {
#  instance_template = "${google_compute_instance_template.default.self_link}"
#  }

#  target_size = 1

#  named_port {
#    name = "customhttp"
#    port = "8080"
#  }
#}

resource "google_compute_region_autoscaler" "default" {

  name       = "my-autoscaler"
  region       = var.region
  target     = google_compute_region_instance_group_manager.default.id

  autoscaling_policy {
    max_replicas    = 4
    min_replicas    = 2
    cooldown_period = 60
    
    cpu_utilization {
      target = 0.6
    }
  }
}

resource "google_compute_health_check" "default" {
  name                = "autohealing-health-check"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 10 # 50 seconds

  http_health_check {
    request_path = "/health_check"
    port         = "80"
  }
}

# reserved IP address
resource "google_compute_global_address" "default" {
  provider   = google-beta
  name       = "l7-xlb-static-ip"
  project    = var.project_id
}

# forwarding rule
resource "google_compute_global_forwarding_rule" "default" {
  name                  = var.lb_name
  provider              = google-beta
  project               = var.project_id
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  port_range            = "80"
  target                = google_compute_target_http_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

# http proxy
resource "google_compute_target_http_proxy" "default" {
  name       = "l7-xlb-target-http-proxy"
  provider   = google-beta
  project    = var.project_id
  url_map    = google_compute_url_map.default.id
}

# url map
resource "google_compute_url_map" "default" {
  name            = var.lb_name
  provider        = google-beta
  project         = var.project_id
  default_service = google_compute_backend_service.default.id
}

# backend service with custom request and response headers
resource "google_compute_backend_service" "default" {
  name                     = var.backend_name
  provider                 = google-beta
  project                  = var.project_id
  protocol                 = "HTTP"
  port_name                = "http"
  load_balancing_scheme    = "EXTERNAL"
  session_affinity         = "GENERATED_COOKIE"
  timeout_sec              = 10
  enable_cdn               = true
  custom_request_headers   = ["X-Client-Geo-Location: {client_region_subdivision}, {client_city}"]
  custom_response_headers  = ["X-Cache-Hit: {cdn_cache_status}"]
  health_checks            = [google_compute_health_check.default.id]
  backend {
    group           = google_compute_region_instance_group_manager.default.instance_group
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_instance_group_named_port" "http" {
  group           = google_compute_region_instance_group_manager.default.instance_group
  zone = var.location

  name = "http"
  port = 8080
}


