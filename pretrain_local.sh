#!/bin/bash
set -euo pipefail

if [ $# -eq 0 ]
then
    echo "No arguments supplied. Exiting."
    exit 1
else
    epochs=$1
    run_uuid=$2
    random_seed=$3
    dataset_name="${4:-gb1}"
fi

export PROVENANCE_RUN_ID="$run_uuid"

# Install mldag at the exact version baked in at DAG generation time.
# --no-deps: provenance modules are pure stdlib; avoids pulling in pandas/polars/etc.
pip install --quiet --no-deps --target="$PWD/.mldag" "git+https://github.com/iross/MLDAG@v${MLDAG_VERSION:?MLDAG_VERSION not set}"
export PYTHONPATH="$PWD/.mldag${PYTHONPATH:+:$PYTHONPATH}"

_provenance_capture_and_emit() {
    # Best-effort: mldag.provenance.autocapture.capture_and_emit() never
    # raises internally, but this wraps the whole thing anyway (torch
    # itself might be missing) so a broken capture step can never abort the
    # training job -- unlike the old inline heredoc this replaced, which ran
    # under `|| exit 1` and would fail the whole job over e.g. a torch
    # import error. GPU info is detected here via torch.cuda (more precise
    # than autocapture's own nvidia-smi/proc fallback, which is used when no
    # override is passed) and handed to capture_and_emit as an override.
    python3 - <<'PYEOF'
try:
    from mldag.provenance.autocapture import capture_and_emit

    gpu_info = None
    try:
        import torch

        gpu_count = torch.cuda.device_count()
        gpu_info = {
            "gpu_count": gpu_count,
            "gpu_model": torch.cuda.get_device_name(0) if gpu_count > 0 else "none",
        }
        try:
            if gpu_count > 0:
                gpu_info["gpu_id"] = str(torch.cuda.get_device_properties(0).uuid)
        except AttributeError:
            from mldag.provenance.autocapture import default_gpu_info

            gpu_info["gpu_id"] = default_gpu_info()[0]["gpu_id"]
    except ImportError:
        pass

    capture_and_emit(gpu_info=gpu_info)
except Exception:
    pass
PYEOF
}

_provenance_capture_and_emit

echo "Looking around a bit"
pwd
ls

ln -s /workspace/metl/data/ .

data_dirs=( "${dataset_name}"*/ )
data_dir="${data_dirs[0]%/}"
[[ -d "$data_dir" ]] || { echo "No data directory found for ${dataset_name}" >&2; exit 1; }

split_dir=$(find "${data_dir}/splits" -mindepth 1 -maxdepth 1 -type d -name 'standard_*' | head -1)
[[ -n "$split_dir" ]] || { echo "No splits subdirectory found in ${data_dir}/splits" >&2; exit 1; }

echo "Using $split_dir as split path"

mkdir -p wandb wandb_data
export WANDB_DIR=$PWD/wandb
export WANDB_DATA_DIR=$PWD/wandb_data
export WANDB_CACHE_DIR=$PWD/wandb/.cache
export WANDB_CONFIG_DIR=$PWD/wandb/.config
export REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt

_TRAIN_START=$(python3 -c "import time; print(time.time())")

python /workspace/metl/code/train_source_model.py @/workspace/metl/args/pretrain_local.txt \
    --ds_fn "$PWD/${data_dir}/${dataset_name}.db"   \
    --split_dir "$PWD/${split_dir}" \
    --max_epochs "$epochs" --uuid="$run_uuid"  \
    --random_seed "$random_seed"

_watcher_args=(--one-shot --start-time "$_TRAIN_START")
[ -f disk_bench.json ] && _watcher_args+=(--extra-sidecar-json disk_bench.json)
python3 -m mldag.provenance.watcher "$PWD" "${PROVENANCE_RUN_ID:-$run_uuid}" "${_watcher_args[@]}"
