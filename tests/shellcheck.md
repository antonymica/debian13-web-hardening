# ShellCheck

## Validation syntaxique

```bash
find . -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

## Analyse statique

```bash
shellcheck harden.sh lib/*.sh modules/*.sh
```

## Notes

- Les scripts sont concus pour Bash avec `set -Eeuo pipefail`.
- Les fichiers `config/*.conf` sont des fragments Bash sources par `harden.sh`.
- Lancez ShellCheck depuis la racine du projet.

