#!/bin/bash

# docker build --platform=linux/amd64 -t kube-registry:5000/haproxy -f ./Dockerfile .
# docker image push --platform=linux/amd64 kube-registry:5000/haproxy

docker build --platform=linux/amd64 -t initialed85/haproxy -f ./Dockerfile .
docker image push --platform=linux/amd64 initialed85/haproxy
