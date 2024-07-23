#!/bin/bash
apt-get update
apt-get install -y python3-pip git
pip3 install ansible

git clone https://github.com/kubernetes-sigs/kubespray.git /home/ubuntu/kubespray
chown -R ubuntu:ubuntu /home/ubuntu/kubespray

pip3 install -r /home/ubuntu/kubespray/requirements.txt

mkdir -p /home/ubuntu/.ssh
echo '${tls_private_key}' > /home/ubuntu/.ssh/id_rsa
chmod 600 /home/ubuntu/.ssh/id_rsa
chown ubuntu:ubuntu /home/ubuntu/.ssh/id_rsa

echo "Host 10.0.*.*" >> /home/ubuntu/.ssh/config
echo "    StrictHostKeyChecking no" >> /home/ubuntu/.ssh/config
echo "    UserKnownHostsFile /dev/null" >> /home/ubuntu/.ssh/config
chmod 600 /home/ubuntu/.ssh/config
chown ubuntu:ubuntu /home/ubuntu/.ssh/config

cp -rfp /home/ubuntu/kubespray/inventory/sample /home/ubuntu/kubespray/inventory/mycluster
chown -R ubuntu:ubuntu /home/ubuntu/kubespray/inventory/mycluster

chmod +x /home/ubuntu/kubespray/contrib/inventory_builder/inventory.py

cat <<EOF > /home/ubuntu/kubespray/inventory/mycluster/hosts.yml
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
  hosts:
    master:
      ansible_host: ${master_ip}
      ip: ${master_ip}
      access_ip: ${master_ip}
    worker1:
      ansible_host: ${worker1_ip}
      ip: ${worker1_ip}
      access_ip: ${worker1_ip}
    worker2:
      ansible_host: ${worker2_ip}
      ip: ${worker2_ip}
      access_ip: ${worker2_ip}
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

chown ubuntu:ubuntu /home/ubuntu/kubespray/inventory/mycluster/hosts.yml

mkdir -p /home/ubuntu/ansible_deploy

cat <<EOF > /home/ubuntu/ansible_deploy/requirements.yml
---
collections:
  - community.kubernetes

roles:
  - name: geerlingguy.pip
EOF

pip install kubernetes

ansible-galaxy collection install community.kubernetes

ansible-galaxy install -r /home/ubuntu/ansible_deploy/requirements.yml

ansible-galaxy collection install -r /home/ubuntu/ansible_deploy/requirements.yml

cat <<EOF > /home/ubuntu/ansible_deploy/deploy_argocd.yml
---
- name: Ensure Python requirements are installed
  hosts: all
  become: yes
  tasks:
    - name: Install pip
      apt:
        name: python3-pip
        state: present
      when: ansible_os_family == "Debian"

    - name: Install kubernetes and openshift Python packages
      pip:
        name:
          - kubernetes
          - openshift
        state: present

- name: Deploy ArgoCD to Kubernetes
  hosts: kube_control_plane
  become: yes
  tasks:
    - name: Create ArgoCD namespace
      kubernetes.core.k8s:
        api_version: v1
        kind: Namespace
        name: argocd
        state: present

    - name: Download ArgoCD installation manifest
      get_url:
        url: https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
        dest: /tmp/argocd-install.yaml

    - name: Split ArgoCD installation manifest
      shell: csplit -z /tmp/argocd-install.yaml '/^---$/' '{*}'
      args:
        chdir: /tmp

    - name: Apply split ArgoCD installation manifests
      kubernetes.core.k8s:
        src: "/tmp/xx{{ item }}"
        state: present
        namespace: argocd
      with_fileglob:
        - "/tmp/xx*"

    - name: Patch ArgoCD server service to LoadBalancer type with annotations
      kubernetes.core.k8s:
        api_version: v1
        kind: Service
        name: argocd-server
        namespace: argocd
        definition:
          metadata:
            annotations:
              service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
              service.beta.kubernetes.io/aws-load-balancer-internal: "false"
              service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
          spec:
            type: LoadBalancer
            ports:
              - name: http
                port: 80
                targetPort: 8080
              - name: https
                port: 443
                targetPort: 8080

    - name: Wait for LoadBalancer to be ready
      kubernetes.core.k8s_info:
        api_version: v1
        kind: Service
        name: argocd-server
        namespace: argocd
      register: lb_service
      until: lb_service.resources[0].status.loadBalancer.ingress is defined
      retries: 30
      delay: 10

    - name: Get LoadBalancer URL
      set_fact:
        argocd_url: "http://{{ lb_service.resources[0].status.loadBalancer.ingress[0].hostname }}"

    - name: Display ArgoCD URL
      debug:
        msg: "ArgoCD is accessible at {{ argocd_url }}"

    - name: Get ArgoCD admin password
      shell: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
      register: argocd_password

    - name: Display ArgoCD admin password
      debug:
        msg: "ArgoCD admin password: {{ argocd_password.stdout }}"
EOF