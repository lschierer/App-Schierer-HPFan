#!/bin/bash

set -e

# Install Pandoc (ARM64)
curl -L https://github.com/jgm/pandoc/releases/download/3.8.3/pandoc-3.8.3-1-arm64.deb -o /tmp/pandoc.deb
#dpkg -i /tmp/pandoc.deb
rm /tmp/pandoc.deb

# Install graphviz, libgd-dev, and fonts
apt-get update && apt-get install -y graphviz libgd-dev fonts-dejavu && rm -rf /var/lib/apt/lists/*
fc-cache -f -v

