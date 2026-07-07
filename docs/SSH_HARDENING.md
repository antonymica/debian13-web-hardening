# SSH hardening

## Fichiers modifies

- `/etc/ssh/sshd_config` est sauvegarde.
- `/etc/ssh/sshd_config.d/90-debian13-hardening.conf` est cree ou remplace.

## Controles appliques

- `PermitRootLogin no`
- `Port <current>` ou `Port <configured>` selon la configuration
- `PubkeyAuthentication yes`
- `PasswordAuthentication no` seulement si une cle publique valide est detectee
- `KbdInteractiveAuthentication no`
- `ChallengeResponseAuthentication no`
- `X11Forwarding no`
- `AllowTcpForwarding` configurable
- `PermitEmptyPasswords no`
- `MaxAuthTries 3`
- `LoginGraceTime 30`
- keepalive client
- `LogLevel VERBOSE`

`Protocol 2` n'est pas ecrit car les versions modernes d'OpenSSH ne supportent
que SSH protocol 2 et cette directive peut etre absente ou obsolette.

## Garde-fous anti-lockout

Le module detecte le port SSH courant, une session SSH active, l'utilisateur
admin et la presence d'une cle dans `authorized_keys`. Si aucune cle valide
n'est detectee, il laisse l'authentification par mot de passe inchangee.

## Changer le port SSH

Par defaut:

```bash
SSH_PORT=auto
SSH_KEEP_CURRENT_PORT_ON_CHANGE=true
```

Pour ajouter un nouveau port sans couper l'ancien:

```bash
sudo ./harden.sh --ssh-port 2222 --module ssh
sudo ./harden.sh --ssh-port 2222 --module firewall
```

Le service SSH ecoutera alors sur le port actuel et sur `2222`. Testez:

```bash
ssh -p 2222 user@server
```

Apres validation, retirez l'ancien port:

```bash
sudo ./harden.sh --ssh-port 2222 --replace-ssh-port --module ssh
sudo ./harden.sh --ssh-port 2222 --replace-ssh-port --module firewall
```

Sur GCP, ajoutez aussi une regle VPC autorisant le nouveau port avant de fermer
la session existante.

La configuration est testee avec:

```bash
sshd -t
```

Le service est recharge avec:

```bash
systemctl reload ssh
```

ou:

```bash
systemctl reload sshd
```

## Risque operationnel

Le risque principal est la perte d'acces SSH. Gardez une session ouverte et
testez une nouvelle connexion avant de fermer la session initiale.

## Rollback

```bash
sudo ./harden.sh --rollback
sshd -t
sudo systemctl reload ssh
```
