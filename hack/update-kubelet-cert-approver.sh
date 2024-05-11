#!/bin/bash

ROOT=$(dirname "${BASH_SOURCE}")/..
ROOT=$(cd ${ROOT} && pwd)

curl -L https://github.com/alex1989hu/kubelet-serving-cert-approver/raw/main/deploy/standalone-install.yaml > ${ROOT}/lib/porkadot/assets/kubernetes/manifests/addons/kubelet-serving-cert-approver/src.yaml.erb
