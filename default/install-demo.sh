#!/usr/bin/env bash
# shfmt -i 2 -ci -w
set -euo pipefail

# create the output directory for our files
mkdir -p output

# Default SSH key path
KEY_PATH="$HOME/.ssh/id_rsa"

# Check if key exists
if [ -f "$KEY_PATH" ] && [ -f "$KEY_PATH.pub" ]; then
  echo "SSH key already exists at $KEY_PATH"
else
  echo "SSH key not found. Generating a new one..."
  mkdir -p "$HOME/.ssh"
  ssh-keygen -t rsa -b 4096 -f "$KEY_PATH" -N "" -C "your_email@example.com"
  echo "SSH key generated at $KEY_PATH"
fi

die() {
  echo "$*" >&2
  exit 1  
}

load_env() {
  # dynamic values loaded from Terraform
  export TF_OUTPUTS=$(terraform output -json | jq -r)
  export AKS_CLUSTER_NAME=$(echo "$TF_OUTPUTS" | jq -r .aks_cluster_name.value)
  export ACR_NAME=$(terraform output -json acr | jq -r .login_server)
  export AZ_MONITOR_WORKSPACE_ID=$(echo $TF_OUTPUTS | jq -r .azure_monitor_workspace_id.value.id)
  export GRAFANA_RESOURCE_ID=$(echo $TF_OUTPUTS | jq -r .grafana_resource_id.value)
  export RESOURCE_GROUP_NAME=$(echo $TF_OUTPUTS | jq -r .resource_group_name.value)
  export STORAGE_ACCOUNT=$(echo $TF_OUTPUTS | jq -r .storage_account_name.value)
  export CONTAINER_NAME=$(echo $TF_OUTPUTS | jq -r .container_name.value)
  export SERVICEBUS_NAME=$(echo $TF_OUTPUTS | jq -r .servicebus_name.value)
  export USER_ASSIGNED_CLIENT_ID=$(echo $TF_OUTPUTS| jq -r .aks_managed_id.value.client_id)
  export USER_ASSIGNED_CLIENT_NAME=$(echo $TF_OUTPUTS | jq -r .aks_managed_id.value.name)
  export SUBSCRIPTION_ID=$(echo $TF_OUTPUTS | jq -r .azure_subscription.value.subscription_id)
  export TENANT_ID=$(echo $TF_OUTPUTS | jq -r .azure_subscription.value.tenant_id)
  echo "***************************************************"
  echo "AZ_MONITOR_WORKSPACE_ID: " $AZ_MONITOR_WORKSPACE_ID
  echo "AKS_CLUSTER_NAME: " $AKS_CLUSTER_NAME
  echo "ACR_NAME: " $ACR_NAME
  echo "NAMESPACE: " "default"
  echo "RESOURCE_GROUP_NAME: " $RESOURCE_GROUP_NAME
  echo "STORAGE_ACCOUNT: " $STORAGE_ACCOUNT
  echo "CONTAINER_NAME: " $CONTAINER_NAME
  echo "SERVICEBUS_NAME: " $SERVICEBUS_NAME
  echo "USER_ASSIGNED_CLIENT_ID: " $USER_ASSIGNED_CLIENT_ID
  echo "USER_ASSIGNED_CLIENT_NAME:" $USER_ASSIGNED_CLIENT_NAME
  echo "SUBSCRIPTION_ID: " $SUBSCRIPTION_ID
  echo "TENANT_ID: " $TENANT_ID
  echo "***************************************************"
}

# We need the following providers for this demo
# - Microsoft.ContainerService/AKS-PrometheusAddon
# - Microsoft.ContainerService/EnableEncryptionAtHostPreview
# - Microsoft.Compute/EncryptionAtHost
demo_providers() {
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

# based on https://azureglobalblackbelts.com/2023/12/18/external-dns-workload-identity.html
create_external_dns(){
  cat <<EOF > output/values.yaml
fullnameOverride: external-dns
serviceAccount:
  annotations:
    azure.workload.identity/client-id: ${USER_ASSIGNED_CLIENT_ID}
podLabels:
  azure.workload.identity/use: "true"
provider: azure-private-dns
azure:
  resourceGroup: "${RESOURCE_GROUP_NAME}"
  tenantId: "${TENANT_ID}"
  subscriptionId: "${SUBSCRIPTION_ID}"
  useWorkloadIdentityExtension: true
logLevel: debug
EOF

  # Add the helm repo
  helm repo add bitnami https://charts.bitnami.com/bitnami

  # Update the helm repo in case you already have it
  helm repo update bitnami

  # Install external dns
  helm install external-dns bitnami/external-dns -f output/values.yaml
}

create_workload_id_sa() {
  cat <<EOF > output/workload-identity-sa
apiVersion: v1
kind: ServiceAccount
metadata:
  annotations:
    azure.workload.identity/client-id: "${USER_ASSIGNED_CLIENT_ID}"
  name: "workload-identity-sa"
  namespace: "default"
EOF
}

create_stormbreaker_files() {
  echo "Generating Stormbreaker files"
  sed "
    s/RESOURCE_GROUP_NAME/$RESOURCE_GROUP_NAME/g;
    s/STORAGE_ACCOUNT/$STORAGE_ACCOUNT/g;
    s/CONTAINER_NAME/$CONTAINER_NAME/g" manifests/pv-blob-nfs.tpl > output/pv-blob-nfs.yaml

  KUBECONFIG=config kubectl create secret generic django-secret --from-literal=SECRET_KEY='django-insecure-fn+k2wszwdgp3n3+oo35_wudr)dxaz(!4u*f%b_b8-j)&-xo41'

  cp manifests/hpc/{cm-nfs.yaml,nfs-server.yaml,nfs-server-service.yaml,serviceaccount.yaml,pv-blob-nfs.yaml,pvc-blob-nfs.yaml,scratchpad.yaml,queue.yaml} output/
  cp manifests/ui/{cm-env-config.yaml,stormbreaker-api.yaml,stormbreaker-frontend.yaml} output/
}

create_keda_template() {  
  echo "Creating KEDA files"  
  sed "s/SERVICEBUS_NAME/$SERVICEBUS_NAME/g; 
    s/USER_ASSIGNED_CLIENT_ID/$USER_ASSIGNED_CLIENT_ID/g; 
    s/ACR_NAME/$ACR_NAME/g; s/STORAGE_ACCOUNT/$STORAGE_ACCOUNT/g; 
    s/AZURE_CLIENT_ID_VALUE/$USER_ASSIGNED_CLIENT_ID/g;" manifests/keda.tpl > output/keda.yaml

  local AKS_OIDC_ISSUER FEDERATED_IDENTITY_CREDENTIAL_NAME SERVICE_ACCOUNT_NAME SERVICE_ACCOUNT_NAMESPACE
  FEDERATED_IDENTITY_CREDENTIAL_NAME="stormbreaker-keda-federated-identity"
  AKS_OIDC_ISSUER="$(az aks show --name "${AKS_CLUSTER_NAME}" --resource-group "${RESOURCE_GROUP_NAME}" --query "oidcIssuerProfile.issuerUrl" --output tsv)"
  SERVICE_ACCOUNT_NAMESPACE="kube-system"
  SERVICE_ACCOUNT_NAME="keda-operator"

  # keda-operator
  az identity federated-credential create \
    --name ${FEDERATED_IDENTITY_CREDENTIAL_NAME} \
    --identity-name "${USER_ASSIGNED_CLIENT_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --issuer "${AKS_OIDC_ISSUER}" \
    --subject system:serviceaccount:"${SERVICE_ACCOUNT_NAMESPACE}":"${SERVICE_ACCOUNT_NAME}" \
    --audience api://AzureADTokenExchange
  
  # sa-keda-sb-kubectl
  FEDERATED_IDENTITY_CREDENTIAL_NAME="stormbreaker-keda-kubectl-federated-identity"
  SERVICE_ACCOUNT_NAMESPACE="default"
  SERVICE_ACCOUNT_NAME="sa-keda-sb-kubectl"
  az identity federated-credential create \
    --name ${FEDERATED_IDENTITY_CREDENTIAL_NAME} \
    --identity-name "${USER_ASSIGNED_CLIENT_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --issuer "${AKS_OIDC_ISSUER}" \
    --subject system:serviceaccount:"${SERVICE_ACCOUNT_NAMESPACE}":"${SERVICE_ACCOUNT_NAME}" \
    --audience api://AzureADTokenExchange
}

do_generate_kubeconfig() {
  terraform output -raw kubeconfig >config
}

enable_prometheus_integration() {
  # enable Managed Prometheus and Managed Grafana integration
  az aks update \
    --enable-azure-monitor-metrics \
    --name ${AKS_CLUSTER_NAME} \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --azure-monitor-workspace-resource-id ${AZ_MONITOR_WORKSPACE_ID} \
    --grafana-resource-id ${GRAFANA_RESOURCE_ID}
}

# enable cost analysis
# this should be migrated to Terraform once supported.
do_enable_cost_analysis() {
  az aks update \
    --resource-group ${RESOURCE_GROUP_NAME} \
    --name ${AKS_CLUSTER_NAME} \
    --enable-cost-analysis
}

do_deploy_volcano() {
  kubectl apply -f https://raw.githubusercontent.com/volcano-sh/volcano/master/installer/volcano-development.yaml
}

do_install_nvidia_operator() {
  kubectl get namespace network-operator 2>/dev/null || kubectl create namespace network-operator

  helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
  helm repo update
  # Install node feature discovery
  helm upgrade -i --wait \
    --create-namespace network-operator node-feature-discovery node-feature-discovery \
    --repo https://kubernetes-sigs.github.io/node-feature-discovery/charts \
    --set-json master.nodeSelector='{"kubernetes.azure.com/mode": "system"}' \
    --set-json worker.nodeSelector='{"kubernetes.azure.com/agentpool": "adcirchpc"}' \
    --set-json worker.config.sources.pci.deviceClassWhitelist='["02","03","0200","0207"]' \
    --set-json worker.config.sources.pci.deviceLabelFields='["vendor"]'

  # Install the network-operator
  helm upgrade -i --wait \
    network-operator nvidia/network-operator \
    --repo https://helm.ngc.nvidia.com/nvidia \
    --set deployCR=true \
    --set nfd.enabled=false \
    --set ofedDriver.deploy=true \
    --set secondaryNetwork.deploy=false \
    --set rdmaSharedDevicePlugin.deploy=true \
    --set sriovDevicePlugin.deploy=true \
    --set-json sriovDevicePlugin.resources='[{"name":"mlnxnics","linkTypes": ["infiniband"], "vendors":["15b3"]}]' 
}

do_build_images() {
  local _CWD _BASE _LOGIN_SERVER _REGISTRY_NAME
	_CWD="$PWD"
	_BASE="${_CWD}/dockerbuild"
	_LOGIN_SERVER="${ACR_NAME}"
	_REGISTRY_NAME="${ACR_NAME%%.azurecr.io}"

	az acr login --name "${_REGISTRY_NAME}" || die "Error: failed to login to ACR: ${_REGISTRY_NAME}"
	
  # frontend
	echo "Building react-ui/frontend"
	cd "${_BASE}/react-ui/frontend" || die "Error: cannot cd to frontend"
	az acr build --image "${_LOGIN_SERVER}/misc/react-ui:1.0" --registry "${_REGISTRY_NAME}" .

  # backend
	echo "Building react-ui/crud-app/backend"
	cd "${_BASE}/react-ui/crud-app/backend" || die "Error: cannot cd to backend"
	az acr build --image "${_LOGIN_SERVER}/misc/backend:1.0" --registry "${_REGISTRY_NAME}" .

  # servicebus-dispatcher
	echo "Building servicebus-dispatcher"
	cd "${_BASE}/dispatcher" || die "Error: cannot cd to dispatcher"
	az acr build --image "${_LOGIN_SERVER}/misc/servicebus-dispatcher:1.0" --registry "${_REGISTRY_NAME}" .

  # servicebus-remover
	echo "Building servicebus-remover"
	cd "${_BASE}/remover" || die "Error: cannot cd to remover"
  az acr build --image "${_LOGIN_SERVER}/misc/servicebus-remover:1.0" --registry "${_REGISTRY_NAME}" .

  # servicebus-completed
  echo "Building servicebus-completed"
	cd "${_BASE}/completed" || die "Error: cannot cd to completed" 
	az acr build --image "${_LOGIN_SERVER}/misc/servicebus-completed:1.0" --registry "${_REGISTRY_NAME}" .

  # hpccm base image
  echo "Building hpccm base image"
  cd "${_BASE}/adcirc/hpccm" || die "Error: cannot cd to adcirc/hpccm"
	az acr build --image "${_LOGIN_SERVER}/hpccm:1.0" --registry "${_REGISTRY_NAME}" -f Dockerfile.base .

	cd "${_CWD}" || die "Warning: failed to return to original directory"
	
  # list of the built images
  az acr repository list --name ${_REGISTRY_NAME} --output table
}

do_deploy_stormbreaker() {
  kubectl apply -f output/

  # copy the simulations directory over to Blob
  # this will prompt the user to login to Azure

  echo "Copying the simulations directory to the output container in Blob Storage"
  echo "You will be prompted to login for this. We will need to temporarily enable public access"
  
  az storage account update \
  --name ${STORAGE_ACCOUNT} \
  --resource-group ${RESOURCE_GROUP_NAME} \
  --public-network-access Enabled

  az storage fs directory upload \
    --account-name ${STORAGE_ACCOUNT} \
    --auth-mode login \
    --file-system input \
    --source ./simulations \
    --recursive
  
  # ADCIRC template
  az storage fs directory upload \
    --account-name ${STORAGE_ACCOUNT} \
    --auth-mode login \
    --file-system input \
    --source ./templates \
    --recursive

  az storage account update \
  --name ${STORAGE_ACCOUNT} \
  --resource-group ${RESOURCE_GROUP_NAME} \
  --public-network-access Disabled
}

# we start here
do_demo_bootstrap() {
  load_env
  create_stormbreaker_files
  create_keda_template
  create_external_dns
  # enable_prometheus_integration
  do_generate_kubeconfig
  do_enable_cost_analysis
  do_deploy_volcano
  do_build_images
  do_deploy_stormbreaker
}
