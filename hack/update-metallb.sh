#!/bin/bash

ROOT=$(dirname "${BASH_SOURCE}")/..
ROOT=$(cd ${ROOT} && pwd)

kubectl kustomize ${ROOT}/hack/metallb/crds > ${ROOT}/lib/porkadot/assets/kubernetes/manifests/addons/metallb/crds.yaml
kubectl kustomize ${ROOT}/hack/metallb > ${ROOT}/lib/porkadot/assets/kubernetes/manifests/addons/metallb/metallb.yaml.erb
