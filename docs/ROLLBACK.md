# Rollback

## Principe

Chaque module sauvegarde les fichiers existants avant modification dans:

```text
/var/backups/debian13-hardening/YYYYMMDD-HHMMSS/
```

Le fichier `backup-manifest.txt` contient les correspondances:

```text
/chemin/original|/chemin/backup
```

Les chemins absents au moment du backup initial sont marques dans le manifeste.
Pendant un rollback, le script retire seulement les fichiers ou liens crees
ensuite. Pour les dossiers, il utilise uniquement `rmdir`; un dossier non vide
est laisse en place avec un avertissement.

## Restaurer

```bash
sudo ./harden.sh --rollback
```

Selectionnez le backup a restaurer, puis confirmez.

Le manifeste est restaure en ordre inverse pour permettre de retirer les
fichiers crees avant d'essayer de retirer les dossiers initialement absents.

## Apres restauration

Le rollback restaure les fichiers, mais ne sait pas toujours quel service doit
etre recharge. Selon les fichiers restaures, verifiez:

```bash
sudo sshd -t && sudo systemctl reload ssh
sudo nft -c -f /etc/nftables.conf && sudo nft -f /etc/nftables.conf
sudo nginx -t && sudo systemctl reload nginx
sudo sysctl --system
sudo fail2ban-client -t && sudo systemctl restart fail2ban
```

## Bonnes pratiques

Gardez une session SSH ouverte pendant le rollback et testez les services
critiques avant de considerer l'operation terminee.
