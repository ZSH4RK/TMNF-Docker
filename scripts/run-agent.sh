#!/bin/bash
cd /home/wineuser/tmrc
# TM_MODE picks what the container runs. Every mode records a run under
# results/ (bind-mounted to TMRC/results on the host):
#   train         SAC vector trainer (N instances, one shared learner)
#   train_single  single-instance SAC trainer
#   eval          evaluate TM_EVAL_AGENT for TM_EVAL_EPISODES episodes
#   verify        re-drive the replay at TM_REPLAY and check it reproduces
#   script        run your own Python file: TM_SCRIPT (relative to tmrc/)
#   anything else plain driving agents (TM_AGENT, default my_agent.py)
case "${TM_MODE}" in
    train)        exec uv run agent/train_sac_vec.py ;;
    train_single) exec uv run agent/train_sac.py ;;
    eval)         exec uv run agent/evaluate.py ;;
    verify)       exec uv run agent/verify_replay.py ;;
    script)       exec uv run "${TM_SCRIPT:?set TM_SCRIPT to the file to run, e.g. agent/examples/hill_climb.py}" ;;
    *)            exec uv run agent/launcher.py ;;
esac
