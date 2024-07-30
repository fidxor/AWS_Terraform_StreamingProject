#!/bin/bash

set -e

export AWS_PAGER=""

CLUSTER_NAME="streaming-cluster"
AWS_REGION="ap-northeast-2"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# kubeconfig 업데이트
aws eks update-kubeconfig --name $CLUSTER_NAME --region $AWS_REGION

# IAM OIDC 제공자 생성 (이미 존재하는 경우 무시)
echo "Creating IAM OIDC provider for the EKS cluster (if not exists)"
OIDC_PROVIDER=$(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///")
if ! aws iam list-open-id-connect-providers | grep -q $(aws eks describe-cluster --name $CLUSTER_NAME --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///"); then
    echo "Fetching OpenID Connect provider thumbprint..."
    THUMBPRINT=$(echo | openssl s_client -servername oidc.eks.${AWS_REGION}.amazonaws.com -showcerts -connect oidc.eks.${AWS_REGION}.amazonaws.com:443 2>&- | openssl x509 -in /dev/stdin -sha1 -noout -fingerprint | sed 's/://g' | awk -F= '{print tolower($2)}')
    echo "Thumbprint: ${THUMBPRINT}"
    
    aws iam create-open-id-connect-provider \
        --url https://${OIDC_PROVIDER} \
        --client-id-list sts.amazonaws.com \
        --thumbprint-list ${THUMBPRINT}
fi

# EBS CSI 드라이버를 위한 IAM 역할 생성 (이미 존재하는 경우 무시)
echo "Creating IAM role for EBS CSI Driver (if not exists)"
TRUST_RELATIONSHIP=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/${OIDC_PROVIDER}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_PROVIDER}:sub": "system:serviceaccount:kube-system:ebs-csi-controller-sa"
        }
      }
    }
  ]
}
EOF
)

if ! aws iam get-role --role-name AmazonEKS_EBS_CSI_DriverRole 2>/dev/null; then
    aws iam create-role --role-name AmazonEKS_EBS_CSI_DriverRole --assume-role-policy-document "$TRUST_RELATIONSHIP"
    aws iam attach-role-policy --role-name AmazonEKS_EBS_CSI_DriverRole --policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy
fi

# StorageClass 생성 또는 업데이트
echo "Creating or updating StorageClass"
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-sc
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
EOF

# EBS CSI 드라이버 파드 재시작
echo "Restarting EBS CSI controller deployment"
kubectl rollout restart deployment ebs-csi-controller -n kube-system
kubectl rollout status deployment ebs-csi-controller -n kube-system

# 기존 PVC 삭제
echo "Deleting existing PVCs"
kubectl delete pvc --all

# Helm 차트 업그레이드
echo "Upgrading Helm charts"
helm upgrade --install grafana grafana/grafana -f values-grafana.yaml --force
helm upgrade --install prometheus prometheus-community/prometheus -f values-prometheus.yaml --force
helm upgrade --install loki grafana/loki -f values-loki.yaml --force

# 롤아웃 상태 확인
echo "Waiting for deployments to be ready..."
kubectl rollout status deployment/grafana --timeout=300s
kubectl rollout status deployment/prometheus-server --timeout=300s
kubectl rollout status statefulset/loki --timeout=300s

# 서비스 상태 확인
kubectl get services

echo "Deployment completed. You can now access your monitoring services."

# Grafana 상태 확인 및 재시작
echo "Checking Grafana status..."
kubectl get pods | grep grafana
kubectl logs $(kubectl get pods -l app.kubernetes.io/name=grafana -o jsonpath="{.items[0].metadata.name}")
echo "Restarting Grafana deployment..."
kubectl rollout restart deployment grafana
kubectl rollout status deployment grafana --timeout=300s

# 모든 파드의 상태 확인
echo "Checking all pod statuses..."
kubectl get pods

# 서비스 상태 확인
echo "Checking service statuses..."
kubectl get services

# 디버깅 정보
echo "Debug information:"
kubectl get pods
kubectl get pvc
kubectl describe pvc
kubectl get events --sort-by='.lastTimestamp'