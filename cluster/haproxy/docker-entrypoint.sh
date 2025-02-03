#!/bin/bash

set -e

/usr/sbin/haproxy -f /etc/haproxy/haproxy.cfg -V
