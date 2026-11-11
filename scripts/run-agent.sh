#!/bin/bash
cd /home/wineuser/tmrc
# TM_MODE=train runs the SAC vector trainer; default runs the driving agents.
if [ "${TM_MODE}" = "train" ]; then
    exec uv run agent/train_sac_vec.py
fi
exec uv run agent/launcher.py
