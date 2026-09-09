#!/usr/bin/env bash
set -e

# Standalone unit-level simulation using the minimal ariane_pkg stub.
# Run this script from this directory.

xrun -64bit -sv \
  -f files.f \
  -top tb_tmh_event_gen_linear \
  -access +rwc
