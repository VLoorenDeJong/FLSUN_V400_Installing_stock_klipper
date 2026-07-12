#!/bin/bash
# Migrate old phase marker files to new scheme if needed
STATE_DIR="/var/lib/linuxsetups"
[ -f "$STATE_DIR/phase1_complete" ] && mv "$STATE_DIR/phase1_complete" "$STATE_DIR/phase1.done"
[ -f "$STATE_DIR/phase2_complete" ] && mv "$STATE_DIR/phase2_complete" "$STATE_DIR/phase2.done"
