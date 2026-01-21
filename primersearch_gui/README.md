# Primersearch GUI (Shiny)

This folder contains a Shiny app that runs the existing `run_primersearch.py`
script via a simple GUI.

## Requirements

- R with the `shiny` and `jsonlite` packages installed.
- `primersearch` available in your PATH (for example by activating your conda
  environment before launching the app).

## Run

From the project root:

```bash
conda activate emboss_suite_env
R -e 'shiny::runApp("primersearch_gui")'
```

## Notes

- Each run creates a folder under `primersearch_gui/runs/` with the generated
  config, stdout/stderr logs, and the primersearch output.
- You can load an optional config JSON, then override values in the GUI.
- Genome can be provided either by file upload or by path.

## Container (Docker)

Build the image from the project root:

```bash
docker build -f primersearch_gui/Dockerfile -t primersearch-gui .
```

Run it:

```bash
docker run --rm -p 3838:3838 \
  -v "/path/to/BIO-INFO:/data" \
  primersearch-gui
```

Then open `http://localhost:3838` in your browser.

Notes:
- The primers TSV can be uploaded directly in the app.
- The genome can be uploaded, or provided as a path inside the container. With
  the example mount above, use paths like `/data/GENOMES/...` in the GUI.
- Large genome uploads may require a higher Shiny upload limit. You can set it
  with `-e SHINY_MAX_UPLOAD_MB=2048` on `docker run` (default is 1024 MB).

### Recommended: one-step build + run script

To avoid image visibility issues between builders/contexts, use:

```bash
bash primersearch_gui/run_container.sh
```

You can configure it by copying and editing
`primersearch_gui/container.env.example`. The script reads
`primersearch_gui/container.env` automatically.

Options (examples):

```bash
# Mount genomes so you can use /data/GENOMES/... in the GUI
GENOMES_DIR="/path/to/BIO-INFO/GENOMES" \
bash primersearch_gui/run_container.sh

# Keep the original /Users/... path from your config
GENOMES_DIR="/path/to/BIO-INFO/GENOMES" \
GENOMES_MOUNT="/path/to/BIO-INFO/GENOMES" \
bash primersearch_gui/run_container.sh

# Increase upload limit (MB)
SHINY_MAX_UPLOAD_MB=4096 \
bash primersearch_gui/run_container.sh
```

Apple Silicon tip:
- The Dockerfile defaults to `linux/amd64` because the base image does not ship
  arm64 builds. This uses emulation on Apple Silicon.
- If you still see platform errors, build and run explicitly with amd64:

```bash
docker buildx build --platform=linux/amd64 -f primersearch_gui/Dockerfile -t primersearch-gui --load .
docker run --rm --platform=linux/amd64 -p 3838:3838 \
  -v "/path/to/BIO-INFO:/data" \
  primersearch-gui
```
