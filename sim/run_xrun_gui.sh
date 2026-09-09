#!/usr/bin/env bash
set -e

# Launch Xcelium/SimVision with full signal access.

xrun -64bit -sv \
  -f files.f \
  -top tb_tmh_event_gen_linear \
  -access +rwc \
  -gui
