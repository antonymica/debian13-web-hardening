# debian13-web-hardening

Framework Bash interactif, modulaire et reutilisable pour durcir des serveurs
web Debian 13, avec une attention particuliere pour les VPS et instances cloud
comme Google Cloud Platform.

Le projet applique des controles de securite prudents: sauvegardes avant
modification, logs lisibles, rapport Markdown, validation des configurations
avant reload, et garde-fous anti-lockout SSH.

## Avertissement securite

Executer ce projet sur un serveur de production peut modifier SSH, nftables,
Fail2ban, sysctl, auditd, AppArmor, Nginx, Apache et les mises a jour
automatiques. Testez d'abord en environnement de preproduction ou lancez:

```bash
sudo ./harden.sh --dry-run
```

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
sudo ./harden.sh --rollback
sudo ./harden.sh --report-only
sudo ./harden.sh --help
```

Les options peuvent etre combinees, par exemple:

```bash
sudo ./harden.sh --profile strict --all --yes
```

## Modules

- `ssh`: durcissement OpenSSH via `/etc/ssh/sshd_config.d/90-debian13-hardening.conf`.
- `firewall`: configuration nftables avec entree refusee par defaut.
- `fail2ban`: jail SSH systemd, avec support Nginx/Apache si presents.
- `kernel`: regles sysctl reseau et kernel raisonnables.
- `services`: proposition de desactivation de services souvent inutiles.
- `updates`: unattended-upgrades, apt-listchanges et needrestart.
- `nginx`: snippets et configuration globale prudente.
- `apache`: headers, ServerTokens, protections de fichiers sensibles.
- `waf`: ModSecurity + OWASP CRS en DetectionOnly par defaut.
- `auditd`: surveillance des fichiers et commandes sensibles.
- `apparmor`: installation et activation sans forcer tous les profils.
- `scanners`: lynis, rkhunter, chkrootkit, debsums, nmap local.

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

Avant chaque modification, les fichiers existants sont sauvegardes dans:

```text
/var/backups/debian13-hardening/YYYYMMDD-HHMMSS/
```

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

