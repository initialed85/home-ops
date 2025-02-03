#!/bin/bash

set -e

DRY_RUN="${DRY_RUN:-1}"
DEBUG="${DEBUG:-1}"
CAMERA_ID="a37a2206-a5e7-4547-90c5-d9220ba3d992"
CLASS_NAME="person"

export DRY_RUN
export DEBUG
export CAMERA_ID
export CLASS_NAME

echo -e "!!!! running tests..."

echo -e "\n!!!! testing a positive event..."

# shellcheck disable=SC2002
cat test_data_positive.json | ./handle_event.sh || true

echo -e "\n!!!! testing a negative event..."

# shellcheck disable=SC2002
cat test_data_negative.json | ./handle_event.sh || true
