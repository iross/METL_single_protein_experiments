# Single-protein METL pretraining across GPU device types

An HTCondor DAG experiment that pretrains [METL](https://github.com/gitter-lab/metl) source models
on eight single-protein Rosetta datasets. Each run is pinned to one specific GPU model with
`require_gpus`. DAG generation, provenance tracking and reporting come from
[mldag](https://github.com/iross/MLDAG) (pinned in `pyproject.toml`).

The sweep is every combination of:

- **Protein:** avgfp, dlg4, gb1, grb2, pab1, pten, tem-1, ube4b
- **GPU:** A100 40GB/80GB, A100 MIG 3g.40gb, GTX 1080 Ti, RTX 2080 Ti, H100, H200, L40, L40S

Each run trains for 30 epochs, one epoch per job, with checkpoints carried between jobs.

## Files

| File | Purpose |
|---|---|
| `Experiment.yaml` | Submit template, sweep variables, epoch counts, post-script |
| `resources.yaml` | Compute resources to target (only `default` here) |
| `config.example.yaml` | Template for `config.yaml` (W&B API key) |
| `pretrain_local.sh` | Job script: installs mldag, records provenance, runs training |
| `sync_and_clean.sh` | DAGMan post-hook: rsyncs `output/` to staging, prunes local checkpoints |
| `justfile` | Recipes for generating, submitting and reporting |

## External inputs

These are not in the repo and must exist on OSDF (edit the paths in `Experiment.yaml` to use your
own):

- **Container:** `osdf:///chtc/staging/iaross/metl_local.sif`. It has to provide the METL code at
  `/workspace/metl` (`code/train_source_model.py`, `args/pretrain_local.txt`, `data/`) along
  with PyTorch and pip.
- **Datasets:** `osdf:///chtc/staging/iaross/metl_rosetta_datasets/processed-<protein>.tar.gz`,
  each unpacking to a `<protein>*/` directory that contains `<protein>.db` and
  `splits/standard_*/`.
- **Sync destination:** the `post_script` argument in `Experiment.yaml`
  (`/staging/iaross/...`) needs to be a directory you can write to from the access point.

## Usage

On a Linux HTCondor access point (mldag depends on the `htcondor` Python bindings, which only
ship Linux wheels) with [uv](https://docs.astral.sh/uv/) and
[just](https://github.com/casey/just):

```bash
cp config.example.yaml config.yaml   # add your W&B API key
just install                         # uv sync
just create                          # generate the .dag from Experiment.yaml
just run                             # condor_submit_dag
```

Reporting, once jobs have run:

```bash
just full-report          # CSV + dated report directory
just recent-summary 48    # activity over the last 48 hours
```

`just clean` deletes generated DAG files, run directories and `output/`.

## Secrets

`mldag-gen` writes the W&B API key from `config.yaml` into the `environment` line of the generated
`.dag` file as plain text. `config.yaml` and `*.dag*` are gitignored, so don't force-add them.
