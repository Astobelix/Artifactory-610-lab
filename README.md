# Lab gratuit — Artifactory OSS 6.1.0

Laboratoire **éphémère et public**, exécuté sur le runner standard GitHub Actions `ubuntu-24.04`, avec Docker ; un second workflow isole teste l'installation de Podman en mode rootless.

## Objectif

Tester l'image officielle **exacte** `releases-docker.jfrog.io/jfrog/artifactory-oss:6.1.0`, sans remplacement automatique de version :

1. téléchargement de l'image ;
2. lancement du conteneur sur une interface locale uniquement ;
3. réponse HTTP et version exacte via l'API ;
4. recréation du conteneur avec le même volume Docker ;
5. récupération des logs et suppression des ressources.

Le premier workflow Docker a terminé avec succès d'après GitHub Actions : son script vérifie l'image et la version exacte 6.1.0. Les journaux du job permettent d'en examiner le détail. Le registre historique `docker.bintray.io` est fermé.

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

## Artifactory OSS 6.1.0 avec Podman rootless (troisième workflow)

Workflow autonome : `.github/workflows/artifactory-610-podman.yml`, script `scripts/ci_podman_lab.sh`.

- Prépare Podman sur un **nouveau runner standard Ubuntu 24.04**, car les runners sont éphémères.
- Vérifie explicitement que Podman fonctionne en **rootless**, puis télécharge exactement l'image JFrog OSS `6.1.0`.
- Démarre Artifactory avec un **volume nommé Podman** et publie l'interface seulement sur `127.0.0.1:8081` du runner.
- Vérifie la réponse HTTP et la version via l'API au premier démarrage, puis **recrée** le conteneur et revérifie le démarrage, la version et un marqueur de persistance.
- Conserve pendant 1 jour les journaux d'exécution GitHub dans l'artefact `artifactory-610-podman-resultats` ; supprime conteneur et volume en fin de test.

Le workflow se déclenche sur `main` lors de l'ajout ou de la modification de ces deux fichiers, ou manuellement sous **Actions → Artifactory 6.1.0 - test Podman rootless → Run workflow**.

**Portée :** test temporaire Podman sur Ubuntu 24.04, sans frais de VM persistante pour un dépôt public utilisant un runner standard. Il **ne prouve pas** la compatibilité RHEL 9/SELinux, ni la fiabilité complète d'une migration ou d'une sauvegarde Artifactory. L'ancienne version n'est pas exposée sur Internet. Les deux précédents workflows restent inchangés.
