# PrimerSearch GUI and CLI

This repository provides two ways to run EMBOSS primersearch:

- CLI (Python script) for automation and batch runs.
- GUI (Shiny) for interactive use.

## Folder layout

- `run_primersearch.py` - CLI script
- `primersearch_gui/` - Shiny app + Docker helper
- `templates/` - starter files for config, primers, and container settings

## Quick start (Docker, no local install)

This is the easiest option for non-coders. It uses a script that builds and
runs the container for you.

1) Copy templates

```bash
cp templates/container.env primersearch_gui/container.env
cp templates/primers.tsv primers.tsv
cp templates/primersearch_config.json primersearch_config.json
```

2) Edit `primersearch_gui/container.env` with a text editor (no code):

- `GENOMES_DIR` = path to your genomes on your computer
- `GENOMES_MOUNT` = path used inside the container (default `/data/GENOMES`)
- `SHINY_MAX_UPLOAD_MB` = upload limit in MB (increase for large genomes)

If `GENOMES_DIR` is empty, you will upload the genome file in the GUI instead.

3) Run the build and start the app

```bash
bash primersearch_gui/run_container.sh
```

4) Open the app in your browser

```
http://localhost:3838
```

5) Use the GUI

- Upload `primers.tsv`
- Upload `primersearch_config.json` (optional)
- Provide the genome either by file upload or by path
  - If you mounted genomes, use `/data/GENOMES/...` in the GUI

## GUI local (Shiny)

Use this if you already have R and EMBOSS installed locally.

```bash
conda activate emboss_suite_env
R -e 'shiny::runApp("primersearch_gui")'
```

## CLI usage

Use this for pipelines or batch runs.

1) Copy templates

```bash
cp templates/primers.tsv primers.tsv
cp templates/primersearch_config.json primersearch_config.json
```

2) Edit `primersearch_config.json` and set the genome path.

3) Run:

```bash
conda activate emboss_suite_env
python3 run_primersearch.py --config primersearch_config.json
```

## Notes about data

- Local files are ignored by git (`primers.tsv`, `primersearch_config.json`,
  `primersearch_work/`, `primersearch_gui/runs/`, `primersearch_gui/container.env`).
- Use files in `templates/` as clean starting points.
