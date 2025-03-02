#!/bin/bash

docker build --platform=linux/amd64 -t kube-registry:5000/keepalived -f ./Dockerfile .

docker image push --platform=linux/amd64 kube-registry:5000/keepalived
