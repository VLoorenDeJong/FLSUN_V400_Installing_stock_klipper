#!/bin/bash
# Mark Phase 1 as complete
mkdir -p /var/lib/linuxsetups
PHASE1_MARKER="/var/lib/linuxsetups/phase1.done"
touch "$PHASE1_MARKER"
