# debian13-web-hardening

Framework Bash interactif, modulaire et reutilisable pour durcir des serveurs
web Debian 13, avec une attention particuliere pour les VPS et instances cloud
comme Google Cloud Platform.

Le projet applique des controles de securite prudents: sauvegardes avant
modification, logs lisibles, rapport Markdown, validation des configurations
avant reload, et garde-fous anti-lockout SSH.

## Avertissement securite

Executer ce projet sur un serveur de production peut modifier SSH, nftables,
Fail2ban, sysctl, auditd, AppArmor, Nginx et les mises a jour
automatiques. Testez d'abord en environnement de preproduction ou lancez:

```bash
sudo ./harden.sh --dry-run
```

En mode `--dry-run`, aucun backup n'est cree dans `/var/backups`; le script
affiche uniquement ce qui serait fait.

## Diagnostic

Si une execution semble ne rien faire, lancez:

```bash
./harden.sh --doctor
sudo ./harden.sh --doctor
sudo bash -x ./harden.sh --help
```

`--doctor` ne modifie pas le systeme. Il verifie le script execute, les chemins
de configuration, l'appel final `main "$@"`, la syntaxe Bash et les chemins
attendus pour les logs et backups.

Pour SSH, gardez toujours une session ouverte et testez une seconde connexion
avant de fermer votre terminal courant.

## Support

- Systeme cible: Debian 13.
- Shell: Bash.
- Execution attendue: root via `sudo`.
- Backend firewall: nftables.
- Cloud awareness: detection GCP metadata server.

## Installation

```bash
git clone https://github.com/<you>/debian13-web-hardening.git
cd debian13-web-hardening
chmod +x harden.sh
sudo ./harden.sh --dry-run
sudo ./harden.sh
```

## Usage

```bash
sudo ./harden.sh
sudo ./harden.sh --menu
sudo ./harden.sh --all
sudo ./harden.sh --module ssh
sudo ./harden.sh --module firewall
sudo ./harden.sh --profile conservative
sudo ./harden.sh --profile balanced
sudo ./harden.sh --profile strict
sudo ./harden.sh --dry-run
sudo ./harden.sh --yes
sudo ./harden.sh --install-tools
sudo ./harden.sh --no-install-prereqs
sudo ./harden.sh --initial-backup-only
sudo ./harden.sh --no-initial-backup
sudo ./harden.sh --doctor
sudo ./harden.sh --rollback
sudo ./harden.sh --report-only
sudo ./harden.sh --help
```

Les options peuvent etre combinees, par exemple:

```bash
sudo ./harden.sh --profile strict --all --yes
sudo ./harden.sh --install-tools --module nginx
```

## Modules

- `ssh`: durcissement OpenSSH via `/etc/ssh/sshd_config.d/90-debian13-hardening.conf`.
- `firewall`: configuration nftables avec entree refusee par defaut.
- `fail2ban`: jail SSH systemd, avec support Nginx si present.
- `kernel`: regles sysctl reseau et kernel raisonnables.
- `services`: proposition de desactivation de services souvent inutiles.
- `updates`: unattended-upgrades, apt-listchanges et needrestart.
- `nginx`: snippets et configuration globale prudente.
- `waf`: ModSecurity + OWASP CRS en DetectionOnly par defaut.
- `auditd`: surveillance des fichiers et commandes sensibles.
- `apparmor`: installation et activation sans forcer tous les profils.
- `scanners`: lynis, rkhunter, chkrootkit, debsums, nmap local.

## Installation des outils

Au lancement des actions principales (`--menu`, `--all`, `--module`), le script
verifie et installe automatiquement les prerequis de base quand
`AUTO_INSTALL_PREREQUISITES=true`:

- `ca-certificates`
- `curl`
- `gnupg`
- `lsb-release`
- `apt-transport-https`
- `debian-archive-keyring`
- `procps`
- `iproute2`
- `sudo`

Pour installer le bundle complet d'outils de securite sans appliquer tous les
modules:

```bash
sudo ./harden.sh --install-tools
```

Ce bundle inclut notamment OpenSSH server, nftables, Fail2ban,
unattended-upgrades, auditd, AppArmor, Lynis, rkhunter, chkrootkit, debsums,
nmap, les paquets WAF disponibles et Nginx si `NGINX_INSTALL_IF_MISSING=true`.

Pour desactiver l'installation automatique des prerequis au lancement:

```bash
sudo ./harden.sh --no-install-prereqs --module ssh
```

## Logs et rapports

Les logs sont ecrits dans:

```text
/var/log/debian13-hardening/hardening-YYYYMMDD-HHMMSS.log
```

Un rapport Markdown est genere apres chaque execution:

```text
/var/log/debian13-hardening/reports/hardening-report-YYYYMMDD-HHMMSS.md
```

Le rapport contient l'hote, la version Debian, le provider cloud detecte, les
modules executes, les fichiers modifies, les backups, les regles firewall, les
services desactives, les recommandations restantes et la commande de rollback.

## Backups et rollback

Avant le lancement des modules, un backup initial des surfaces de configuration
gerees par le projet est cree automatiquement dans:

```text
/var/backups/debian13-hardening/YYYYMMDD-HHMMSS/
```

Il contient notamment les configurations SSH, nftables, Fail2ban, sysctl, APT,
Nginx, ModSecurity, auditd, AppArmor, systemd et services par defaut. Les
permissions originales sont conservees et le dossier de backup est cree en
mode `0700`, car il peut contenir des elements sensibles comme les cles host
SSH.

Ensuite, avant chaque modification ciblée, le fichier concerne est sauvegarde
dans le meme dossier de backup. Les chemins qui n'existaient pas au depart sont
enregistres afin que le rollback puisse retirer prudemment les fichiers crees
par le script.

Pour restaurer:

```bash
sudo ./harden.sh --rollback
```

Le rollback restaure les fichiers depuis le manifeste du backup choisi. Il ne
devine pas quels services doivent etre recharges apres restauration: verifiez
les services affectes et relancez-les manuellement si necessaire.

## Precautions SSH

Le module SSH:

- detecte le port SSH courant;
- detecte une session SSH active;
- cherche une cle publique valide dans `authorized_keys` pour l'utilisateur admin;
- ne desactive pas `PasswordAuthentication` si aucune cle valide n'est detectee;
- teste `sshd -t` avant reload;
- utilise `systemctl reload ssh` ou `systemctl reload sshd`;
- ne fait pas de restart brutal.

Sur GCP, OS Login et les cles SSH peuvent etre geres par la plateforme. Le
module affiche donc un avertissement et laisse l'authentification par mot de
passe intacte si aucune cle locale n'est detectee.

## Notes GCP

Le firewall configure ici est le firewall local Linux. Il ne configure pas les
regles GCP VPC. Verifiez separement que vos regles GCP autorisent les ports
SSH, HTTP et HTTPS necessaires.

Le script ne bloque pas les sorties, afin de conserver l'acces au metadata
server `169.254.169.254`, et ne desactive pas les agents Google Cloud connus.

## Profils

- `conservative`: changements prudents, moins restrictifs.
- `balanced`: profil recommande par defaut.
- `strict`: durcissement plus fort, incluant IPv6 desactive et WAF blocking si confirme.

Les profils sont dans `config/profiles/`.

## Nginx uniquement

Le projet est configure par defaut pour des serveurs Nginx uniquement:

```bash
NGINX_ONLY=true
APACHE_ENABLED=false
NGINX_INSTALL_IF_MISSING=true
```

Le module Apache reste present comme option de base de code, mais il est exclu
du menu et de `--all`. Pour l'utiliser explicitement, modifiez
`config/hardening.conf` et passez `APACHE_ENABLED=true`.

## Contribution

Avant une pull request:

```bash
find . -name '*.sh' -print0 | xargs -0 -n1 bash -n
shellcheck harden.sh lib/*.sh modules/*.sh
```

Ajoutez ou mettez a jour la documentation quand un module change un fichier
systeme, une commande de verification ou une procedure de rollback.

## Licence

MIT. Voir `LICENSE`.
