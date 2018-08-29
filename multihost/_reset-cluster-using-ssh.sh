#!/bin/bash

# usage: ./multihost/_reset-cluster-using-ssh.sh dev ceph
# optional usage: ./multihost/_reset-cluster-using-ssh.sh dev ceph labeler=/opt/deploy-to-kubernetes/multihost/run.sh dockerdir=/var/lib/docker deploy_dir=/opt/deploy-to-kubernetes rookdir=/var/lib/rook

found_colors="./tools/bash_colors.sh"
if [[ "${DISABLE_COLORS}" == "" ]] && [[ "${found_colors}" != "" ]] && [[ -e ${found_colors} ]]; then
    . ${found_colors}
elif [[ "${DISABLE_COLORS}" == "" ]] && [[ "../${found_colors}" != "" ]] && [[ -e ../${found_colors} ]]; then
    . ${found_colors}
else
    inf() {
        echo "$@"
    }
    anmt() {
        echo "$@"
    }
    good() {
        echo "$@"
    }
    err() {
        echo "$@"
    }
    critical() {
        echo "$@"
    }
    warn() {
        echo "$@"
    }
fi

# this assumes the current user has root ssh access to the following hosts:
# master1.example.com
# master2.example.com
# master3.example.com
initial_master="master1.example.com"
secondary_nodes="master2.example.com master3.example.com"
nodes="${initial_master} ${secondary_nodes}"
login_user="root"
cert_env="dev"
docker_data_dir="/data/docker/*"
deploy_dir="/opt/deploy-to-kubernetes"
rook_dir="/var/lib/rook"
multihost_labeler="./multihost/run.sh"
should_cleanup_before_startup=0
deploy_suffix=""
deploy_splunk="splunk"
deploy_resources="1"
deploy_stack="1"
use_go_dir="~/go"
use_go_path_value="PATH=\$PATH:${use_go_dir}/bin"
use_go_exports="export GOPATH=${use_go_dir} && export ${use_go_path_value}"
storage_type="ceph"
object_store=""
namespace="default"
delete_docker="0"
apply_dns="1"
debug="0"
for i in "$@"
do
    contains_equal=$(echo ${i} | grep "=")
    if [[ "${i}" == "prod" ]]; then
        cert_env="prod"
    elif [[ "${i}" == "ceph" ]]; then
        storage_type="ceph"
    elif [[ "${i}" == "cephs3" ]]; then
        storage_type="ceph"
        object_store="ceph"
    elif [[ "${i}" == "-d" ]]; then
        debug="1"
    elif [[ "${i}" == "clean_on_start" ]]; then
        should_cleanup_before_startup="1"
    elif [[ "${i}" == "deletedocker" ]]; then
        delete_docker="1"
    elif [[ "${i}" == "nodns" ]]; then
        apply_dns="0"
    elif [[ "${i}" == "nostorage" ]]; then
        storage_type=""
    elif [[ "${i}" == "nosplunk" ]]; then
        deploy_splunk=""
    elif [[ "${i}" == "noresources" ]]; then
        deploy_resources="0"
    elif [[ "${i}" == "nostack" ]]; then
        deploy_stack="0"
    elif [[ "${contains_equal}" != "" ]]; then
        first_arg=$(echo ${i} | sed -e 's/=/ /g' | awk '{print $1}')
        second_arg=$(echo ${i} | sed -e 's/=/ /g' | awk '{print $2}')
        if [[ "${first_arg}" == "labeler" ]]; then
            multihost_labeler=${second_arg}
        elif [[ "${first_arg}" == "dockerdir" ]]; then
            docker_data_dir=${second_arg}
        elif [[ "${first_arg}" == "deploydir" ]]; then
            deploy_dir=${second_arg}
        elif [[ "${first_arg}" == "rookdir" ]]; then
            rook_dir=${second_arg}
        elif [[ "${first_arg}" == "gopath" ]]; then
            use_go_dir=${second_arg}
            use_go_path_value="PATH=\$PATH:${use_go_dir}"
            use_go_exports="export GOPATH=${use_go_dir} && export ${use_go_path_value}"
        fi
    elif [[ "${i}" == "antinex" ]]; then
        cert_env="an"
    elif [[ "${i}" == "qs" ]]; then
        cert_env="qs"
    elif [[ "${i}" == "redten" ]]; then
        cert_env="redten"
    fi
done


anmt "---------------------------------------------------------"
anmt "resetting kubernetes multihost cluster on nodes: ${nodes}"
inf ""

for i in $nodes; do
    anmt "resetting kubernetes on ${i}: ssh ${login_user}@${i} 'kubeadm reset -f'"
    ssh ${login_user}@${i} "kubeadm reset -f" &
    sleep 2
    ssh ${login_user}@${i} "systemctl stop docker && kubeadm reset -f && systemctl start docker"
done
inf ""

for i in $nodes; do
    anmt "resetting flannel networking on ${i}: ssh ${login_user}@${i} 'cd ${deploy_dir}; ./tools/reset-flannel-cni-networks.sh'"
    ssh ${login_user}@${i} "cd ${deploy_dir}; ./tools/reset-flannel-cni-networks.sh"
done
inf ""

# https://blog.heptio.com/properly-resetting-your-kubeadm-bootstrapped-cluster-nodes-heptioprotip-473bd0b824aa
for i in $nodes; do
    anmt "resetting iptables on ${i}: ssh ${login_user}@${i} 'iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X'"
    ssh ${login_user}@${i} "iptables -F && iptables -t nat -F && iptables -t mangle -F && iptables -X"
done
inf ""

if [[ "${delete_docker}" == "1" ]]; then
    for i in $nodes; do
        anmt "stopping docker on ${i}: ssh ${login_user}@${i} 'systemctl stop docker'"
        ssh ${login_user}@${i} "systemctl stop docker"
    done
    inf ""

    for i in $nodes; do
        anmt "cleaning up docker directories on ${i}: ssh ${login_user}@${i} 'rm -rf ${docker_data_dir}'"
        ssh ${login_user}@${i} "rm -rf ${docker_data_dir}"
    done
    inf ""
fi

for i in $nodes; do
    anmt "deleting ${rook_dir} on ${i}: ssh ${login_user}@${i} 'rm -rf ${rook_dir}'"
    ssh ${login_user}@${i} "rm -rf ${rook_dir}"
done
inf ""

if [[ "${apply_dns}" == "1" ]];then
    for i in $nodes; do
        anmt "applying netplan dns on ${i}: ssh ${login_user}@${i} 'netplan apply'"
        ssh ${login_user}@${i} "netplan apply"
    done
    inf ""
fi

for i in $nodes; do
    anmt "starting docker on ${i}: ssh ${login_user}@${i} 'systemctl start docker; systemctl status docker'"
    ssh ${login_user}@${i} "systemctl start docker; systemctl status docker"
done
inf ""

anmt "starting cluster initial master node on ${initial_master} in ${deploy_dir}: cert_env=${cert_env}; cd ${deploy_dir}; export KUBECONFIG=/etc/kubernetes/admin.conf && ${deploy_dir}/tools/cluster-reset.sh ; ${deploy_dir}/user-install-kubeconfig.sh"
ssh ${login_user}@${initial_master} "cert_env=${cert_env}; cd ${deploy_dir}; export KUBECONFIG=/etc/kubernetes/admin.conf && ${deploy_dir}/tools/cluster-reset.sh ; ${deploy_dir}/user-install-kubeconfig.sh"
inf ""

if [[ ! -e ~/.kube ]]; then
    mkdir -p -m 777 ~/.kube
fi

anmt "copying kubernetes config to local using: scp ${login_user}@${initial_master}:/etc/kubernetes/admin.conf ~/.kube/config"
scp ${login_user}@${initial_master}:/etc/kubernetes/admin.conf ~/.kube/config
inf ""

for i in ${nodes}; do
    anmt "installing kubernetes config on ${i} using: scp ${login_user}@${initial_master}:/etc/kubernetes/admin.conf ${login_user}@${i}:~/.kube/config"
    ssh ${login_user}@${i} "mkdir -p -m 777 ~/.kube >> /dev/null"
    scp ${login_user}@${initial_master}:/etc/kubernetes/admin.conf ${login_user}@${i}:~/.kube/config
done
inf ""

anmt "generating kubernetes cluster join command: ssh ${login_user}@${initial_master} 'kubeadm token create --print-join-command > /root/k8join'"
ssh ${login_user}@${initial_master} "kubeadm token create --print-join-command > /root/k8join"
inf ""

anmt "getting kubernetes cluster join command: ssh ${login_user}@${initial_master} 'cat /root/k8join'"
cluster_join_command=$(ssh ${login_user}@${initial_master} "cat /root/k8join")
inf " - join nodes with command: ${cluster_join_command}"
inf ""

for i in $secondary_nodes; do
    anmt "joining kubernetes cluster on ${i}: ssh ${login_user}@${i} '${cluster_join_command}'"
    ssh ${login_user}@${i} "${cluster_join_command}"
done
inf ""

anmt "waiting for cluster nodes to be ready: $(date -u +'%Y-%m-%d %H:%M:%S')"
not_done="1"
sleep_count=0
while [[ "${not_done}" == "1" ]]; do
    for i in ${nodes}; do
        cluster_status=$(ssh ${login_user}@${i} "kubectl get nodes -o wide --show-labels | grep NotReady | wc -l")
        if [[ "${cluster_status}" == "0" ]]; then
            good "cluster nodes are ready"
            not_done="0"
            break
        else
            sleep_count=$((sleep_count+1))
            if [[ ${sleep_count} -gt 30 ]]; then
                inf " - still waiting $(date -u +'%Y-%m-%d %H:%M:%S')"
                sleep_count=0
            fi
            sleep 1
        fi
    done
done
inf ""

if [[ -e ${multihost_labeler} ]]; then
    anmt "applying multihost labels using command: ${multihost_labeler}"
    ${multihost_labeler}
    inf ""
fi

anmt "getting cluster status"
kubectl get nodes -o wide --show-labels
inf ""

if [[ "${deploy_resources}" == "1" ]]; then
    anmt "deploying resources using: ssh ${login_user}@${initial_master} 'cert_env=${cert_env} && cd ${deploy_dir} && export KUBECONFIG=/etc/kubernetes/admin.conf && ${use_go_exports} && ${deploy_dir}/deploy-resources.sh ${deploy_splunk} ${storage_type} ${cert_env}'"
    ssh ${login_user}@${initial_master} "cert_env=${cert_env} && cd ${deploy_dir} && export KUBECONFIG=/etc/kubernetes/admin.conf && ${use_go_exports} && ${deploy_dir}/deploy-resources.sh ${deploy_splunk} ${storage_type} ${cert_env}"
    inf ""
fi

if [[ "${deploy_stack}" == "1" ]]; then
    anmt "deploying stack using: ssh ${login_user}@${initial_master} 'cert_env=${cert_env} && cd ${deploy_dir} && export KUBECONFIG=/etc/kubernetes/admin.conf && ${use_go_exports} && ${deploy_dir}/start.sh ${deploy_splunk} ${storage_type} ${cert_env}'"
    ssh ${login_user}@${initial_master} "cert_env=${cert_env} && cd ${deploy_dir} && export KUBECONFIG=/etc/kubernetes/admin.conf && ${use_go_exports} && ${deploy_dir}/start.sh ${deploy_splunk} ${storage_type} ${cert_env}"
    inf ""
fi

if [[ "${deploy_resources}" == "1" ]] || [[ "${deploy_stack}" == "1" ]]; then
    anmt "getting cluster status"
    kubectl get nodes -o wide --show-labels
    inf ""
fi

exit 0
