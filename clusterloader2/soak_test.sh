#!/bin/bash
# Copyright 2017 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

CLUSTER_NAME=$1
KUBERNETES_VERSION="v1.23.4"
CP_MACHINE_COUNT=1
WORKER_MACHINE_COUNT=1
FLAVOR="windows-containerd"
CAPZ_YAML="./yamls/${CLUSTER_NAME}.yaml"
CLUSTER_KUBECONFIG=${HOME}/.kube/${CLUSTER_NAME}.kubeconfig

CNI_URL="https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-azure/main/templates/addons/calico.yaml"
CNI_WINDOWS_URL="https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-azure/main/templates/addons/windows/calico/calico.yaml"

AZURE_DISKS_URL="https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-azure/main/templates/addons/storageclass-azure-disk.yaml"
CSI_PROXY_URL="https://raw.githubusercontent.com/kubernetes-sigs/cluster-api-provider-azure/main/templates/addons/windows/csi-proxy/csi-proxy.yaml"

# Generate CAPZ templates
clusterctl generate cluster ${CLUSTER_NAME} \
  --kubernetes-version ${KUBERNETES_VERSION} \
  --control-plane-machine-count=${CP_MACHINE_COUNT} \
  --worker-machine-count=${WORKER_MACHINE_COUNT} \
  --flavor ${FLAVOR} > ${CAPZ_YAML}

# Create the cluster
kubectl apply -f ${CAPZ_YAML}

# Get cluster kubeconfig file
# Here we need to wait for kubeconfig to be available
# Error: "${CLUSTER_NAME}-kubeconfig" not found in namespace "default": secrets "${CLUSTER_NAME}-kubeconfig" not found
until clusterctl get kubeconfig ${CLUSTER_NAME}; do
    echo Waiting for ${CLUSTER_NAME} Kubeconfig to be ready
    sleep 10
done
clusterctl get kubeconfig ${CLUSTER_NAME} > ${CLUSTER_KUBECONFIG}

until kubectl --kubeconfig=${CLUSTER_KUBECONFIG} get nodes; do
    echo Waiting for ${CLUSTER_NAME} master to be ready
    sleep 10
done

# Apply Calico
kubectl --kubeconfig=${CLUSTER_KUBECONFIG} apply -f ${CNI_URL}
kubectl --kubeconfig=${CLUSTER_KUBECONFIG} apply -f ${CNI_WINDOWS_URL}

# Apply storage provider
kubectl --kubeconfig=${CLUSTER_KUBECONFIG} apply -f ${AZURE_DISKS_URL}
kubectl --kubeconfig=${CLUSTER_KUBECONFIG} apply -f ${CSI_PROXY_URL}

CL2_POD_COUNT=10
REPORTS_DIR="./reports/${CLUSTER_NAME}"

mkdir -p ${REPORTS_DIR}
go run cmd/clusterloader.go \
    --testconfig=testing/windows-tests/config.yaml \
    --provider=skeleton \
    --kubeconfig=${CLUSTER_KUBECONFIG} \
    --report-dir=${REPORTS_DIR} \
    --v=2 \
    --delete-stale-namespaces \
    --enable-prometheus-server \
    --prometheus-scrape-node-exporter
