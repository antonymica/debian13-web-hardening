# Firewall hardening

## Backend

Le module utilise nftables et sauvegarde `/etc/nftables.conf` avant
modification.

## Regles appliquees

- loopback autorise;
- connexions etablies et relatives autorisees;
- paquets invalides rejetes;
- ICMP et ICMPv6 autorises;
- port SSH detecte autorise;
- ports TCP 80 et 443 autorises en mode web;
- trafic sortant autorise;
- entree refusee par defaut.

Le trafic sortant reste autorise pour eviter de bloquer les mises a jour, DNS,
monitoring et le metadata server GCP `169.254.169.254`.

## Validation

Avant application:

```bash
nft -c -f /tmp/generated-file
```

Apres application:

```bash
sudo nft list ruleset
sudo systemctl status nftables
```

## GCP

Ce module configure seulement le firewall local. Les regles GCP VPC doivent
etre configurees separement.

## Risque operationnel

Une mauvaise regle firewall peut couper l'acces distant. Le module conserve le
port SSH courant, mais verifiez toujours les regles cloud et ouvrez une seconde
session SSH avant de fermer la premiere.

## Rollback

```bash
sudo ./harden.sh --rollback
sudo nft -f /etc/nftables.conf
```

