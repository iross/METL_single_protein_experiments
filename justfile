# Install / sync dependencies
install:
    uv sync

clean:
    rm -f *.dag *.dag.* metl.log nodes.dag.status
    find . -maxdepth 1 -type d -name '????????' -exec rm -rf {} +
    rm -rf output/

create:
    uv run mldag-gen

run:
    #!/usr/bin/env bash
    set -euo pipefail
    exp=$(grep "^name:" Experiment.yaml | cut -d'"' -f 2)
    dag=${exp// /_}
    dag=$(echo "$dag" | tr '[:upper:]' '[:lower:]')
    echo "$dag"
    condor_submit_dag "$dag.dag"

# Generate CSV of job activity from the DAG files and event log
generate-csv:
    uv run mldag-csv --dag-files *.dag* --metl-logs metl.log --output full_local.csv

# Generate experiment report from CSV
generate-report:
    uv run mldag-report full_local.csv

# Generate CSV and a report in a dated output directory
full-report: generate-csv
    uv run mldag-report full_local.csv --output-dir `date +"%Y-%m-%d"`

# Summarize the last N hours of job activity (e.g. just recent-summary 48)
recent-summary hours="24": generate-csv
    uv run mldag-report full_local.csv --hours {{ hours }} --output-dir recent_{{ hours }}h_summary
