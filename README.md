# Lab gratuit — Artifactory OSS 6.1.0

Laboratoire **éphémère et public**, exécuté sur le runner standard GitHub Actions `ubuntu-24.04`, avec Docker ; un second workflow isole teste l'installation de Podman en mode rootless.

## Objectif

Tester l'image officielle **exacte** `releases-docker.jfrog.io/jfrog/artifactory-oss:6.1.0`, sans remplacement automatique de version :

1. téléchargement de l'image ;
2. lancement du conteneur sur une interface locale uniquement ;
3. réponse HTTP et version exacte via l'API ;
4. recréation du conteneur avec le même volume Docker ;
5. récupération des logs et suppression des ressources.

**La disponibilité du tag 6.1.0 n'a pas encore été vérifiée par exécution réelle.** Si son téléchargement échoue, le workflow doit échouer explicitement. Le registre historique `docker.bintray.io` est fermé.

## Lancement

Ouvrir **Actions → Artifactory 6.1.0 - lab ephemere → Run workflow**. Le workflow est également déclenché si son fichier ou le script est modifié sur `main`.

Consulter l'exécution et son artefact `artifactory-610-resultats` (conservé un jour). Le runner et le conteneur sont supprimés à la fin : **aucune interface Artifactory persistante** n'est disponible entre deux exécutions.

## Sécurité et limites

- Dépôt public : **aucune information confidentielle, aucun identifiant réel**.
- Artifactory 6.1.0 est obsolète ; aucun port n'est ouvert sur Internet.
- Compte `admin:password` utilisé uniquement pour la vérification locale sur le runner isolé.
- Ce test utilise **Ubuntu/Docker**, et ne valide **pas** RHEL 9/Podman, Oracle/PostgreSQL ou une migration 6.x → 7.x.
- Le test du volume vérifie la présence d'un marqueur : il ne remplace pas une vraie recette de persistance applicative.
- Runner standard dans un dépôt public : GitHub documente une utilisation gratuite. Aucun larger runner payant.

## Journaux

`resultat.txt` : bilan général ;
`docker-pull.log` : succès/échec du téléchargement ;
`image-digest.txt` : identifiant de l'image ;
`artifactory-container.log` : logs si le conteneur a démarré ;
`version.json` : version renvoyée par l'API si disponible.

Le script est conçu pour échouer sans masquer la cause et pour nettoyer conteneur et volume après exécution.

## Préparation de Podman sur Ubuntu 24.04

Workflow indépendant : **Podman - installation et test Ubuntu 24.04** (`.github/workflows/podman-install.yml`).

Sur le runner standard éphémère, il vérifie la version et l'installation de Podman (paquets Ubuntu si nécessaire), inspecte sa configuration rootless et exécute un petit conteneur Alpine avec réseau désactivé. Il ne déploie pas encore Artifactory et ne modifie pas le workflow Docker existant.

Déclenchement automatique lors de l'ajout du workflow à `main`, ou manuel via **Actions → Podman - installation et test Ubuntu 24.04 → Run workflow**. Les commandes et résultats apparaissent dans les journaux GitHub Actions. Après le job, la VM est supprimée : Podman devra être préparé lors de chaque nouvelle exécution.

Documentation : [installation Podman](https://podman.io/docs/installation), [runners GitHub](https://docs.github.com/en/actions/reference/runners/github-hosted-runners).
