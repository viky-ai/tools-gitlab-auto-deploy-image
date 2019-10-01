#!/bin/bash -e

[[ "$TRACE" ]] && set -x

# Check tools version
function check_version() {

  echo "Docker (https://kubernetes.io) :"
  docker --version || true
  echo  " "

  echo "Kubernetes (https://kubernetes.io) :"
  kubectl version || true
  echo  " "

  echo "Helm (https://helm.sh/) :"
  helm version || true
  echo  " "
}
export -f check_version

####################################################################
#
# KUBERNETES Shortcuts
#
####################################################################
if [[ "${CI_ENVIRONMENT_SLUG}" == "" ]]; then
  export CI_ENVIRONMENT_SLUG="autodeploy"
fi
export RELEASE_NAME="${HELM_RELEASE_NAME:-$CI_ENVIRONMENT_SLUG}"
export HELM_RELEASE_NAME="${RELEASE_NAME}"
export KUBE_NAMESPACE="${KUBE_NAMESPACE:-$CI_ENVIRONMENT_SLUG}"
export TILLER_NAMESPACE="${KUBE_NAMESPACE}"
export SERVICE_ACCOUNT="${KUBE_NAMESPACE}-service-account"

# Setup all resources to use kubernetes
function kube_setup() {
  kube_config
  kube_namespace
  kube_initialize_tiller
  kube_create_pull_secret
  check_version
}
export -f kube_setup

# Remove all resources allocated in kubernetes (delete env)
function kube_cleanup() {
  kube_delete_helm_release
  kube_delete_tiller
  kube_delete_resources
  kube_delete_namespace
}
export -f kube_cleanup

function kube_config() {
  if [[ "${KUBECONFIG_URL}" != "" ]]; then
    curl -s -o /alternate_kubeconfig "${KUBECONFIG_URL}"
    export KUBECONFIG="/alternate_kube_config"
    echo "Using KUBECONFIG=/alternate_kube_config to connect to kubernetes"
  fi

  if [[ "${KUBECONFIG}" == "" ]]; then
    echo "You must set KUBECONFIG or KUBE_CONFIG_URL env to use kubernetes"
    return 1
  fi
  echo "Kubernetes   cluster: $(kubectl config current-context)"
}

function kube_namespace() {
  kubectl get namespace "${KUBE_NAMESPACE}" > /dev/null 2>&1 || kubectl create namespace "${KUBE_NAMESPACE}" > /dev/null
  kubectl config set-context --current --namespace="${KUBE_NAMESPACE}" > /dev/null
  echo "Kubernetes namespace: $(kubectl get namespace "${KUBE_NAMESPACE}" -o name)"
}

function kube_initialize_tiller() {
  export TILLER_SERVICE_ACCOUNT="${TILLER_NAMESPACE}-service-account"
  kubectl get serviceaccounts -n "${TILLER_NAMESPACE}" "${TILLER_SERVICE_ACCOUNT}" > /dev/null 2>&1 || TILLER_SERVICE_ACCOUNT="default"

  helm init --upgrade --wait --history-max=5 \
    --tiller-connection-timeout=30 \
    --service-account "${TILLER_SERVICE_ACCOUNT}" \
    --tiller-namespace "${TILLER_NAMESPACE}" > /dev/null
}

function kube_create_pull_secret() {

  if [[ "$CI_PROJECT_VISIBILITY" == "public" ]]; then
    return
  fi

  echo "Creating pull secret ..."
  if [[ "${CI_REGISTRY_USER}" == "" ]]; then
    echo "You must set CI_REGISTRY_USER env to use kubernetes"
    return 1
  fi
  if [[ "${CI_REGISTRY_PASSWORD}" == "" ]]; then
    echo "You must set CI_REGISTRY_PASSWORD env to use kubernetes"
    return 1
  fi
  if [[ "${GITLAB_USER_EMAIL}" == "" ]]; then
    echo "You must set GITLAB_USER_EMAIL env to use kubernetes"
    return 1
  fi

  kubectl create secret -n "${KUBE_NAMESPACE}" \
    docker-registry gitlab-registry \
    --docker-server="${CI_REGISTRY}" \
    --docker-username="${CI_DEPLOY_USER:-$CI_REGISTRY_USER}" \
    --docker-password="${CI_DEPLOY_PASSWORD:-$CI_REGISTRY_PASSWORD}" \
    --docker-email="${GITLAB_USER_EMAIL}" \
    -o yaml --dry-run | kubectl replace -n "${KUBE_NAMESPACE}" --force -f -
}

function kube_delete_helm_release() {
  HELM_ALL_NAMESPACE_RELEASE=$(helm ls -q)
  if [[ "${HELM_ALL_NAMESPACE_RELEASE}" != "" ]]; then
    for r in ${HELM_ALL_NAMESPACE_RELEASE} ; do
	    helm delete --purge --no-hooks "${r}" || true
    done
  else
    helm delete --purge --no-hooks "${RELEASE_NAME}" || true
  fi
  sleep 5
}

function kube_delete_tiller() {
  kubectl delete deployment,svc --ignore-not-found --namespace "${KUBE_NAMESPACE}" tiller-deploy || true
  kubectl delete cm --ignore-not-found --namespace "${KUBE_NAMESPACE}" '*.v*' || true
}

function kube_delete_resources() {
  kubectl delete all,cm,pvc,pdb --ignore-not-found --namespace "${KUBE_NAMESPACE}" --all || true
  kubectl delete secret --ignore-not-found --namespace "${KUBE_NAMESPACE}" gitlab-registry || true
}

function kube_delete_namespace() {
  # gitab managed kubernetes does no allow to delete namespace
  kubectl delete namespace "${KUBE_NAMESPACE}" 2> /dev/null || true
}

# List all pods name matching selector in agrs
function kube_get_pods() {

  if [[ "$1" == "" ]]; then
    echo "Usage :"
    echo "  kube_get_pods selector"
    echo ""
    echo " * selector is mandatory"
    echo ""
    return 1
  fi

  if [[ "${KUBECONFIG}" == "" ]]; then
    echo "You must set KUBECONFIG or KUBE_CONFIG_URL env to use kubernetes"
    return 2
  fi

  local KUBE_SELECTOR="$1"
  kubectl get pods --namespace="${KUBE_NAMESPACE}" \
    -l "${KUBE_SELECTOR}" \
    --no-headers \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}'
}
export -f kube_get_pods

####################################################################
#
# DOCKER Shortcut
#
####################################################################

export DOCKER_TLS_CERTDIR=""
if [[ "${DOCKER_HOST}" == "" ]]; then
  # Use DooD (dooker out of doker) if dood service exist
  if [[ "${DOOD_PORT}" != "" ]]; then
    export DOCKER_HOST="${DOOD_PORT}"
  fi
fi

function docker_build() {

  if [[ "$1" == "" ]]; then
    echo "Usage :"
    echo "  docker_build image_name [build_dir] [build_args]"
    echo ""
    echo " * image_name is mandatory"
    echo ""
    return 1
  fi

  if [[ "${DOCKER_HOST}" == "" ]]; then
    echo "DOCKER_HOST en must be set to use docker."
    return 2
  fi

  # login to private registry
  docker_login

  local TIMESTAMP=$(date +%Y%m%d%H%M%S)
  local CI_DOCKER_IMAGE="$1:${CI_COMMIT_REF_SLUG:-$TIMESTAMP}"
  local CI_DOCKER_DIR="${2:-.}"
  local CI_DOCKER_IMAGE_BUILD_OPT="$3"

  echo ""
  echo "Build docker image ${CI_DOCKER_IMAGE} from dir ${CI_DOCKER_DIR} ..."
  docker build --pull ${CI_DOCKER_IMAGE_BUILD_OPT} -t ${CI_DOCKER_IMAGE} ${CI_DOCKER_DIR}

  echo ""
  echo "Pushing ${CI_DOCKER_IMAGE} to GitLab Container Registry ..."
  docker push ${CI_DOCKER_IMAGE}

  echo ""
}
export -f docker_build

function docker_tag_latest() {

  if [[ "$1" == "" ]]; then
    echo "Usage :"
    echo "  docker_tag_latest image_name"
    echo ""
    echo " * image_name is mandatory"
    echo ""
    return 1
  fi

  if [[ "${DOCKER_HOST}" == "" ]]; then
    echo "DOCKER_HOST en must be set to use docker."
    return 2
  fi

  # login to private registry
  docker_login

  local CI_DOCKER_IMAGE="$1"
  local CI_DOCKER_IMAGE="$1:${CI_COMMIT_REF_SLUG:-latest}"
  local CI_DOCKER_IMAGE_LATEST="$1:latest"

  echo "Pulling ${CI_DOCKER_IMAGE}"
  docker pull ${CI_DOCKER_IMAGE}

  echo "Taggging ${CI_DOCKER_IMAGE} to ${CI_DOCKER_IMAGE_LATEST}"
  docker tag ${CI_DOCKER_IMAGE} ${CI_DOCKER_IMAGE_LATEST}

  echo "Pushing ${CI_DOCKER_IMAGE_LATEST} to registry ..."
  docker push ${CI_DOCKER_IMAGE_LATEST}
  echo ""
}
export -f docker_tag_latest

function docker_login() {
  if [[ -n "$CI_REGISTRY_USER" ]]; then
    echo "Logging to GitLab Container Registry with CI credentials ..."
    echo "${CI_REGISTRY_PASSWORD}" | docker login --username "${CI_REGISTRY_USER}" --password-stdin "${CI_REGISTRY}"
    echo ""
  fi
}
export -f docker_login
