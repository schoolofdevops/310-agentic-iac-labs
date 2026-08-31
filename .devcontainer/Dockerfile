# 310 — Agentic IaC lab environment.
# Pin everything. A course that drifts with upstream is a course that generates support tickets.
FROM mcr.microsoft.com/devcontainers/base:ubuntu-24.04

ARG TERRAFORM_VERSION=1.16.0
ARG OPENTOFU_VERSION=1.12.2
ARG TRIVY_VERSION=0.74.0
ARG CHECKOV_VERSION=3.3.16
ARG KIND_VERSION=0.32.0
ARG HELM_VERSION=4.0.0
ARG KUBECTL_VERSION=1.34.0
ARG INFRACOST_VERSION=0.10.44
ARG CONFTEST_VERSION=0.68.2

USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl unzip jq git ca-certificates python3-pip mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Terraform + OpenTofu — one language, two runtimes
RUN curl -fsSL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -o /tmp/tf.zip \
    && unzip -q /tmp/tf.zip -d /usr/local/bin && rm /tmp/tf.zip
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_amd64.zip" -o /tmp/tofu.zip \
    && unzip -q /tmp/tofu.zip -d /tmp/tofu && mv /tmp/tofu/tofu /usr/local/bin/ && rm -rf /tmp/tofu*

# Verification ladder (M09) — Trivy AND Checkov, always both
RUN curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz" \
      | tar xz -C /usr/local/bin trivy
RUN pip install --no-cache-dir --break-system-packages "checkov==${CHECKOV_VERSION}"
RUN curl -fsSL "https://github.com/open-policy-agent/conftest/releases/download/v${CONFTEST_VERSION}/conftest_${CONFTEST_VERSION}_Linux_x86_64.tar.gz" \
      | tar xz -C /usr/local/bin conftest
RUN curl -fsSL "https://github.com/infracost/infracost/releases/download/v${INFRACOST_VERSION}/infracost-linux-amd64.tar.gz" \
      | tar xz -C /tmp && mv /tmp/infracost-linux-amd64 /usr/local/bin/infracost

# Tier 2 — Kubernetes
RUN curl -fsSLo /usr/local/bin/kind "https://kind.sigs.k8s.io/dl/v${KIND_VERSION}/kind-linux-amd64" && chmod +x /usr/local/bin/kind
RUN curl -fsSLo /usr/local/bin/kubectl "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && chmod +x /usr/local/bin/kubectl
RUN curl -fsSL "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
      | tar xz -C /tmp && mv /tmp/linux-amd64/helm /usr/local/bin/ && rm -rf /tmp/linux-amd64

USER vscode
