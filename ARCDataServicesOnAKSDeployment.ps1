# Azure Settings should be revisited for unique value properties.
$RG_Name="ARCDataServices"
$LAWS_Name="ARC-WS"
$KV_Name="ARCKV-Contoso"
$AKS_Name="ContosoAKS"
$SP_Name="ARC-DEMOSP"
$Subscription="{subscription ID}"
$Region="westeurope"
$CustomLocation="arc-ds-aks-cluster-location"
$ARCDS_Namespace="arcds-ns"

# Deployment Variables
$ENV:ACCEPT_EULA='yes'
$ENV:AZDATA_USERNAME="arcadmin"
$ENV:AZDATA_PASSWORD="Passw0rd1234"

# Install Extensions for the az CLI
az extension add --name connectedk8s
az extension add --name k8s-extension
az extension add --name customlocation
az extension add --name arcdata

az account set -s $Subscription

# Create Resource Group
az group create --name $RG_Name --location $Region

#Enable monitoring and create AKS Cluster accouding to docs nodes should be 4 cpus 16GB memory
az provider show -n Microsoft.OperationsManagement -o table
az provider show -n Microsoft.OperationalInsights -o table

az provider register --namespace Microsoft.OperationsManagement
az provider register --namespace Microsoft.OperationalInsights

az aks create --resource-group $RG_Name --name $AKS_Name --node-count 1 --enable-addons monitoring --generate-ssh-keys

#AZ command to create AKS cluster missing


# Retrieve credentials and verify connectivity 
az aks get-credentials -n $AKS_Name -g $RG_Name --overwrite-existing
kubectl get nodes
kubectl cluster-info

# Create Key Vault
az keyvault create --name $KV_Name --resource-group $RG_Name --location $Region

# Create Service Principal
$SP=(az ad sp create-for-rbac --name http://$SP_Name)
$SP

# Add Role
az role assignment create --assignee ($SP | ConvertFrom-Json).appId --role "Monitoring Metrics Publisher" --scope subscriptions/$Subscription

# Create Log Analytics Workspace and retrieve it's credentials
$LAWS=(az monitor log-analytics workspace create -g $RG_Name -n $LAWS_Name)
$LAWSKEYS=(az monitor log-analytics workspace get-shared-keys -g $RG_Name -n $LAWS_Name)

# Save credentials
az keyvault secret set --vault-name $KV_Name --name "SPN-CLIENT-ID" --value ($SP | ConvertFrom-Json).appId
az keyvault secret set --vault-name $KV_Name --name "SPN-TENANT-ID" --value ($SP | ConvertFrom-Json).tenant
az keyvault secret set --vault-name $KV_Name --name "SPN-CLIENT-SECRET" --value ($SP | ConvertFrom-Json).password
az keyvault secret set --vault-name $KV_Name --name "WORKSPACE-SHARED-KEY" --value ($LAWSKEYS | ConvertFrom-Json).primarySharedKey
az keyvault secret set --vault-name $KV_Name --name "WORKSPACE-ID" --value ($LAWS | ConvertFrom-Json).customerId

# Check credentials
az keyvault secret list --vault-name $KV_Name -o table

# Change context back to kubeadm Kubernetes Cluster
kubectl config view -o jsonpath='{range .contexts[*]}{.name}{''\n''}{end}'
kubectl config current-context
kubectl config use-context kubernetes-admin@kubernetes
kubectl config current-context

# Add the Arc extension and Azure Account to Azure Data Studio
azuredatastudio

# Connect the Kubernetes Cluster to Azure
az connectedk8s connect --name $AKS_Name --resource-group $RG_Name --location $Region
az connectedk8s list --resource-group $RG_Name --output table

kubectl get deployments,pods -n azure-arc

# Enable the Cluster for Custom Locations
az connectedk8s enable-features -n $AKS_Name -g $RG_Name --features cluster-connect custom-locations
az k8s-extension create --name $customLocation --extension-type microsoft.arcdataservices --cluster-type connectedClusters `
    -c $AKS_Name -g $RG_Name --scope cluster --release-namespace $ARCDS_Namespace --config Microsoft.CustomLocation.ServiceAccount=sa-bootstrapper `
         --auto-upgrade false

# Wait for the extension to be Installed!
az k8s-extension show --name $customLocation --cluster-type connectedClusters -c $AKS_Name -g $RG_Name  -o table
kubectl get pods -n arc

# Deploy Custom Location and DC from Portal (could also deploy through CLI, ARM or Bicep!)
# we need the Client secret though...
az keyvault secret show --vault-name $KV_Name --name "SPN-CLIENT-SECRET" --query value -o tsv | Set-Clipboard
Start-Process https://portal.azure.com/#create/Microsoft.DataController

# We also need the LAWS ID and Key
az keyvault secret show --vault-name $KV_Name --name "WORKSPACE-ID" --query value -o tsv | Set-Clipboard
az keyvault secret show --vault-name $KV_Name --name "WORKSPACE-SHARED-KEY" --query value -o tsv | Set-Clipboard

# Check out the result
kubectl get pods -n $ARCDS_Namespace

# Check Status
az arcdata dc status show --k8s-namespace $ARCDS_Namespace --use-k8s

# Let's check in Azure Data Studio
azuredatastudio
