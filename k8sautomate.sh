#!/bin/bash
echo "Welcome to AKS automate setup!"

echo "Checking if Azure CLI is installed..."
if [ "$(which az)" = "" ]
then
    echo Azure CLI not found, installing now...
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
else
    echo Azure CLI found, continuing...
fi

echo "Checking if Azure subscription is connected..."
if [ $(az account show -o tsv --query id 2>&1 |wc -c) -ne 37 ]
then
    echo -e \\n please follow the instructions below to connect to your Azure subscription...
    az login -o tsv
fi

# Setting up network addresses
VNET_ADDRESS_SPACE="11.0.0.0/16"
AKS_SUBNET_CIDR="11.0.1.0/24"
APPGW_SUBNET_CIDR="11.0.2.0/24"
DB_SUBNET_CIDR="11.0.3.0/24"

echo "Getting tenant Id..."
AZ_TenantID=$(az account show --query tenantId -o tsv)

echo "Fetching Azure resources list..."
azResources=$(az resource list -o tsv --query [].[name,resourceGroup] |sed s/-/_/g)

function checkNameAvailability {
        echo $azResources |grep -wq $1
        case $? in
                0)
                        echo "Conflict: Resource $1 already exists, please enter a different name."
                        return 1
                        ;;
                1)
                        return 0
                        ;;
        esac
}

function getValue {
        until ( test -v $2 )
        do
                read -p "$1" $2
                varValue=$(set |grep ^$2= |awk -F= '{print $2}')
                if [ "$varValue" == "" ]
                then
                        echo "Input for $2 required. Please enter a valid input."
                        unset $2
                else
                        checkNameAvailability $varValue || unset $2
                fi

        done
}

function getValidValue2 {
        until ( test -v $2 )
        do
                read -p "$1" $2
                varValue=$(set |grep ^$2= |awk -F= '{print $2}')
                echo $3 $4 $5 $6 |grep -qw $varValue
                case $? in
                        0)
                                return
                                ;;
                        1)
                                echo "Valid inputs are $(echo $3 $4 $5 $6 | sed 's/\ /\//g')"; unset $2
                                ;;
                esac
        done
}

function getValidValue {
    prompt=$1
    varName=$2
    shift 2
    validValues=$*
        until ( test -v $varName )
        do
                read -p "$prompt" $varName
                varValue=$(set |grep ^$varName= |awk -F= '{print $2}')
                echo $validValues |grep -qw "$varValue"
                case $? in
                        0)
                                return
                                ;;
                        1)
                                echo "Valid inputs are $(echo $validValues | sed 's/\ /\//g')"; unset $varName
                                ;;
                esac
        done
}

function getSelection {
    export PS3=$1
    prompt=$1
    varName=$2
    shift 2
    validValues=$*
        until ( test -v $varName )
        do
            select name in $validValues
            do
                echo $validValues |grep -qw "$name"
                case $? in
                        0)
                                export $varName=$name
                                return
                                ;;
                        1)
                                unset $varName
                                ;;
                esac
            done
        done
}

getValue "Please enter name for the AKS Cluster: " AAKS_AKS_NAME
getValue "Please enter name for the resource group: " AAKS_RG_NAME
getValue "Please enter Azure region: " AAKS_REGION
if [ "$AAKS_REGION" == "centralindia" ]
then
        getValue "Do you want to enable Availability Zones for this cluster? (y/n): " AAKS_AZ_ENABLE
fi
getValue "Please enter the admin username for the cluster (default azureuser): " AAKS_ADMIN_USERNAME
getValidValue "Please enter size of the node pool (small/medium/large) " AAKS_NODEPOOL_SIZE small medium large
getValidValue "Do you also need a Windows node pool? (y/n) " AAKS_WIN_NODEPOOL y n Y N
if [ "$AAKS_WIN_NODEPOOL" == "y" ]
then
        getValue "Please enter the Windows node administrator username: " AAKS_WIN_USERNAME
fi
getValidValue "Please select the K8s network policy you want to use (azure/calico/none): " AAKS_NETWORK_POLICY azure calico none
getValidValue "Select an Ingress Controller (nginx/appgw/none): " AAKS_INGRESS nginx appgw none
getValidValue "Do you want to create a new Azure Container Registry? (y/n) " AAKS_ACR_CREATE y n Y N
if [ "$AAKS_ACR_CREATE" == "n" ] || [ "$AAKS_ACR_CREATE" == "N" ]
then
        getValidValue "Do you want to use an existing Azure Container Registry? (y/n) " AAKS_ACR_EXISTING y n Y N
        if [ "$AAKS_ACR_EXISTING" == "y" ] || [ "$AAKS_ACR_EXISTING" == "Y" ]
        then
                getValue "Please enter the name of the existing Azure Container Registry: " AAKS_ACR_NAME
        fi
fi

getValidValue "Do want to set up Azure Key Vault for secrets storage? (y/n) " AAKS_KEYVAULT y n Y N
if [ "$AAKS_KEYVAULT" == "y" ] || [ "$AAKS_KEYVAULT" == "Y" ]
then
        until [ "$AAKS_KEYVAULT_NAME" != "" ]
        do 
                getValue "Please enter the name of the Azure Key Vault: " AAKS_KEYVAULT_NAME
                curl -fs https://$AAKS_KEYVAULT_NAME.vault.azure.net
                if [ "$?" -ne 6 ]
                then
                        echo "Conflict: Resource $AAKS_KEYVAULT_NAME already exists, please enter a different name."
                        unset AAKS_KEYVAULT_NAME
                fi
        done
fi

getValidValue "Do you want to create and use a Persistent Volume claim for the AKS cluster? (y/n) " AAKS_PVC y n Y N
if [ "$AAKS_PVC" == "y" ] || [ "$AAKS_PVC" == "Y" ]
then
        if [ "$AAKS_AZ_ENABLE" == "y" ]
        then
                getSelection "Please enter a number to select a SKU for the Azure File Storage: " AAKS_PVC_SKU Standard_ZRS Premium_ZRS 
        else
                getSelection "Please enter a number to select a SKU for the Azure File Storage: " AAKS_PVC_SKU Standard_LRS Standard_GRS Standard_ZRS Standard_RAGRS Premium_LRS Premium_ZRS 
        fi

        if [ "$AAKS_PVC_SKU" == "Premium_ZRS" ] || [ "$AAKS_PVC_SKU" == "Premium_LRS" ]
        then
                getValue "Please enter the size of the Azure File Storage (in GB; minimum 100): " AAKS_PVC_SIZE
        else
                getValue "Please enter the size of the Azure File Storage (in GB): " AAKS_PVC_SIZE

        fi
fi

getValidValue "Do you want to set up a demo app? (y/n) " AAKS_DEMOAPP y n Y N

getSelection "Please select your database: " AAKS_DB_TYPE sql mysql postgresql none
case $AAKS_DB_TYPE in
        sql)
                getValue "Please enter the name of the database: " AAKS_DB_NAME
                getValue "Please enter the name of the database user: " AAKS_DB_USER
                getValue "Please enter the password for the database user: " AAKS_DB_PASSWORD
                getSelection "Please select your database size SKU? " AAKS_DB_SKU
                ;;
        mysql)
                DB_SKUS=$(az mysql server list-skus -l $AAKS_REGION --query [].serviceLevelObjectives[].id -o tsv)
                if [ "$DB_SKUS" != "" ]
                then
                        getValidValue "Please select between single/flexible server mode? " AAKS_DB_MODE single flexible
                        DB_VERSIONS=$(az mysql flexible-server list-skus -l $AAKS_REGION --query "[].supportedFlexibleServerEditions[].supportedServerVersions[*].name | [0]" -o tsv)
                        getSelection "Please select your database version: " AAKS_DB_VERSION $DB_VERSIONS
                        getValue "Please enter the name of the database: " AAKS_DB_NAME
                        getValue "Please enter the name of the database user: " AAKS_DB_USER
                        read -s -p "Please enter the password for the database user: " AAKS_DB_PASSWORD; echo "";
                        if [ "$AAKS_DB_MODE" == "flexible" ]
                        then
                                DB_TIERS=$(az mysql flexible-server list-skus -l $AAKS_REGION --query "[].supportedFlexibleServerEditions[*].name | [0]" -o tsv)
                                getSelection "Please select database tier: " AAKS_DB_TIER $DB_TIERS
                                DB_SKUS=$(az mysql flexible-server list-skus -l $AAKS_REGION --query "[].supportedFlexibleServerEditions[?name=='$AAKS_DB_TIER'][].supportedServerVersions[].supportedSkus[*].name | [0]" -o tsv)
                                getSelection "Please select your database size SKU? " AAKS_DB_SKU $DB_SKUS
                        else
                                DB_TIERS=$(az mysql server list-skus -l $AAKS_REGION --query "[].id" -o tsv)
                                getSelection "Please select database tier: " AAKS_DB_TIER $DB_TIERS                        
                                DB_SKUS=$(az mysql server list-skus -l $AAKS_REGION --query "[].serviceLevelObjectives[?edition=='$AAKS_DB_TIER'][].id" -o tsv)
                                getSelection "Please select your database size SKU? " AAKS_DB_SKU $DB_SKUS
                        fi
                else
                        AAKS_DB_TYPE=none
                        echo '*********************************************************************'
                        echo "No MySQL SKUs available for your subscription in region $AAKS_REGION."
                        echo '*********************************************************************'
                fi
                ;;
        postgresql)
                DB_SKUS=$(az postgres server list-skus -l $AAKS_REGION --query [].serviceLevelObjectives[].id -o tsv)
                if [ "$DB_SKUS" != "" ]
                then
                        getValidValue "Please select between single/flexible server mode? " AAKS_DB_MODE single flexible
                        getValue "Please enter the name of the database: " AAKS_DB_NAME
                        getValue "Please enter the name of the database user: " AAKS_DB_USER
                        read -s -p "Please enter the password for the database user: " AAKS_DB_PASSWORD; echo "";
                        if [ "$AAKS_DB_MODE" == "flexible" ]
                        then
                                DB_VERSIONS=$(az postgres flexible-server list-skus -l $AAKS_REGION --query "[].supportedFlexibleServerEditions[].supportedServerVersions[*].name | [0]" -o tsv |awk -F. '{print $1}' |sort |uniq)
                                getSelection "Please select your database version: " AAKS_DB_VERSION $DB_VERSIONS
                                DB_TIERS="Burstable GeneralPurpose MemoryOptimized"
                                getSelection "Please select database tier: " AAKS_DB_TIER $DB_TIERS
                                DB_SKUS=$(az postgres flexible-server list-skus -l $AAKS_REGION --query "[].supportedFlexibleServerEditions[?name=='$AAKS_DB_TIER'].supportedServerVersions[][?name=='$AAKS_DB_VERSION'].supportedVcores[*].name | [0]" -o tsv)
                                getSelection "Please select your database size SKU? " AAKS_DB_SKU $DB_SKUS
                        else
                                DB_VERSIONS="10 11"
                                getSelection "Please select your database version: " AAKS_DB_VERSION $DB_VERSIONS
                                # DB_TIERS=$(az postgres server list-skus -l $AAKS_REGION --query "[].id" -o tsv)
                                DB_TIERS="Basic GeneralPurpose MemoryOptimized"
                                getSelection "Please select database tier: " AAKS_DB_TIER $DB_TIERS        
                                DB_SKUS=$(az postgres server list-skus -l $AAKS_REGION --query "[].serviceLevelObjectives[?edition=='$AAKS_DB_TIER'][].id" -o tsv)
                                getSelection "Please select your database size SKU? " AAKS_DB_SKU $DB_SKUS
                        fi
                else
                        AAKS_DB_TYPE=none
                        echo '*********************************************************************'
                        echo "No PostgreSQL SKUs available for your subscription in region $AAKS_REGION."
                        echo '*********************************************************************'
                fi
                ;;
        none)
                ;;
esac

# set |grep ^AAKS
# exit

echo "Creating resource group..."
az group create --name $AAKS_RG_NAME --location $AAKS_REGION -o none

for i in $(set |grep ^AAKS)
do
        case $i in
                AAKS_ACR_EXISTING=y)
                        echo "Existing Azure Container Registry will be connected to AKS cluster"
                        AAKS_ACR_EXISTING="--attach-acr $AAKS_ACR_NAME"
                        ;;
                AAKS_ACR_EXISTING=n)
                        echo "Azure Container Registry will not be connnected to AKS cluster"
                        AAKS_ACR_EXISTING=""
                        ;;
                AAKS_ACR_CREATE=y)
                        echo "Azure Container Registry will be created and connected to AKS cluster"
                        ;;
                AAKS_ACR_CREATE=n)
                        echo "Azure Container Registry integration will not be set up"
                        ;;
                AAKS_AZ_ENABLE=y)
                        echo "AZ will be enabled"
                        AAKS_AZ_ENABLE="--zones 1 2 3"
                        ;;
                AAKS_AZ_ENABLE=n)
                        echo "AZ will not be enabled"
                        AAKS_AZ_ENABLE=""
                        ;;
                AAKS_WIN_NODEPOOL=y)
                        echo "Windows node pool will be created"
                        AAKS_WIN_NODEPOOL="--windows-admin-username $AAKS_WIN_USERNAME"
                        ;;
                AAKS_WIN_NODEPOOL=n)
                        echo "Windows node pool will not be created"
                        AAKS_WIN_NODEPOOL=""
                        ;;
                AAKS_KEYVAULT=y)
                        echo "Azure KeyVault will be created"
                        AAKS_KEYVAULT="--enable-addons azure-keyvault-secrets-provider --enable-managed-identity"
                        ;;
                AAKS_KEYVAULT=n)
                        echo "Azure KeyVault will not be created"
                        AAKS_KEYVAULT=""
                        ;;
                AAKS_INGRESS=appgw)
                        echo "App Gateway will be enabled as Ingress Controller"
                        ;;
                AAKS_NODEPOOL_SIZE=small)
                        echo "Small node pool will be created"
                        AAKS_NODEPOOL_SIZE="--node-count 3 --node-vm-size Standard_D2_v4"
                        ;;
                AAKS_NODEPOOL_SIZE=medium)
                        echo "Medium node pool will be created"
                        AAKS_NODEPOOL_SIZE="--node-count 3 --node-vm-size Standard_D4_v4"
                        ;;
                AAKS_NODEPOOL_SIZE=large)
                        echo "Large node pool will be created"
                        AAKS_NODEPOOL_SIZE="--node-count 3 --node-vm-size Standard_D8_v4"
                        ;;
                AAKS_NETWORK_POLICY=none)
                        echo "No network policy will be enabled"
                        AAKS_NETWORK_POLICY=""
                        ;;
                AAKS_NETWORK_POLICY=azure)
                        echo "Azure network policy will be enabled"
                        AAKS_NETWORK_POLICY='--network-policy azure'
                        ;;
                AAKS_NETWORK_POLICY=calico)
                        echo "Calico network policy will be enabled"
                        AAKS_NETWORK_POLICY='--network-policy calico'
                        ;;
        esac
done

if [ "$AAKS_ACR_CREATE" == "y" ]
then
        echo "Creating Azure Container Registry..."
        AAKS_ACR_NAME=$(echo $AAKS_AKS_NAME)ACR
        az acr create --resource-group $AAKS_RG_NAME --name $AAKS_ACR_NAME --sku Basic --admin-enabled true -o none
        AAKS_ACR_EXISTING="--attach-acr $AAKS_ACR_NAME"
fi

#Create cluster
echo "Creating virtual network and subnets..."
AAKS_VNET_NAME=$(echo $AAKS_AKS_NAME)vnet
AAKS_SUBNET_NAME=$(echo $AAKS_AKS_NAME)subnet
az network vnet create -n $AAKS_VNET_NAME -g $AAKS_RG_NAME --address-prefix $VNET_ADDRESS_SPACE --subnet-name $AAKS_SUBNET_NAME --subnet-prefix $AKS_SUBNET_CIDR -o none
AAKS_SUBNET_ID=$(az network vnet subnet show -n $AAKS_SUBNET_NAME -g $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME --query id -o tsv)

az network vnet subnet create --name appgwsubnet --resource-group $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME --address-prefixes $APPGW_SUBNET_CIDR -o none
APPGW_SUBNET_ID=$(az network vnet subnet show -n appgwsubnet -g $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME --query id -o tsv)

echo "Creating AKS cluster..."
az aks create -n $AAKS_AKS_NAME -g $AAKS_RG_NAME --network-plugin azure \
-u $AAKS_ADMIN_USERNAME -x --uptime-sla $AAKS_AZ_ENABLE $AAKS_NODEPOOL_SIZE $AAKS_WIN_NODEPOOL \
$AAKS_KEYVAULT $AAKS_ACR_EXISTING --vnet-subnet-id $AAKS_SUBNET_ID --yes -o none 

AKS_CREATION_STATE=$?
if [ $AKS_CREATION_STATE -eq 0 ]
then
        echo ""; echo "AKS Cluster creation completed successfully. Proceeding ahead..."
else
        echo ""; echo "AKS Cluster creation failed. Please see error(s) above and rectify."
        exit
fi

#Add Windows Node Pool
if [ $AKS_CREATION_STATE -eq 0 ] && [ "$AAKS_WIN_NODEPOOL" != "" ]
then
        echo "Adding Windows node pool..."
        az aks nodepool add --resource-group $AAKS_RG_NAME --cluster-name $AAKS_AKS_NAME --os-type Windows --name winvms $AAKS_NODEPOOL_SIZE -o none
fi

if [ $AKS_CREATION_STATE -eq 0 ] && [ "$AAKS_INGRESS" == "appgw" ]
then
        echo "Creating public IP for App Gateway..."
        AppGw_IP_Name=$(echo $AAKS_AKS_NAME)appgwip
        az network public-ip create -n $AppGw_IP_Name -g $AAKS_RG_NAME --allocation-method Static --sku Standard -o none
        AAKS_APPGW_NAME=$(echo $AAKS_AKS_NAME)appgw
        echo "Creating App Gateway..."
        az network application-gateway create -n $AAKS_APPGW_NAME -l $AAKS_REGION -g $AAKS_RG_NAME --sku Standard_v2 --public-ip-address $AppGw_IP_Name --vnet-name $AAKS_VNET_NAME --subnet appgwsubnet -o none
        appgwId=$(az network application-gateway show -n $AAKS_APPGW_NAME -g $AAKS_RG_NAME -o tsv --query id -o tsv) 
        az aks enable-addons -n $AAKS_AKS_NAME -g $AAKS_RG_NAME -a ingress-appgw --appgw-id $appgwId -o none
fi

#Add Azure KeyVault
if [ $AKS_CREATION_STATE -eq 0 ] && [ "$AAKS_KEYVAULT" != "" ]
then
        echo "Creating Azure KeyVault..."
        az keyvault create -n $AAKS_KEYVAULT_NAME -g $AAKS_RG_NAME -l $AAKS_REGION -o none
        echo "Creating Azure KeyVault example secret..."
        az keyvault secret set --vault-name $AAKS_KEYVAULT_NAME -n ExampleSecret --value MyAKSExampleSecret -o none
        echo "Getting AKS managed identity..."
        AAKS_ID=$(az aks show -g $AAKS_RG_NAME -n $AAKS_AKS_NAME --query addonProfiles.azureKeyvaultSecretsProvider.identity.clientId -o tsv)
        echo "Assigning Azure KeyVault permissions to AKS managed identity..."
        az keyvault set-policy -n $AAKS_KEYVAULT_NAME --key-permissions get --spn $AAKS_ID -o none
        az keyvault set-policy -n $AAKS_KEYVAULT_NAME --secret-permissions get --spn $AAKS_ID -o none
        az keyvault set-policy -n $AAKS_KEYVAULT_NAME --certificate-permissions get --spn $AAKS_ID -o none
fi

# Creating database
case $AAKS_DB_TYPE in
        sql)
                ;;
        mysql)
                echo "Creating subnet for MySQL database..."
                az network vnet subnet create \
                --name mySqlSubnet  --resource-group $AAKS_RG_NAME \
                --vnet-name $AAKS_VNET_NAME --disable-private-endpoint-network-policies true \
                --address-prefixes $DB_SUBNET_CIDR -o none
                DB_SUBNET_ID=$(az network vnet subnet show -n mySqlSubnet -g $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME --query id -o tsv)
                echo "Creating MySQL database..."
                if [ "$AAKS_DB_MODE" == "flexible" ]
                then
                        DB_ZONE_PARAMS=""
                        if [ "$AAKS_AZ_ENABLE" == "y" ] && [ "$AAKS_DB_SKU" != "Standard_B"* ]
                        then
                                DB_ZONE_PARAMS="--high-availability ZoneRedundant --zone 1 --standby-zone 2"
                        fi
                        az mysql flexible-server create -l $AAKS_REGION -g $AAKS_RG_NAME -n $AAKS_DB_NAME -u $AAKS_DB_USER \
                        -p $AAKS_DB_PASSWORD --tier $AAKS_DB_TIER --sku-name $AAKS_DB_SKU --version $AAKS_DB_VERSION \
                        $DB_ZONE_PARAMS --subnet $DB_SUBNET_ID \
                        --private-dns-zone $AAKS_DB_NAME.private.mysql.database.azure.com -o none
                else
                        AAKS_DB_VERSION=$(echo $AAKS_DB_VERSION | cut -c 1-3)
                        az mysql server create -l $AAKS_REGION -g $AAKS_RG_NAME -n $AAKS_DB_NAME -u $AAKS_DB_USER \
                        -p $AAKS_DB_PASSWORD --sku-name $AAKS_DB_SKU --ssl-enforcement Enabled \
                        --public-network-access Disabled --version $AAKS_DB_VERSION -o none
                        echo "Creating Private Endpoint..."
                        az network private-endpoint create --name mySqlPrivateEndpoint --resource-group $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME \
                        --subnet mySqlSubnet --private-connection-resource-id $(az resource show -g $AAKS_RG_NAME -n $AAKS_DB_NAME --resource-type "Microsoft.DBforMySQL/servers" --query "id" -o tsv) \
                        --group-id mySqlServer --connection-name mySqlConnection -o none
                        echo "Creating Private DNS Zone and association link..."
                        az network private-dns zone create --resource-group $AAKS_RG_NAME --name "privatelink.mysql.database.azure.com" -o none
                        az network private-dns link vnet create --resource-group $AAKS_RG_NAME \
                        --zone-name "privatelink.mysql.database.azure.com" \
                        --name MyDNSLink --virtual-network $AAKS_VNET_NAME --registration-enabled false -o none
                        networkInterfaceId=$(az network private-endpoint show --name mySqlPrivateEndpoint --resource-group $AAKS_RG_NAME --query 'networkInterfaces[0].id' -o tsv)
                        privateIP=$(az resource show --ids $networkInterfaceId --api-version 2019-04-01 --query properties.ipConfigurations[0].properties.privateIPAddress -o tsv)
                        az network private-dns record-set a create --name mySqlServer --zone-name privatelink.mysql.database.azure.com --resource-group $AAKS_RG_NAME -o none
                        az network private-dns record-set a add-record --record-set-name mySqlServer --zone-name privatelink.mysql.database.azure.com --resource-group $AAKS_RG_NAME -a $privateIP -o none
                fi
                ;;
        postgresql)
                echo "Creating subnet for PostgreSQL database..."
                az network vnet subnet create \
                --name PGSqlSubnet  --resource-group $AAKS_RG_NAME \
                --vnet-name $AAKS_VNET_NAME --disable-private-endpoint-network-policies true \
                --address-prefixes $DB_SUBNET_CIDR -o none
                DB_SUBNET_ID=$(az network vnet subnet show -n PGSqlSubnet -g $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME --query id -o tsv)
                echo "Creating PostgreSQL database..."
                if [ "$AAKS_DB_MODE" == "flexible" ]
                then
                        DB_ZONE_PARAMS=""
                        if [ "$AAKS_AZ_ENABLE" == "y" ] && [ "$AAKS_DB_SKU" != "Standard_B"* ]
                        then
                                DB_ZONE_PARAMS="--high-availability Enabled --zone 1 --standby-zone 2"
                        fi
                        az postgres flexible-server create -l $AAKS_REGION -g $AAKS_RG_NAME -n $AAKS_DB_NAME -u $AAKS_DB_USER \
                        -p $AAKS_DB_PASSWORD --tier $AAKS_DB_TIER --sku-name $AAKS_DB_SKU --version $AAKS_DB_VERSION \
                        $DB_ZONE_PARAMS --subnet $DB_SUBNET_ID \
                        --private-dns-zone $AAKS_DB_NAME.private.postgres.database.azure.com --yes -o none
                else
                        az postgres server create -l $AAKS_REGION -g $AAKS_RG_NAME -n $AAKS_DB_NAME -u $AAKS_DB_USER \
                        -p $AAKS_DB_PASSWORD --sku-name $AAKS_DB_SKU --ssl-enforcement Enabled \
                        --public-network-access Disabled --version $AAKS_DB_VERSION -o none
                        echo "Creating Private Endpoint..."
                        az network private-endpoint create --name myPGSqlPrivateEndpoint --resource-group $AAKS_RG_NAME --vnet-name $AAKS_VNET_NAME \
                        --subnet PGSqlSubnet --private-connection-resource-id $(az resource show -g $AAKS_RG_NAME -n $AAKS_DB_NAME --resource-type "Microsoft.DBforPostgreSQL/servers" --query "id" -o tsv) \
                        --group-id postgresqlServer --connection-name pgSqlConnection -o none
                        echo "Creating Private DNS Zone and association link..."
                        az network private-dns zone create --resource-group $AAKS_RG_NAME --name "privatelink.postgres.database.azure.com" -o none
                        az network private-dns link vnet create --resource-group $AAKS_RG_NAME \
                        --zone-name "privatelink.postgres.database.azure.com" \
                        --name MyDNSLink --virtual-network $AAKS_VNET_NAME --registration-enabled false -o none
                        networkInterfaceId=$(az network private-endpoint show --name myPGSqlPrivateEndpoint --resource-group $AAKS_RG_NAME --query 'networkInterfaces[0].id' -o tsv)
                        privateIP=$(az resource show --ids $networkInterfaceId --api-version 2019-04-01 --query properties.ipConfigurations[0].properties.privateIPAddress -o tsv)
                        az network private-dns record-set a create --name pgSqlServer --zone-name privatelink.postgres.database.azure.com --resource-group $AAKS_RG_NAME -o none
                        az network private-dns record-set a add-record --record-set-name pgSqlServer --zone-name privatelink.postgres.database.azure.com --resource-group $AAKS_RG_NAME -a $privateIP -o none
                fi
                ;;
esac

echo "Proceeding with cluster internal configurations..."

echo "Getting k8s context..."
az aks get-credentials --overwrite-existing --resource-group $AAKS_RG_NAME --name $AAKS_AKS_NAME -o none

echo "Checking for kubectl..."
if [ "$(which kubectl)" = "" ]
then
        echo "kubectl not found. Installing..."
        sudo az aks install-cli
        export PATH=$PATH:/usr/local/bin
fi

#Add SecretProviderClass for KeyVault
if [ $AKS_CREATION_STATE -eq 0 ] && [ "$AAKS_KEYVAULT" != "" ]
then
        echo 'Creating SecretProviderClass CRD yaml...'
        echo "apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: $AAKS_KEYVAULT_NAME-system-msi
spec:
  provider: azure
  parameters:
    usePodIdentity: \"false\"
    useVMManagedIdentity: \"true\"  
    userAssignedIdentityID: \"$AAKS_ID\"
    keyvaultName: $AAKS_KEYVAULT_NAME
    objects:  |
      array:
        - |
          objectName: ExampleSecret
          objectType: secret        # object types: secret, key, or cert
          objectAlias: ""           # [OPTIONAL] if not provided, defaults to the object name
          objectVersion: ""         # [OPTIONAL] object versions, default to latest if empty
    tenantId: $AZ_TenantID          # The tenant ID of the key vault
        ">secretproviderclass.yaml
        echo "Applying SecretProviderClass CRD yaml..."
        kubectl apply -f secretproviderclass.yaml
        echo "Please edit secretproviderclass.yaml for additional configuration."
fi

#Install NGINX Ingress Controller if needed
if [ "AAKS_INGRESS" == "nginx" ]
then
        echo "Installing NGINX Ingress Controller..."
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.1.0/deploy/static/provider/cloud/deploy.yaml
fi

# Set up PV?
if [ "$AAKS_PVC" == "y" ] || [ "$AAKS_PVC" == "Y" ]
then
        echo "Setting up Azure Files Dynamic Persistent Volume Claim..."
        echo "Creating StorageClass for Azure Files..."
        echo "kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: azurefiles-sc
provisioner: file.csi.azure.com
mountOptions:
  - dir_mode=0755
  - file_mode=0755
  - uid=0
  - gid=0
  - mfsymlinks
  - cache=strict
  - actimeo=30
parameters:
  skuName: $AAKS_PVC_SKU
        ">azure-file-sc.yaml
        echo "Applying StorageClass..."
        kubectl apply -f azure-file-sc.yaml

        echo "Creating Persistent Volume Claim..."
        echo "apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: azurefile-pvc
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: azurefiles-sc
  resources:
    requests:
      storage: $(echo $AAKS_PVC_SIZE)Gi
        ">azure-file-pvc.yaml
        echo "Applying Persistent Volume Claim..."
        kubectl apply -f azure-file-pvc.yaml

fi

#Install demo app if needed
if [ "$AAKS_DEMOAPP" == "y" ] || [ "$AAKS_DEMOAPP" == "Y" ]
then
        echo "Creating demo app def..."
        echo "kind: Pod
apiVersion: v1
metadata:
  name: busybox-demoapp
spec:
  containers:
    - name: busybox
      image: k8s.gcr.io/e2e-test-images/busybox:1.29-1
      command:
        - \"/bin/sleep\"
        - \"10000\"
      volumeMounts:
      - name: volume-azurefiles
        mountPath: \"/mnt/azurefiles\"
      - name: secrets-store01-inline
        mountPath: \"/mnt/secrets-store\"
        readOnly: true
  volumes:
    - name: volume-azurefiles
      persistentVolumeClaim:
        claimName: azurefile-pvc
    - name: secrets-store01-inline
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: \"$AAKS_KEYVAULT_NAME-system-msi\"
          ">busybox-demoapp.yaml
          echo "Applying demo app def..."
        kubectl apply -f busybox-demoapp.yaml
fi

echo "The AKS environment is ready. Please check the $AAKS_RG_NAME resource group for the resources."