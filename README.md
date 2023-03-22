# rancid
Rancid Git for docker and kubernetes


Rancid is a "Really Awesome New Cisco ConfIg Differ" developed to maintain GIT controlled copies of router configs.

### Secret creation
- kubectl -n rancid create secret generic id-rsa --from-file=.ssh/id_rsa --dry-run=client -o yaml > kubernetes/secret.yml
