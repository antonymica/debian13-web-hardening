# Initial configuration backup

## Objectif

Avant d'executer un module de hardening, le script cree un snapshot initial des
surfaces de configuration qu'il peut modifier ou inspecter. Ce snapshot donne
un point de retour clair vers l'etat du serveur avant hardening.

## Emplacement

```text
/var/backups/debian13-hardening/YYYYMMDD-HHMMSS/initial-config/
```

Le dossier est cree avec des permissions restrictives (`0700`) car il peut
contenir des donnees sensibles, notamment dans `/etc/ssh`.

## Chemins sauvegardes par defaut

- `/etc/ssh`
- `/etc/nftables.conf`
- `/etc/fail2ban`
- `/etc/sysctl.conf`
- `/etc/sysctl.d`
- `/etc/apt/apt.conf.d`
- `/etc/apt/sources.list`
- `/etc/apt/sources.list.d`
- `/etc/nginx`
- `/etc/modsecurity`
- `/etc/audit`
- `/etc/auditd.conf`
- `/etc/apparmor`
- `/etc/apparmor.d`
- `/etc/default`
- `/etc/systemd/system`
- `/etc/needrestart`
- `/etc/rkhunter.conf`

La liste est configurable dans `config/hardening.conf` via
`INITIAL_BACKUP_PATHS`.

## Chemins absents

Si un chemin n'existe pas avant le hardening, il est note dans le manifeste. En
cas de rollback, le script sait alors qu'un fichier cree ensuite peut etre
retire. Les dossiers sont supprimes uniquement s'ils sont vides.

## Commandes utiles

Creer uniquement le backup initial:

```bash
sudo ./harden.sh --initial-backup-only
```

Simuler sans ecrire dans `/var/backups`:

```bash
sudo ./harden.sh --dry-run --initial-backup-only
```

Desactiver le backup initial pour une execution precise:

```bash
sudo ./harden.sh --no-initial-backup --module nginx
```

Cette derniere option est deconseillee sur un premier lancement serveur.
