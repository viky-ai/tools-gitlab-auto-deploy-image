# docker build --pull -t vikyai/tools-gitlab-auto-deploy-image .
#
FROM docker:stable

ARG HELM_VERSION=3.3.1
ARG KUBERNETES_VERSION=1.18.8

# Install Dependencies
RUN apk --no-cache add -U \
  bash \
  ca-certificates \
  curl \
  gettext \
  git \
  gzip \
  openssl \
  tar \
  util-linux \
  vim \
  && curl -sS "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" | tar zx \
  && mv linux-amd64/helm   /usr/local/bin/ \
  && curl -sSL -o /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/v${KUBERNETES_VERSION}/bin/linux/amd64/kubectl" \
  && chmod +x /usr/local/bin/kubectl

#COPY src/entrypoint.sh    /entrypoint.sh
COPY src/auto-deploy.sh   /auto-deploy.sh
RUN echo ". /auto-deploy.sh" > $HOME/.profile

ENTRYPOINT []
CMD [ "/bin/bash", "-e", "-l"]
