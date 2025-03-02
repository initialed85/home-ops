#!/bin/bash

set -e

docker build -t kube-registry:5000/camry-home-assistant-webhook  -f ./Dockerfile . 

docker image push kube-registry:5000/camry-home-assistant-webhook

# docker run --rm -it camry-home-assistant-webhook
