#!/bin/bash

set -eu
export LC_ALL=C
ROOT=$(dirname "${BASH_SOURCE}")

kubectl kustomize ${ROOT}/storage-version-migrator | sed -e "s/NAMESPACE/kube-system/g" > ${ROOT}/../lib/porkadot/assets/kubernetes/manifests/addons/storage-version-migrator/storage-version-migrator.yaml.erb
