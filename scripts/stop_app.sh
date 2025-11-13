#!/bin/bash
set -euxo pipefail
if systemctl is-active --quiet demo.service; then
  sudo systemctl stop demo.service
fi
