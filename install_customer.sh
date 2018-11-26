#!/bin/bash
set -e
# Terminal Colors
red=$'\e[1;31m'
grn=$'\e[1;32m'
yel=$'\e[1;33m'
blu=$'\e[1;34m'
mag=$'\e[1;35m'
cyn=$'\e[1;36m'
end=$'\e[0m'
coffee=$'\xE2\x98\x95'
coffee3="${coffee} ${coffee} ${coffee}"

BX_API_ENDPOINT="api.ng.bluemix.net"
CLUSTER_NAME=$1
BX_SPACE=$2
BX_API_KEY=$3
BX_CR_NAMESPACE=""
BX_ORG=""

function check_tiller {
	kubectl --namespace=kube-system get pods | grep tiller | grep Runnin | grep 1/1
}

function print_usage {
	printf "\n\n${yel}Usage:${end}\n"
	printf "\t${cyn}./install_bluecompute.sh <cluster-name> <bluemix-space-name> <bluemix-api-key>${end}\n\n"
}

function bluemix_login {
	# Bluemix Login
	if [[ -z "${CLUSTER_NAME// }" ]]; then
		print_usage
		echo "${red}Please provide Cluster Name. Exiting..${end}"
		exit 1

	elif [[ -z "${BX_SPACE// }" ]]; then
		print_usage
		echo "${red}Please provide Bluemix Space. Exiting..${end}"
		exit 1

	elif [[ -z "${BX_API_KEY// }" ]]; then
		print_usage
		echo "${red}Please provide Bluemix API Key. Exiting..${end}"
		exit 1
	fi

	printf "${grn}Login into Bluemix${end}\n"

	export BLUEMIX_API_KEY=${BX_API_KEY}
	bx login -a ${BX_API_ENDPOINT} -s ${BX_SPACE}

	status=$?

	if [ $status -ne 0 ]; then
		printf "\n\n${red}Bluemix Login Error... Exiting.${end}\n"
		exit 1
	fi
}

function create_api_key {
	# Creating for API KEY
	if [[ -z "${BX_API_KEY// }" ]]; then
		printf "\n\n${grn}Creating API KEY...${end}\n"
		BX_API_KEY=$(bx iam api-key-create kubekey | tail -1 | awk '{print $3}')
		echo "${yel}API key 'kubekey' was created.${end}"
		echo "${mag}Please preserve the API key! It cannot be retrieved after it's created.${end}"
		echo "${cyn}Name${end}	kubekey"
		echo "${cyn}API Key${end}	${BX_API_KEY}"
	fi
}

function create_registry_namespace {	
	printf "\n\n${grn}Login into Container Registry Service${end}\n\n"
	bx cr login
	BX_CR_NAMESPACE="jenkins$(cat ~/.bluemix/config.json | jq .Account.GUID | sed 's/"//g' | tail -c 7)"
	printf "\nCreating namespace \"${BX_CR_NAMESPACE}\"...\n"
	bx cr namespace-add ${BX_CR_NAMESPACE} &> /dev/null
	echo "Done"
}

function get_cluster_name {
	printf "\n\n${grn}Login into Container Service${end}\n\n"
	bx cs init

	if [[ -z "${CLUSTER_NAME// }" ]]; then
		echo "${yel}No cluster name provided. Will try to get an existing cluster...${end}"
		CLUSTER_NAME=$(bx cs clusters | tail -1 | awk '{print $1}')

		if [[ "$CLUSTER_NAME" == "Name" ]]; then
			echo "No Kubernetes Clusters exist in your account. Please provision one and then run this script again."
			exit 1
		fi
	fi
}

function get_org {
	BX_ORG=$(cat ~/.bluemix/.cf/config.json | jq .OrganizationFields.Name | sed 's/"//g')
}

function get_space {
	if [[ -z "${BX_SPACE// }" ]]; then
		BX_SPACE=$(cat ~/.bluemix/.cf/config.json | jq .SpaceFields.Name | sed 's/"//g')
	fi
}

function set_cluster_context {
	# Getting Cluster Configuration
	unset KUBECONFIG
	printf "\n${grn}Setting terminal context to \"${CLUSTER_NAME}\"...${end}\n"
	eval "$(bx cs cluster-config ${CLUSTER_NAME} | tail -1)"
	echo "KUBECONFIG is set to = $KUBECONFIG"

	if [[ -z "${KUBECONFIG// }" ]]; then
		echo "${red}KUBECONFIG was not properly set. Exiting.${end}"
		exit 1
	fi
}

function initialize_helm {
	printf "\n\n${grn}Initializing Helm.${end}\n"
	helm init --upgrade
	echo "Waiting for Tiller (Helm's server component) to be ready..."

	TILLER_DEPLOYED=$(check_tiller)
	while [[ "${TILLER_DEPLOYED}" == "" ]]; do 
		sleep 1
		TILLER_DEPLOYED=$(check_tiller)
	done
}

function install_bluecompute_customer {
	printf "\n\n${grn}Installing customer chart. This will take a few minutes...${end} ${coffee3}\n\n"
	cd chart

	time helm install --name customer --debug --wait --timeout 600 \
	--set configMap.bluemixOrg=${BX_ORG} \
	--set configMap.bluemixSpace=${BX_SPACE} \
	--set configMap.bluemixRegistryNamespace=${BX_CR_NAMESPACE} \
	--set configMap.kubeClusterName=${CLUSTER_NAME} \
	--set secret.apiKey=${BX_API_KEY} \
	customer

	printf "\n\n${grn}customer was successfully installed!${end}\n"
	printf "\n\n${grn}Cleaning up...${end}\n"
	kubectl delete pods,jobs -l heritage=Tiller

	cd ..
}

# Setup Stuff
bluemix_login
create_api_key
create_registry_namespace
get_cluster_name
get_org
get_space
set_cluster_context
initialize_helm

# Install Bluecompute
install_bluecompute_customer

printf "\n\nTo see Kubernetes Dashboard, paste the following in your terminal:\n"
echo "${cyn}export KUBECONFIG=${KUBECONFIG}${end}"

printf "\nThen run this command to connect to Kubernetes Dashboard:\n"
echo "${cyn}kubectl proxy${end}"

printf "\nThen open a browser window and paste the following URL to see the Services created by customer Chart:\n"
echo "${cyn}http://127.0.0.1:8001/api/v1/proxy/namespaces/kube-system/services/kubernetes-dashboard/#/service?namespace=default${end}"