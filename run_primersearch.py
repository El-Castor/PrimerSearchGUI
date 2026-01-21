#!/usr/bin/env python3
"""
Script pour lancer facilement le programme `primersearch` de la suite EMBOSS.

Ce script lit un fichier de configuration (au format JSON) décrivant :

* le chemin vers un fichier tabulé contenant des paires de primers (au moins
  trois colonnes : un identifiant de paire, la séquence du primer sens
  (forward) et la séquence du primer antisens (reverse)) ;
* le chemin vers le génome (ou jeu de séquences) contre lequel les primers
  doivent être testés ;
* la tolérance de mismatch en pourcentage ;
* le nom du fichier de sortie souhaité ;
* toute option supplémentaire supportée par primersearch (par exemple les
  paramètres associés à l’argument `-seqall` comme `sbegin`, `send`, etc.).

Le script prépare automatiquement un fichier d’entrée compatible avec
`primersearch` à partir du tableau tabulé et construit la ligne de commande
appropriée. Il appelle ensuite `primersearch` via `subprocess.run`.  Les
arguments non fournis dans le fichier de configuration prennent leur valeur par
défaut telle qu’indiquée dans la documentation officielle de EMBOSS
primersearch【348991980705319†L60-L132】.

Exemple de fichier de configuration (`primersearch_config.json`) :

```
{
  "primer_table": "primers.tsv",        // fichier TSV contenant au moins les colonnes: name, forward, reverse
  "genome": "genome.fasta",            // séquence(s) cible(s) au format fasta ou tout format reconnu par EMBOSS
  "mismatchpercent": 0,                 // pourcentage de mismatch autorisé (0 par défaut)
  "output": "resultats.primersearch",  // fichier de sortie; par défaut <genome>.primersearch
  // options associées à -seqall (toutes facultatives). Les valeurs nulles ou absentes ne sont pas ajoutées à la ligne de commande.
  "sbegin": null,      // début de la séquence à utiliser (0 par défaut【348991980705319†L139-L140】)
  "send": null,        // fin de la séquence à utiliser (0 = fin, valeur par défaut【348991980705319†L139-L142】)
  "sreverse": false,   // recherche sur la séquence inversée (False par défaut【348991980705319†L142-L144】)
  "sask": false,       // demander l’intervalle (False par défaut【348991980705319†L144-L145】)
  "snucleotide": false,// forcer l’interprétation comme séquence nucléotidique (False par défaut【348991980705319†L146-L148】)
  "sprotein": false,   // séquence protéique (False par défaut【348991980705319†L148-L149】)
  "slower": false,     // convertir en minuscules (False par défaut【348991980705319†L150-L152】)
  "supper": false,     // convertir en majuscules (False par défaut【348991980705319†L150-L152】)
  "scircular": false,  // séquence circulaire (False par défaut【348991980705319†L154-L155】)
  "squick": false,     // lecture rapide id+séquence seulement (False par défaut【348991980705319†L156-L157】)
  "sformat": null,     // format d’entrée (laisser null pour automatique【348991980705319†L158-L159】)
  "ioffset": null,     // décalage de position (0 par défaut【348991980705319†L162-L163】)
  "sdbname": null,     // nom de base de données (optionnel【348991980705319†L164-L165】)
  "sid": null,         // identifiant d’entrée (optionnel【348991980705319†L166-L167】)
  // d’autres options générales de primersearch peuvent également être fournies, par exemple "auto", "stdout", "filter", "verbose" etc.
  "auto": true,        // désactive les invites interactives. Recommandé pour les scripts (False par défaut【348991980705319†L103-L104】)
  "verbose": false     // afficher les options de la ligne de commande (False par défaut【348991980705319†L109-L112】)
}
```

Veillez à activer l’environnement conda « emboss_suite_env » avant de lancer ce
script pour que `primersearch` soit dans le PATH :

```bash
conda activate emboss_suite_env
python3 run_primersearch.py --config primersearch_config.json
```

"""

import argparse
import csv
import itertools
import json
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    """Analyse les arguments de la ligne de commande."""
    parser = argparse.ArgumentParser(
        description=(
            "Prépare et exécute l'outil EMBOSS primersearch en utilisant un "
            "fichier de configuration JSON."
        )
    )
    parser.add_argument(
        "--config",
        required=True,
        help="Chemin vers le fichier de configuration JSON décrivant les paramètres.",
    )
    parser.add_argument(
        "--workdir",
        default="./primersearch_work",
        help=(
            "Dossier de travail où seront générés les fichiers intermédiaires. "
            "Par défaut: ./primersearch_work"
        ),
    )
    return parser.parse_args()


def load_config(config_path: str) -> dict:
    """Charge le fichier de configuration JSON et retourne un dictionnaire."""
    try:
        with open(config_path, "r", encoding="utf-8") as fh:
            config = json.load(fh)
    except FileNotFoundError:
        sys.exit(f"Erreur : fichier de configuration '{config_path}' introuvable.")
    except json.JSONDecodeError as e:
        sys.exit(f"Erreur de format JSON dans '{config_path}': {e}")
    return config


def prepare_primersearch_input(primer_table: str, output_dir: Path) -> Path:
    """
    Construit le fichier d'entrée attendu par primersearch à partir du fichier
    tabulé des primers. Renvoie le chemin du fichier généré.

    Le fichier d'entrée doit contenir une ligne par paire de primers :

    <Nom> <Séquence primer 1> <Séquence primer 2>

    où les champs sont séparés par une tabulation. Les colonnes
    attendues dans le fichier tabulé sont 'name', 'forward' et 'reverse'. Si
    l'utilisateur utilise d'autres noms de colonnes, ils peuvent être modifiés
    ici.
    """
    primer_table_path = Path(primer_table)
    if not primer_table_path.exists():
        sys.exit(f"Erreur : fichier de primers '{primer_table}' introuvable.")

    primers_input_path = output_dir / "primers_for_primersearch.txt"

    with open(primer_table_path, "r", encoding="utf-8") as tsv_in, open(
        primers_input_path, "w", encoding="utf-8"
    ) as out_fh:
        # Skip leading blank lines so the header is detected correctly.
        lines_iter = iter(tsv_in)
        for first_line in lines_iter:
            if first_line.strip():
                break
        else:
            sys.exit(
                "Erreur : le fichier de primers semble vide ou mal formaté (pas de ligne d'en-tête)."
            )
        reader = csv.DictReader(
            itertools.chain([first_line], lines_iter), delimiter="\t"
        )
        if reader.fieldnames is None:
            sys.exit(
                "Erreur : le fichier de primers semble vide ou mal formaté (pas de ligne d'en-tête)."
            )
        lower_names = [name.lower() for name in reader.fieldnames]
        required_cols = {"name", "forward", "reverse"}
        if not required_cols.issubset(set(lower_names)):
            sys.exit(
                "Erreur : le fichier des primers doit contenir les colonnes 'name', 'forward' et 'reverse'."
            )
        for row in reader:
            # recherche sans tenir compte de la casse
            def get_value(keys):
                for key in keys:
                    if key in row and row[key]:
                        return row[key]
                return None

            name = get_value(["name", "Name", "Primer name", "primer name"])
            forward = get_value([
                "forward",
                "Forward",
                "primer_forward",
                "primer forward",
            ])
            reverse = get_value([
                "reverse",
                "Reverse",
                "primer_reverse",
                "primer reverse",
            ])
            if not (name and forward and reverse):
                # ligne incomplète : on ignore ou on signale.
                print(
                    f"Avertissement : ligne incomplète dans le fichier des primers: {row}",
                    file=sys.stderr,
                )
                continue
            # Écriture du fichier d'entrée
            out_fh.write(f"{name}\t{forward}\t{reverse}\n")
    return primers_input_path


def build_primersearch_command(config: dict, primers_file: Path, output_dir: Path) -> list:
    """
    Construit la liste des arguments pour appeler primersearch en fonction de
    la configuration et du fichier des primers généré. Le premier élément de la
    liste est le binaire à exécuter (ici 'primersearch').
    """
    cmd = ["primersearch"]

    # Paramètre obligatoire : séquence(s) à rechercher
    genome = config.get("genome")
    if not genome:
        sys.exit(
            "Erreur : le chemin vers le génome (champ 'genome') est requis dans la configuration."
        )
    if not Path(genome).exists():
        sys.exit(f"Erreur : fichier génome '{genome}' introuvable.")
    cmd.extend(["-seqall", genome])

    # Fichier des primers
    cmd.extend(["-infile", str(primers_file)])

    # Mismatch percent
    mismatch = config.get("mismatchpercent")
    if mismatch is not None:
        try:
            mismatch_val = int(mismatch)
            if mismatch_val < 0:
                raise ValueError
            cmd.extend(["-mismatchpercent", str(mismatch_val)])
        except (TypeError, ValueError):
            sys.exit(
                f"Erreur : 'mismatchpercent' doit être un entier positif (valeur trouvée : {mismatch})."
            )

    # Fichier de sortie
    output_file = config.get("output")
    if not output_file:
        # valeur par défaut selon EMBOSS : <genome>.primersearch
        output_file = str(Path(genome).stem) + ".primersearch"
    # s'assurer que le chemin est dans output_dir si l'utilisateur ne fournit pas de chemin absolu
    output_path = Path(output_file)
    if not output_path.is_absolute():
        output_path = output_dir / output_path
    cmd.extend(["-outfile", str(output_path)])

    # Ajout des options facultatives
    # Map des clés de configuration vers le nom des arguments primersearch.
    optional_map = {
        "sbegin": "-sbegin1",
        "send": "-send1",
        "sreverse": "-sreverse1",
        "sask": "-sask1",
        "snucleotide": "-snucleotide1",
        "sprotein": "-sprotein1",
        "slower": "-slower1",
        "supper": "-supper1",
        "scircular": "-scircular1",
        "squick": "-squick1",
        "sformat": "-sformat1",
        "ioffset": "-ioffset1",
        "sdbname": "-sdbname1",
        "sid": "-sid1",
    }
    for key, arg_name in optional_map.items():
        if key in config and config[key] not in (None, "", False):
            value = config[key]
            # certains arguments sont booléens et n'ont pas de valeur
            if isinstance(value, bool):
                if value:
                    cmd.append(arg_name)
            else:
                cmd.extend([arg_name, str(value)])

    # Options générales (flags sans valeur)
    general_flags = [
        "auto",
        "stdout",
        "filter",
        "options",
        "debug",
        "verbose",
        "warning",
        "error",
        "fatal",
        "die",
        "version",
    ]
    for flag in general_flags:
        val = config.get(flag)
        if val:
            cmd.append("-" + flag)

    return cmd


def run_primersearch(command: list) -> None:
    """
    Exécute la commande primersearch et gère les erreurs éventuelles. Les
    messages d'erreur et d'avertissement sont relayés à l'utilisateur.
    """
    print("Exécution de la commande :", " ".join(command))
    try:
        result = subprocess.run(command, check=False, capture_output=True, text=True)
    except FileNotFoundError:
        sys.exit(
            "Erreur : le programme 'primersearch' n'est pas trouvé dans le PATH.\n"
            "Vérifiez que l'environnement conda 'emboss_suite_env' est activé."
        )
    # Impression de la sortie standard et d'erreur pour information
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    if result.returncode != 0:
        print(
            f"Attention : primersearch s'est terminé avec un code {result.returncode}",
            file=sys.stderr,
        )


def main() -> None:
    args = parse_args()
    config = load_config(args.config)
    workdir = Path(args.workdir)
    workdir.mkdir(parents=True, exist_ok=True)

    # Préparer le fichier d'entrée pour primersearch
    primers_file = prepare_primersearch_input(config.get("primer_table"), workdir)

    # Construire la commande
    command = build_primersearch_command(config, primers_file, workdir)

    # Lancer primersearch
    run_primersearch(command)


if __name__ == "__main__":
    main()
