# Kernel and sysctl hardening

## Fichier modifie

- `/etc/sysctl.d/99-debian13-hardening.conf`

## Objectif

Les regles reduisent les risques lies aux redirections reseau, au source
routing, aux paquets suspects, aux liens symboliques/durs dangereux et aux
fuites d'information kernel.

## Regles principales

- `net.ipv4.ip_forward = 0`
- redirects IPv4 desactives;
- source routing desactive;
- martian packets journalises;
- SYN cookies actives;
- ASLR active;
- restrictions `kptr` et `dmesg`;
- protections hardlinks/symlinks.

IPv6 n'est pas desactive par defaut. Le profil strict peut le faire via
`DISABLE_IPV6=true`.

## Verification

```bash
sudo sysctl --system
sysctl net.ipv4.ip_forward
sysctl kernel.randomize_va_space
```

## Rollback

```bash
sudo ./harden.sh --rollback
sudo sysctl --system
```

