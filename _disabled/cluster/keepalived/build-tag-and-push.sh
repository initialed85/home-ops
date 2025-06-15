#!/bin/bash

# docker build --platform=linux/amd64 -t kube-registry:5000/keepalived -f ./Dockerfile .
# docker image push --platform=linux/amd64 kube-registry:5000/keepalived

docker build --platform=linux/amd64 -t initialed85/keepalived -f ./Dockerfile .
docker image push --platform=linux/amd64 initialed85/keepalived
