# GCP notes

## Detection

Le script detecte GCP avec le metadata server:

```bash
curl -fsS --max-time 1 -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name
```

## Points importants

- Le firewall local nftables ne remplace pas les regles GCP VPC.
- OS Login peut gerer les utilisateurs et cles SSH.
- Les agents Google Cloud ne doivent pas etre desactives.
- Le metadata server `169.254.169.254` doit rester accessible depuis l'instance.

## Verification

```bash
curl -H "Metadata-Flavor: Google" \
  http://metadata.google.internal/computeMetadata/v1/instance/name
systemctl list-units 'google-*'
```

## Recommandations

Verifiez les regles GCP VPC pour SSH, HTTP et HTTPS avant d'appliquer le module
firewall. Pour les environnements avec OS Login, validez l'acces SSH avec une
nouvelle session avant de fermer la session existante.

