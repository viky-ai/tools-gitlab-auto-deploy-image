# tools-gitlab-auto-deploy-image

A docker image to build docker image and deploy in kubernetes with gitlab.

Notes : since tools-gitlab-auto-deploy-image v2.0, helm 3 is required.


## Available commands

- `kubernetes`

  - `kube_setup`
    Setup a kubernetes environment
    - `kubectl` is set from `KUBECONFIG` (gitlab autoset it) or with `KUBECONFIG_URL`
    - namespace is created using `KUBE_NAMESPACE` environment variable (if not in gitlab managed cluster)
    - `kubectl` default namespace is set to `KUBE_NAMESPACE`
    - `helm` is initialized with a `tiller` service is the current namespace
    - a pull secret is created named `gitlab-registry` using gitlab ci default variables or named from env `K8S_IMAGE_PULL_SECRET_REGISTRY` using `EXTERNAL_REGISTRY*` env.
  - `kube_cleanup`
    delete a kubernetes environment
    - remove all `helm` release installation in the current namespace
    - remove `tiller` installation in the current namespace
    - remove all pods,configmaps,secrets
    - delete namespace (if not in gitlab managed cluster)
  - `kube_get_pods`
    get pods name from a selector in argument

- `docker`
  - `docker_build`
    build, tag and push an image according `CI_COMMIT_REF_SLUG`
  - `docker_tag_latest`
    tag and push image according `CI_COMMIT_REF_SLUG` to `latest`
  - `docker_digest_tag`
    pull an image and return full image tag with digest in order to pin image across deployment
  - `docker_gitlab_login`
    log to gitlab registry using `CI_REGISTRY_*`
  - `docker_external_login`
    log to an external registry using
    - `EXTERNAL_REGISTRY` for registry host or host + namespace, (by default to index.docker.io)
    - `EXTERNAL_REGISTRY_LOGIN` for login
    - `EXTERNAL_REGISTRY_PASSWORD` for password
  - `docker_push_gitlab_to_external`
    pull docker image from gitlab registry and push it to an external registry (by default to index.docker.io)
    - `first parameter`
      This Docker image from Gitlab ex: `docker-registry.example.com/organization/repository:tag`
    - `second parameter`
      This Docker image to push to the external registry ex: `organization/repository:tag` or `rg.fr-par.scw.cloud/namespace/repository:tag`
  - `docker_login` **DEPRECATED use: docker_external_login**
    log to docker registry
  - `docker_push_gitlab_to_dockerhub` **DEPRECATED use: docker_external_login**
    pull docker image from gitlab registry and push it to dockerhub
    - `first parameter`
      This Docker image from Gitlab ex: `docker-registry.example.com/organization/repository:tag`
    - `second parameter`
      This Docker image to push to dockerhub ex: `organization/repository:tag`
- `check_version` : show `docker`, `kubectl` and `helm` versions
- `notify_deployment` : notify deployment to grafana monitoring service

## Usage

Just add the following lines to your .gitlab-ci.yml :

```
image: vikyai/tools-gitlab-auto-deploy-image:latest
before_script:
  - . /auto-deploy.sh
```

Example :

```
stages:
  - build
  - deploy

image: vikyai/tools-gitlab-auto-deploy-image:latest
before_script:
  - . /auto-deploy.sh

build:
  stage: build
  script:
    - docker_build       ${CI_REGISTRY_IMAGE}
    - docker_tag_latest  ${CI_REGISTRY_IMAGE}

kube:
  stage: deploy
  environment:
    name: ${CI_COMMIT_REF_NAME}
  script:
    - kube_setup
    - helm upgrade --wait --install "${RELEASE_NAME}" stable/redis

cleanup:
  stage: deploy
  environment:
    name: ${CI_COMMIT_REF_NAME}
    action: stop
  variables:
      GIT_STRATEGY: none
  script:
    - kube_setup
    - kube_cleanup
  when: manual
  allow_failure: true
```
