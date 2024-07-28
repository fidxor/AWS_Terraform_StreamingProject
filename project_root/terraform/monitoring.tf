# monitoring.tf

provider "aws" {
  region = var.region
}

data "aws_instances" "control_node" {
  filter {
    name   = "tag:Name"
    values = ["*control*"]
  }

  filter {
    name   = "instance-state-name"
    values = ["running"]
  }
}

resource "null_resource" "install_monitoring_stack" {
  count = length(data.aws_instances.control_node.ids)

connection {
  type        = "ssh"
  user        = "ubuntu"
  host        = data.aws_instances.control_node.public_ips[0]
  private_key = file("~/kubernetes.mycluster.k8s.local-62:92:3f:06:ea:8a:9b:88:59:52:d5:36:f9:d6:11:a")
  timeout     = "5m"
}

  provisioner "remote-exec" {
    inline = [
      "echo 'Connection successful'",
      # Install Helm
      "curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash",

      # Add Helm repositories
      "helm repo add grafana https://grafana.github.io/helm-charts",
      "helm repo add prometheus-community https://prometheus-community.github.io/helm-charts",
      "helm repo update",

      # Create monitoring namespace
      "kubectl create namespace monitoring",

      # Create Helm chart directory
      "mkdir -p ~/monitoring-chart",
      
      # Copy chart files
      "echo '${file("Chart.yaml")}' > ~/monitoring-chart/Chart.yaml",
      "echo '${file("values.yaml")}' > ~/monitoring-chart/values.yaml",
      "echo '${file("values-loki.yaml")}' > ~/monitoring-chart/values-loki.yaml",
      "mkdir -p ~/monitoring-chart/templates",
      "echo '${file("all-resources.tpl")}' > ~/monitoring-chart/templates/all-resources.tpl",

      # Install the monitoring stack
      "helm install monitoring-stack ~/monitoring-chart -f ~/monitoring-chart/values.yaml -f ~/monitoring-chart/values-loki.yaml --namespace monitoring",

      # Wait for pods to be ready
      "kubectl wait --for=condition=Ready pods --all --namespace monitoring --timeout=300s",
    ]
  }
}

# Outputs
output "control_node_public_ip" {
  value = data.aws_instances.control_node.public_ips[0]
}

output "grafana_url" {
  value = "http://${data.aws_instances.control_node.public_ips[0]}:80"
}

output "prometheus_url" {
  value = "http://${data.aws_instances.control_node.public_ips[0]}:9090"
}