[master]
${master_ip} ansible_host=${master_ip}

[workers]
${worker1_ip} ansible_host=${worker1_ip}
${worker2_ip} ansible_host=${worker2_ip}

[k3s_cluster:children]
master
workers

[k3s_cluster:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=../ssh/id_rsa
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
ansible_python_interpreter=/usr/bin/python3
