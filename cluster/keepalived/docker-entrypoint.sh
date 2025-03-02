#!/bin/bash

set -e

/usr/sbin/keepalived -l -D -S 7 -X -n -f "/etc/keepalived/${HOSTNAME}.conf"
