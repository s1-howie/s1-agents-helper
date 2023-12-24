#!/bin/bash
# This script automates the steps discussed in: 
# https://community.sentinelone.com/s/article/000006134

# NOTE: Please be aware that there is a 100 pulls/hour rate limit for the repository!!

# Please provide a value for the S1_SITE_TOKEN:
S1_SITE_TOKEN=$1

# Please provide values for your registry username and password
S1_REGISTRY_USERNAME=$2
S1_REGISTRY_PASSWORD=$3

# The value of the S1_AGENT_TAG controls the version of the agent. ie: 23.3.2-ga, 23.4.1-ea, etc
S1_AGENT_TAG=$4

S1_AGENT_LOG_LEVEL="${$5:-info}"  # Please use the default of'info' for production deployments

# We derive the helm release/chart version from the SentinelOne Agent version/tag + set the s1helper tag to be the same as the s1agent tag
HELM_RELEASE_VERSION=$(echo $S1_AGENT_TAG | cut -d "-" -f1) # ie: 23.4.1
S1_HELPER_TAG=$S1_AGENT_TAG

# The following variable values can be customized as you see fit (or can be left as is).
S1_PULL_SECRET_NAME=sentinelone-registry
HELM_RELEASE_NAME=sentinelone
S1_NAMESPACE=sentinelone
# Resource Limits and Requests for Agent
S1_AGENT_LIMITS_MEMORY='1945Mi'
S1_AGENT_LIMITS_CPU='900m'
S1_AGENT_REQUESTS_MEMORY='800Mi'
S1_AGENT_REQUESTS_CPU='500m'
# Resource Limits and Requests for Helper
S1_HELPER_LIMITS_MEMORY='1945Mi'
S1_HELPER_LIMITS_CPU='900m'
S1_HELPER_REQUESTS_MEMORY='100Mi'
S1_HELPER_REQUESTS_CPU='100m'
# Environment
S1_AGENT_HEAP_TRIMMING_ENABLE='true'
S1_PROXY=''
S1_DV_PROXY=''

# The following variables SHOULD NOT BE ALTERED
REPO_BASE=containers.sentinelone.net
REPO_HELPER=$REPO_BASE/cws-agent/s1helper
REPO_AGENT=$REPO_BASE/cws-agent/s1agent


# Color control constants
Color_Off='\033[0m'       # Text Resets
Black='\033[0;30m'        # Black
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan
White='\033[0;37m'        # White

# Check for prerequisite binaries
if ! command -v kubectl &> /dev/null ; then
    printf "\n${Red}Missing the 'kubectl' utility.  Please install this utility and try again.\n"
    printf "Reference:  https://kubernetes.io/docs/tasks/tools/install-kubectl/\n${Color_Off}"
    exit 1
fi

if ! command -v kubectl get nodes  &> /dev/null ; then
    printf "\n${Red}Unable to issue 'kubectl get nodes' command.  Please ensure that a valid context has been established with the target cluster.\n"
    printf "ie: kubectl config get-context\n"
    printf "kubectl config use-context CONTEXT\n${Color_Off}"
    exit 1
fi

if ! command -v helm &> /dev/null ; then
    printf "\n${Red}Missing the 'helm' utility!  Please install this utility and try again.\n"
    printf "Reference:  https://helm.sh/docs/intro/install/\n${Color_Off}"
    exit 1
fi

# Check if the minimum number of arguments have been passed
if [ $# -lt 4 ]; then
    printf "\n${Red}ERROR:  Expecting at least 4 arguments to be passed. \n${Color_Off}"
    printf "Example usage: \n"
    printf "ie:${Green}  $0 \$S1_SITE_TOKEN \$S1_REGISTRY_USERNAME \$S1_REGISTRY_PASSWORD 23.4.1-ea debug \n${Color_Off}"
    printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Purple}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
    printf "\nFor instructions on obtaining ${Purple}Registry Credentials${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Purple}https://community.sentinelone.com/s/article/000008771 ${Color_Off} \n\n"
    exit 1
fi

# Check if Site Token is in the right format
if ! [ echo $S1_SITE_TOKEN | base64 -d | grep sentinelone.net &> /dev/null ]; then
    printf "\n${Red}ERROR:  Site Token does not decode correctly.  Please ensure that you've passed a valid Site Token as the first argument to the script. \n${Color_Off}"
    printf "\nFor instructions on obtaining a ${Purple}Site Token${Color_Off} from the SentinelOne management console, please see the following KB article:\n"
    printf "    ${Purple}https://community.sentinelone.com/s/article/000004904 ${Color_Off} \n\n"
    exit 1
fi

# Get cluster name from the current context
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[].name}')
printf "\n${Purple}Cluster Name:  $CLUSTER_NAME\n${Color_Off}"

# Create namespace for S1 resources
printf "\n${Purple}Creating namespace...\n${Color_Off}"
kubectl create namespace ${S1_NAMESPACE}

# Create Kubernetes secret to house the credentials for accessing the container registry repos
printf "\n${Purple}Creating K8s secret ${S1_PULL_SECRET_NAME}...\n${Color_Off}"
if ! kubectl get secret ${S1_PULL_SECRET_NAME} -n ${S1_NAMESPACE} &> /dev/null ; then
    printf "\n${Purple}Creating secret for S1 image download in K8s...\n${Color_Off}"
    kubectl create secret docker-registry -n ${S1_NAMESPACE} ${S1_PULL_SECRET_NAME} \
        --docker-username="${S1_REGISTRY_USERNAME}" \
        --docker-server="${REPO_BASE}" \
        --docker-password="${S1_REGISTRY_PASSWORD}"
fi

# Add the SentinelOne helm repo
printf "\n${Purple}Adding SentinelOne Helm Repo...\n${Color_Off}"
helm repo add sentinelone https://charts.sentinelone.com

# Ensure we're using the latest chart
printf "\n${Purple}Running helm repo update...\n${Color_Off}"
helm repo update

# Deploy S1 agent!  Upgrade it if it already exists
printf "\n${Purple}Deploying Helm Chart...\n${Color_Off}"
helm upgrade --install ${HELM_RELEASE_NAME} --namespace=${S1_NAMESPACE} --version ${HELM_RELEASE_VERSION} \
    --set secrets.imagePullSecret=${S1_PULL_SECRET_NAME} \
    --set secrets.site_key.value=${S1_SITE_TOKEN} \
    --set configuration.repositories.agent=${REPO_AGENT} \
    --set configuration.tag.agent=${S1_AGENT_TAG} \
    --set configuration.repositories.helper=${REPO_HELPER} \
    --set configuration.tag.helper=${S1_HELPER_TAG} \
    --set configuration.cluster.name=$CLUSTER_NAME \
    --set helper.nodeSelector."kubernetes\\.io/os"=linux \
    --set agent.nodeSelector."kubernetes\\.io/os"=linux \
    --set helper.resources.limits.memory=${S1_HELPER_LIMITS_MEMORY} \
    --set helper.resources.limits.cpu=${S1_HELPER_LIMITS_CPU} \
    --set helper.resources.requests.memory=${S1_HELPER_REQUESTS_MEMORY} \
    --set helper.resources.requests.cpu=${S1_HELPER_REQUESTS_CPU} \
    --set agent.resources.limits.memory=${S1_AGENT_LIMITS_MEMORY} \
    --set agent.resources.limits.cpu=${S1_AGENT_LIMITS_CPU} \
    --set agent.resources.requests.memory=${S1_AGENT_REQUESTS_MEMORY} \
    --set agent.resources.requests.cpu=${S1_AGENT_REQUESTS_CPU} \
    --set configuration.env.agent.heap_trimming_enable=${S1_AGENT_HEAP_TRIMMING_ENABLE} \
    --set configuration.env.agent.log_level=${S1_AGENT_LOG_LEVEL} \
    --set configuration.proxy=${S1_PROXY} \
    --set configuration.dv_proxy=${S1_DV_PROXY} \
    sentinelone/s1-agent

# Check the status of the pods
printf "\n${Purple}Running: kubectl wait --for=condition=ready --timeout=60s pod -n $S1_NAMESPACE -l app=s1-agent\n${Color_Off}"
printf "\n${Purple}This should take less than 60 seconds...\n${Color_Off}"
kubectl wait --for=condition=ready pod -n $S1_NAMESPACE -l app=s1-agent
