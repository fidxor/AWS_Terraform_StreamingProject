#!/bin/bash

set -e

export AWS_PAGER=""

CLUSTER_NAME="streaming-cluster"
AWS_REGION="ap-northeast-2"  # 한국 리전으로 변경

# kubeconfig 업데이트
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# Helm 리포지토리 추가 및 업데이트
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update

# EFS CSI 드라이버 설치
helm upgrade --install aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
  --namespace kube-system \
  --set image.repository=602401143452.dkr.ecr.ap-northeast-2.amazonaws.com/eks/aws-efs-csi-driver \
  --set controller.serviceAccount.create=true \
  --set controller.serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=$(aws iam get-role --role-name AmazonEKS_EFS_CSI_DriverRole --query Role.Arn --output text)

# EFS 파일시스템 생성 (이미 존재하지 않는 경우)
EFS_ID=$(aws efs create-file-system --region $AWS_REGION --performance-mode generalPurpose --query 'FileSystemId' --output text)
echo "Created EFS file system with ID: $EFS_ID"

# VPC ID 가져오기
VPC_ID=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.vpcId" --output text)

# 보안 그룹 생성
SG_ID=$(aws ec2 create-security-group --group-name MyEfsSecurityGroup --description "My EFS security group" --vpc-id $VPC_ID --query 'GroupId' --output text)

# 보안 그룹 규칙 추가
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 2049 --cidr $VPC_CIDR

# 서브넷 ID 가져오기
SUBNET_IDS=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.resourcesVpcConfig.subnetIds" --output text)

# EFS 마운트 타겟 생성
for SUBNET_ID in $SUBNET_IDS; do
  aws efs create-mount-target --file-system-id $EFS_ID --subnet-id $SUBNET_ID --security-groups $SG_ID
done

# StorageClass 생성
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
parameters:
  provisioningMode: efs-ap
  fileSystemId: $EFS_ID
  directoryPerms: "700"
EOF

# Grafana 배포
helm upgrade --install grafana grafana/grafana -f values-grafana.yaml --namespace=monitoring --create-namespace

# Prometheus 배포
helm upgrade --install prometheus prometheus-community/prometheus -f values-prometheus.yaml --namespace=monitoring

# Loki 배포
helm upgrade --install loki grafana/loki -f values-loki.yaml --namespace=monitoring

# 오픈텔레메트리 배포
helm upgrade --install opentelemetry-collector open-telemetry/opentelemetry-collector -f values-opentelemetry-collector.yaml --namespace=monitoring

# 배포 상태 확인 (약간의 대기 시간 추가)
echo "Waiting for pods to start..."
sleep 60
kubectl get pods -n monitoring
kubectl get pvc -n monitoring

echo "Deployment completed. You can now access your monitoring services."