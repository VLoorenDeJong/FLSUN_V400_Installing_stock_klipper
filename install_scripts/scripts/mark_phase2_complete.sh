#!/bin/bash
# Mark Phase 2 as complete
mkdir -p /var/lib/linuxsetups
PHASE2_MARKER="/var/lib/linuxsetups/phase2.done"
touch "$PHASE2_MARKER"
