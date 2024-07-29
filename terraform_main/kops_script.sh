#!/bin/bash
export AWS_DEFAULT_REGION=ap-northeast-2

apt-get update
apt-get install -y awscli
apt-get install python3-pip

# kops 설치
curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x kops-linux-amd64
mv kops-linux-amd64 /usr/local/bin/kops

# kubectl 설치
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

apt-get install -y ansible
pip3 install ansible
sleep 10
ansible-galaxy collection install kubernetes.core

pip3 install openshift pyyaml kubernetes

# 키 저장
echo "${public_key}" > /home/ubuntu/kops_public_key.pub
echo "${private_key}" > /home/ubuntu/kops_private_key.pem

# 키 파일 권한 설정
chmod 400 /home/ubuntu/kops_public_key.pub
chmod 400 /home/ubuntu/kops_private_key.pem
chown ubuntu:ubuntu /home/ubuntu/kops_public_key.pub
chown ubuntu:ubuntu /home/ubuntu/kops_private_key.pem

# 환경변수 설정을 .bashrc와 /etc/environment에 추가
echo "export NAME=mycluster.k8s.local" >> /home/ubuntu/.bashrc
echo "export KOPS_STATE_STORE=s3://${s3bucketname}" >> /home/ubuntu/.bashrc
echo "export KUBECONFIG=/home/ubuntu/.kube/config" >> /home/ubuntu/.bashrc
echo "export SLACK_WEBHOOK_URL='${slack_webhook_url}'" >> /home/ubuntu/.bashrc
echo "export SLACK_WEBHOOK_URL='${slack_webhook_url}'" >> /etc/environment
echo "NAME=mycluster.k8s.local" >> /etc/environment
echo "KOPS_STATE_STORE=s3://${s3bucketname}" >> /etc/environment
echo "export KUBECONFIG=/home/ubuntu/.kube/config" >> /etc/environment

# 권한 변경
chown ubuntu:ubuntu /home/ubuntu/.bashrc

# 환경 변수를 현재 세션과 시스템 전체에 즉시 적용
export NAME=mycluster.k8s.local
export KOPS_STATE_STORE=s3://${s3bucketname}
export AWS_DEFAULT_REGION=ap-northeast-2
export SLACK_WEBHOOK_URL=${slack_webhook_url}
echo "export NAME=mycluster.k8s.local" >> /etc/profile
echo "export KOPS_STATE_STORE=s3://${s3bucketname}" >> /etc/profile
echo "export AWS_DEFAULT_REGION=ap-northeast-2" >> /etc/profile
echo "export KUBECONFIG=/home/ubuntu/.kube/config" >> /etc/profile
echo "export SLACK_WEBHOOK_URL='${slack_webhook_url}'" >> /etc/profile
source /etc/profile

# 새로운 프로세스에서도 환경 변수를 사용할 수 있도록 설정
echo "NAME=mycluster.k8s.local" >> /etc/environment
echo "KOPS_STATE_STORE=s3://${s3bucketname}" >> /etc/environment
echo "AWS_DEFAULT_REGION=ap-northeast-2" >> /etc/environment
echo "KUBECONFIG=/home/ubuntu/.kube/config" >> /etc/environment
echo "SLACK_WEBHOOK_URL='${slack_webhook_url}'" >> /etc/environment

# PAM 설정을 통해 환경 변수를 즉시 로드
sed -i '/^session\s*required\s*pam_env.so/s/^/#/' /etc/pam.d/common-session
echo "session required pam_env.so readenv=1" >> /etc/pam.d/common-session

# 클러스터 설정파일 생성 calico사용
su - ubuntu -c "export NAME=mycluster.k8s.local && export KOPS_STATE_STORE=s3://${s3bucketname} && kops create secret sshpublickey admin -i /home/ubuntu/kops_public_key.pub --name \$NAME"
# 클러스터 생성
su - ubuntu -c "export NAME=mycluster.k8s.local && export KOPS_STATE_STORE=s3://${s3bucketname} && kops create cluster --zones ap-northeast-2a --networking calico --ssh-public-key /home/ubuntu/kops_public_key.pub \$NAME"

# workernode 인스턴스 그룹 설정 생성
cat << 'EOF' > /home/ubuntu/ig-nodes-ap-northeast-2a.yaml
apiVersion: kops/v1alpha2
kind: InstanceGroup
metadata:
  name: nodes-ap-northeast-2a
  labels:
    kops.k8s.io/cluster: mycluster.k8s.local
spec:
  image: 099720109477/ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20240607
  machineType: t2.medium
  maxSize: 2
  minSize: 2
  nodeLabels:
    kops.k8s.io/instancegroup: nodes-ap-northeast-2a
  subnets:
  - ap-northeast-2a
  role: Node
EOF

# workernode 인스턴스 그룹 설정 적용
kops replace -f /home/ubuntu/ig-nodes-ap-northeast-2a.yaml

# 마스터노드 인스턴스 설정 생성
# workernode 인스턴스 그룹 설정 생성
cat << 'EOF' > /home/ubuntu/ig-control-plane-ap-northeast-2a.yaml
apiVersion: kops/v1alpha2
kind: InstanceGroup
metadata:
  name: control-plane-ap-northeast-2a
  labels:
    kops.k8s.io/cluster: mycluster.k8s.local
spec:
  image: 099720109477/ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20240607
  machineType: t2.medium
  maxSize: 1
  minSize: 1
  nodeLabels:
    kops.k8s.io/instancegroup: control-plane-ap-northeast-2a  
  subnets:
  - ap-northeast-2a
  role: Master
EOF

# workernode 인스턴스 그룹 설정 적용
kops replace -f /home/ubuntu/ig-control-plane-ap-northeast-2a.yaml

# kubeconfig 초기 생성 및 설정
echo "Generating initial kubeconfig..."
kops export kubecfg --name $NAME --admin
chmod 600 ~/.kube/config

# cluster 생성
kops update cluster --yes $NAME

# 클러스터 생성 완료 대기
echo "Waiting for cluster to be ready..."
start_time=$(date +%s)
end_time=$((start_time + 40*60))  # 40 minutes from now
check_count=0
total_checks=$((40*60/5))  # Total number of checks in 40 minutes

while [ $(date +%s) -lt $end_time ]; do
    kops export kubecfg --name $NAME --admin

    validation_output=$(kops validate cluster --name $NAME 2>&1)
    if echo "$validation_output" | grep -qE "Your cluster.*is ready"; then
        echo "Cluster appears to be ready. Validation successful."
        break
    else
        check_count=$((check_count + 1))
        percent=$((check_count * 100 / total_checks))
        printf "Cluster not ready yet. Checked for %d minutes. Progress: %d%%\r" $((check_count / 12)) $percent
        echo "$validation_output" | grep -E "Error|error|warning|Warning"
        sleep 5
    fi
done

if [ $(date +%s) -ge $end_time ]; then
    echo "Error: Cluster deployment timed out after 40 minutes"
    exit 1
fi

# kubeconfig 재생성 및 업데이트
echo "Updating kubeconfig..."
kops export kubecfg --name $NAME --admin
chmod 600 ~/.kube/config

# 인스턴스 정보 가져오기
echo "Fetching instance information..."

# 마스터 노드 IP 가져오기
master_ip=$(aws ec2 describe-instances --filters "Name=tag:k8s.io/role/master,Values=1" "Name=tag:KubernetesCluster,Values=$NAME" --query 'Reservations[].Instances[].PublicIpAddress' --output text | awk '{print $1}')

# 워커 노드 IP 가져오기
worker_ips=$(aws ec2 describe-instances --filters "Name=tag:k8s.io/role/node,Values=1" "Name=tag:KubernetesCluster,Values=$NAME" --query 'Reservations[].Instances[].PublicIpAddress' --output text)
worker1_ip=$(echo $worker_ips | awk '{print $1}')
worker2_ip=$(echo $worker_ips | awk '{print $2}')

# Kubespray 인벤토리 파일 생성
echo "Creating Kubespray inventory file..."
mkdir -p /home/ubuntu/ansible

cat <<EOF > /home/ubuntu/ansible/hosts.yml
all:
  vars:
    ansible_user: ubuntu
    ansible_ssh_private_key_file: /home/ubuntu/kops_private_key.pem
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    ansible_python_interpreter: /usr/bin/python3
  hosts:
    master:
      ansible_host: $master_ip
      ip: $master_ip
      access_ip: $master_ip
    worker1:
      ansible_host: $worker1_ip
      ip: $worker1_ip
      access_ip: $worker1_ip
    worker2:
      ansible_host: $worker2_ip
      ip: $worker2_ip
      access_ip: $worker2_ip
  children:
    kube_control_plane:
      hosts:
        master:
    kube_node:
      hosts:
        worker1:
        worker2:
    etcd:
      hosts:
        master:
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
EOF

cat <<EOF > /home/ubuntu/ansible/deploy_argocd.yml
---
- name: Install ArgoCD on existing Kubernetes cluster
  hosts: all
  become: yes
  vars:
    slack_webhook_url: "{{ lookup('env', 'SLACK_WEBHOOK_URL') }}"
  tasks:
    - name: Update apt cache
      apt:
        update_cache: yes
      when: ansible_os_family == "Debian"

    - name: Install pip
      package:
        name: python3-pip
        state: present

    - name: Install kubernetes Python library
      pip:
        name: kubernetes
        state: present

    - name: Read kubeconfig content
      slurp:
        src: /home/ubuntu/.kube/config
      register: kubeconfig_content
      delegate_to: localhost

    - name: Ensure .kube directory exists
      file:
        path: /home/ubuntu/.kube
        state: directory
        mode: '0755'
        owner: ubuntu
        group: ubuntu

    - name: Write kubeconfig to remote hosts
      copy:
        content: "{{ kubeconfig_content['content'] | b64decode }}"
        dest: /home/ubuntu/.kube/config
        mode: '0600'
        owner: ubuntu
        group: ubuntu

    - name: Create ArgoCD namespace
      kubernetes.core.k8s:
        kubeconfig: /home/ubuntu/.kube/config
        api_version: v1
        kind: Namespace
        name: argocd
        state: present

    - name: Apply ArgoCD installation manifest
      kubernetes.core.k8s:
        kubeconfig: /home/ubuntu/.kube/config
        state: present
        src: https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        namespace: argocd

    - name: Get ArgoCD pods info
      kubernetes.core.k8s_info:
        kubeconfig: /home/ubuntu/.kube/config
        api_version: v1
        kind: Pod
        namespace: argocd
        label_selectors:
          - app.kubernetes.io/part-of=argocd
      register: argocd_pods

    - name: Display ArgoCD pods info
      debug:
        msg:
          - "Total pods: {{ argocd_pods.resources | length }}"
          - "Pod details: {{ argocd_pods.resources | map(attribute='metadata.name') | zip(argocd_pods.resources | map(attribute='status.phase')) | list }}"

    - name: Check if all pods are running
      set_fact:
        all_pods_running: "{{ argocd_pods.resources | map(attribute='status.phase') | list | unique == ['Running'] }}"

    - name: Display all pods running status
      debug:
        msg: "All pods are running: {{ all_pods_running }}"

    - name: Wait for 2 minutes
      pause:
        minutes: 2

    - name: Force continue
      debug:
        msg: "Forcing continuation to next steps"

    - name: Patch ArgoCD server service to LoadBalancer
      kubernetes.core.k8s:
        kubeconfig: /home/ubuntu/.kube/config
        api_version: v1
        kind: Service
        name: argocd-server
        namespace: argocd
        definition:
          spec:
            type: LoadBalancer

    - name: Wait for ArgoCD server service and LoadBalancer to be ready
      kubernetes.core.k8s_info:
        kubeconfig: /home/ubuntu/.kube/config
        api_version: v1
        kind: Service
        name: argocd-server
        namespace: argocd
      register: argocd_service
      until:
        - argocd_service.resources is defined
        - argocd_service.resources | length > 0
        - argocd_service.resources[0].status is defined
        - argocd_service.resources[0].status.loadBalancer is defined
        - argocd_service.resources[0].status.loadBalancer.ingress is defined
        - argocd_service.resources[0].status.loadBalancer.ingress | length > 0
        - argocd_service.resources[0].status.loadBalancer.ingress[0].hostname is defined
        - argocd_service.resources[0].status.loadBalancer.ingress[0].hostname != ""
      retries: 30
      delay: 20
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true

    - name: Set ArgoCD server external hostname
      set_fact:
        argocd_external_hostname: "{{ argocd_service.resources[0].status.loadBalancer.ingress[0].hostname }}"
      when: argocd_service.resources is defined and argocd_service.resources | length > 0

    - name: Set ArgoCD access URL
      set_fact:
        argocd_access_url: "https://{{ argocd_external_hostname }}"
      when:
        - argocd_external_hostname is defined
        - argocd_external_hostname != ""
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true    

    - name: Get ArgoCD admin password
      shell: |
        kubectl --kubeconfig=/home/ubuntu/.kube/config -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode
      register: argocd_admin_password_result
      retries: 15
      delay: 30
      until: argocd_admin_password_result.rc == 0 and argocd_admin_password_result.stdout != ""
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true
      become: yes
      become_user: ubuntu
      environment:
        KUBECONFIG: /home/ubuntu/.kube/config

    - name: Set ArgoCD admin password fact
      set_fact:
        argocd_admin_password: "{{ argocd_admin_password_result.stdout }}"
      when: argocd_admin_password_result.stdout is defined and argocd_admin_password_result.stdout != ""
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true

    - name: Verify ArgoCD admin password
      debug:
        msg: "ArgoCD admin password: {{ argocd_admin_password | default('Not set') }}"
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true

    - name: Prepare Slack message
      set_fact:
        slack_message: |
          ArgoCD has been successfully deployed!
          Access URL: {{ argocd_access_url }}
          Initial admin password: {{ argocd_admin_password | default('Password not available') }}
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true

    - name: Send Slack notification
      uri:
        url: "{{ slack_webhook_url }}"
        method: POST
        body_format: json
        body:
          text: "{{ slack_message }}"
      register: slack_notification_result
      delegate_to: "{{ groups['kube_control_plane'][0] }}"
      run_once: true 
EOF

# 인벤토리 파일 내용 출력
cat /home/ubuntu/ansible/hosts.yml

ansible-playbook -i /home/ubuntu/ansible/hosts.yml /home/ubuntu/ansible/deploy_argocd.yml -b -v