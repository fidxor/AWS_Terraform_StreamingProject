const AWS = require('aws-sdk');
const ec2 = new AWS.EC2();
const autoscaling = new AWS.AutoScaling();
const { exec } = require('child_process');

exports.handler = async (event) => {
  const instanceId = event.detail['EC2 InstanceId'];
  const eventType = event.detail-type;

  if (eventType === 'EC2 Instance Launch Successful') {
    // 인스턴스 정보 가져오기
    const instanceData = await ec2.describeInstances({ InstanceIds: [instanceId] }).promise();
    const privateIp = instanceData.Reservations[0].Instances[0].PrivateIpAddress;

    // Kubernetes 클러스터에 노드 추가
    exec(`kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes`, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error: ${error}`);
        return;
      }
      console.log(`Nodes: ${stdout}`);
    });

    // Prometheus에 타겟 추가
    // (Prometheus 설정 업데이트 로직 구현 필요)

  } else if (eventType === 'EC2 Instance Terminate Successful') {
    // Kubernetes 클러스터에서 노드 제거
    exec(`kubectl --kubeconfig=/etc/kubernetes/admin.conf delete node ${instanceId}`, (error, stdout, stderr) => {
      if (error) {
        console.error(`Error: ${error}`);
        return;
      }
      console.log(`Node deleted: ${stdout}`);
    });

    // Prometheus에서 타겟 제거
    // (Prometheus 설정 업데이트 로직 구현 필요)
  }
};