#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

kustomize build ${ROOT}/storage-version-migrator | sed -e "s/NAMESPACE/kube-system/g" > ${ROOT}/../lib/porkadot/assets/kubernetes/manifests/storage-version-migrator.yaml.erb
