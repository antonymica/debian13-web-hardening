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

## Restaurer

```bash
sudo ./harden.sh --rollback
```

Selectionnez le backup a restaurer, puis confirmez.

## Apres restauration

Le rollback restaure les fichiers, mais ne sait pas toujours quel service doit
etre recharge. Selon les fichiers restaures, verifiez:

```bash
sudo sshd -t && sudo systemctl reload ssh
sudo nft -c -f /etc/nftables.conf && sudo nft -f /etc/nftables.conf
sudo nginx -t && sudo systemctl reload nginx
sudo apachectl configtest && sudo systemctl reload apache2
sudo sysctl --system
sudo fail2ban-client -t && sudo systemctl restart fail2ban
```

## Bonnes pratiques

Gardez une session SSH ouverte pendant le rollback et testez les services
critiques avant de considerer l'operation terminee.

