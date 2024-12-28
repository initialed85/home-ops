#!/bin/bash

set -e

echo -e "\n---- ---- ---- ----\n"

echo -e "testing a positive event...\n"

# shellcheck disable=SC2002
if ! cat test_data_positive.txt | ./handle_event.sh; then
    echo -e "\nFAILED"
else
    echo -e "\nPASSED"
fi

echo -e "\n---- ---- ---- ----\n"

echo -e "testing a negative event...\n"

# shellcheck disable=SC2002
if cat test_data_negative.txt | ./handle_event.sh; then
    echo -e "\nFAILED"
else
    echo -e "\nPASSED"
fi

echo -e "\n---- ---- ---- ----\n"
