#!/bin/bash

set -e

export AWS_PAGER=""

CLUSTER_NAME="korea"
AWS_REGION="ap-northeast-3"

# kubeconfig 업데이트
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Helm 리포지토리 추가 및 업데이트
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
--namespace kube-system \
--set image.repository=602401143452.dkr.ecr.ap-northeast-3.amazonaws.com/eks/aws-efs-csi-driver \
--set controller.serviceAccount.create=true \
--set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(aws iam get-role --role-name AmazonEKS_EFS_CSI_DriverRole --query Role.Arn --output text)

# Grafana 배포
helm upgrade --install grafana grafana/grafana -f values-grafana.yaml --namespace=default

# Prometheus 배포
helm upgrade --install prometheus prometheus-community/prometheus -f values-prometheus.yaml --namespace=default

# Loki 배포
helm upgrade --install loki grafana/loki -f values-loki.yaml --namespace=default

# 오픈텔레메트리 배포
helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector -f values-opentelemetry-collector.yaml --namespace=default

# 배포 상태 확인
kubectl get pods
kubectl get pvc

echo "Deployment completed. You can now access your monitoring services."