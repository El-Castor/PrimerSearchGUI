# PrimerSearch GUI + CLI

Ce depot propose deux facons d'utiliser `primersearch` (EMBOSS) :

- **CLI (script Python)** : ideal pour les pipelines, l'automatisation, ou les serveurs.
- **GUI (Shiny)** : ideal pour une utilisation interactive et rapide.

## Choisir la bonne option

- **CLI** : quand vous avez plusieurs jeux de primers, des runs batch, ou un HPC.
- **GUI** : quand vous voulez tester rapidement quelques primers sans ligne de commande.
- **GUI via Docker** : quand vous ne voulez pas installer R/EMBOSS localement.

## CLI (script Python)

1) Preparer les fichiers (exemples fournis) :

```bash
cp primers.example.tsv primers.tsv
cp primersearch_config.example.json primersearch_config.json
```

2) Editer `primersearch_config.json` avec vos chemins :
- `primer_table` : chemin vers votre TSV
- `genome` : chemin vers le genome (local)

3) Executer :

```bash
conda activate emboss_suite_env
python3 run_primersearch.py --config primersearch_config.json
```

## GUI locale (Shiny)

```bash
conda activate emboss_suite_env
R -e 'shiny::runApp("primersearch_gui")'
```

## GUI via Docker (recommande pour non-install)

La facon la plus simple est d'utiliser le script :

```bash
bash primersearch_gui/run_container.sh
```

Configuration (sans code) :
- Editer `primersearch_gui/container.env.example`
- Copier en `primersearch_gui/container.env`

```bash
cp primersearch_gui/container.env.example primersearch_gui/container.env
```

Deux modes pour le genome :

- **Upload** dans l'interface (plus simple, mais taille limitee).
- **Chemin monte** via Docker (recommande pour gros genomes) : utilisez un chemin
  `/data/GENOMES/...` dans la GUI si vous montez `GENOMES`.

## Notes sur les donnees

- Les fichiers locaux (`primersearch_config.json`, `primers.tsv`, runs, etc.) ne sont pas versionnes.
- Utilisez les fichiers `*.example.*` comme modeles.
