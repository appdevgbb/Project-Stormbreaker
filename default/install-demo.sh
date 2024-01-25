# This script installs the Refinitiv Tick Capture (RTC) application on an Azure Kubernetes Service (AKS) cluster.
# It sets environment variables, loads dynamic values from Terraform, and creates a workload identity service account and federated credential.
# The script also checks for and registers the necessary Azure providers for the demo.

#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -euo pipefail

# create the output directory for our files
mkdir -p output

load_env() {
  # dynamic values loaded from Terraform
  export TF_OUTPUTS=$(terraform output -json | jq -r)
  export AKS_CLUSTER_NAME=$(echo "$TF_OUTPUTS" | jq -r .aks_cluster_name.value)
  export AZ_MONITOR_WORKSPACE_ID=$(echo $TF_OUTPUTS | jq -r .azure_monitor_workspace_id.value)
  export GRAFANA_RESOURCE_ID=$(echo $TF_OUTPUTS | jq -r .grafana_resource_id.value)
  export RESOURCE_GROUP_NAME=$(echo $TF_OUTPUTS | jq -r .resource_group_name.value)
  export STORAGE_ACCOUNT=$(echo $TF_OUTPUTS | jq -r .storage_account_name.value)
  export CONTAINER_NAME=$(echo $TF_OUTPUTS | jq -r .container_name.value)
  echo "***************************************************"
  echo "AZ_MONITOR_WORKSPACE_ID: " $AZ_MONITOR_WORKSPACE_ID
  echo "AKS_CLUSTER_NAME: " $AKS_CLUSTER_NAME
  echo "NAMESPACE: " "default"
  echo "RESOURCE_GROUP_NAME: " $RESOURCE_GROUP_NAME
  echo "STORAGE_ACCOUNT: " $STORAGE_ACCOUNT
  echo "CONTAINER_NAME: " $CONTAINER_NAME
  echo "***************************************************"
}

# We need the following providers for this demo
# - Microsoft.ContainerService/AKS-PrometheusAddonPreview
# - Microsoft.ContainerService/EnableWorkloadIdentityPreview
# - Microsoft.ContainerService/EnableEncryptionAtHostPreview
# - Microsoft.Compute/EncryptionAtHost
demo_providers() {
  az extension update --name aks-preview

  local _AZURE_NAMESPACE=$(echo $1 | awk -F '/' '{print $1}')
  local _FLAGS=$(echo $1 | awk -F '/' '{print $2}')

  echo "Checking if " $1 " is registered"
  for feature in $(echo ${_FLAGS}); do
    is_featured_registered="Unregistered"
    is_featured_registered=$(az feature register --namespace ${_AZURE_NAMESPACE} --name ${feature} -o json | jq -r .properties.state)

    while ! true; do
      if [[ "${is_featured_registered}" != "Registered" ]]; then
        echo "Featured state:" $is_featured_registered
        is_featured_registered=$(az feature show --namespace ${_AZURE_NAMESPACE} --name ${feature} -o json | jq -r '.properties.state')
        sleep 3
      fi
    done
  done
  # When the status reflects Registered, refresh the registration of the namespace resource provider by using
  # the az provider register command:
  az provider register --namespace ${_AZURE_NAMESPACE}
}

create_nfs_workload() {
  echo "Creating a sample file"
  sed "
    s/RESOURCE_GROUP_NAME/$RESOURCE_GROUP_NAME/g;
    s/STORAGE_ACCOUNT/$STORAGE_ACCOUNT/g;
    s/CONTAINER_NAME/$CONTAINER_NAME/g" manifests/pv-blob-nfs.tpl >output/pv-blob-nfs.yaml

    cp manifests/{nginx-pod-blob.yaml,pvc-blob-nfs.yaml} output/
}

do_generate_kubeconfig(){
  terraform output -raw kubeconfig > config
}
# a test workload
do_deploy_nfs_workload(){
  KUBECONFIG=config kubectl apply -f output/
}

enable_prometheus_integration() {
  # enable Managed Prometheus and Managed Grafana integration
  az aks update \
    --enable-azure-monitor-metrics \
    --name ${AKS_CLUSTER_NAME} \
    --resource-group ${RGNAME} \
    --azure-monitor-workspace-resource-id ${AZ_MONITOR_WORKSPACE_ID} \
    --grafana-resource-id ${GRAFANA_RESOURCE_ID}
}

# we start here
do_demo_bootstrap() {
  load_env
  create_nfs_workload
  # enable_prometheus_integration
  do_generate_kubeconfig
  do_deploy_nfs_workload
}
