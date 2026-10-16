# Laboratoire Artifactory interactif — GitHub Codespaces

## Condition impérative : ne pas engager de frais

GitHub Codespaces possède une franchise **mensuelle**, pas un hébergement gratuit illimité. Un compte personnel peut disposer de 120 heures-cœur / mois et 15 Go-mois de stockage. Avec une machine 4 cœurs, cela correspond à 30 heures de fonctionnement si la totalité de la franchise est disponible. Les quotas sont partagés avec les autres Codespaces de ce compte et le stockage continue à compter lorsque le Codespace est arrêté. **Ne pas créer de Codespace sans vérifier d'abord son solde et ses limites de facturation dans les paramètres du compte.** Configurer un budget Codespaces de 0 $ ou un plafond empêchant les dépassements (vérifier que « arrêter l'utilisation au dépassement » est activé) ; refuser toute création si ces protections ne sont pas disponibles. Le dépôt ne peut pas garantir à lui seul l'absence de facture.

La configuration utilise une machine à 4 vCPU, 16 Go RAM et le mécanisme officiel Docker-in-Docker. Aucun Artifactory n'est démarré automatiquement lors de la création du Codespace. Aucun certificat autosigné ni exposition publique ne sont nécessaires : l'URL du port 8080 est fournie en HTTPS par GitHub, avec **visibilité PRIVATE** obligatoire.

## Création après contrôle du budget

Depuis la page du dépôt GitHub : **Code → Codespaces → Create codespace on main**. Choisir **4-core** si GitHub propose ce type de machine dans la franchise. Ne pas sélectionner une machine plus grande. Vérifier l'onglet **Ports** : le port **8080** doit être **Private**, pas Public ni Organization. Si ce n'est pas le cas, le remettre en Private avant d'ouvrir Artifactory.

Dans le terminal du Codespace :

```bash
bash codespaces/lab.sh start 6.1.0
# ou, après arrêt du premier :
bash codespaces/lab.sh stop
bash codespaces/lab.sh start 6.23.42
```

Les images sont téléchargées dans le Codespace. Ouvrir ensuite l'onglet **Ports**, puis le lien HTTPS du **port 8080**. Depuis Chrome Android ou Edge Chromium, se connecter à GitHub et ouvrir le même Codespace dans le navigateur. L'URL peut changer si le Codespace est recréé.

Commandes utiles :

```bash
bash codespaces/lab.sh status
bash codespaces/lab.sh logs
bash codespaces/lab.sh stop
```

**Très important :** arrêter le Codespace depuis GitHub après chaque session, puis le **supprimer** quand il n'est plus nécessaire : arrêter interrompt le calcul, supprimer libère aussi l'espace de stockage. Les volumes Docker sont perdus lors de la suppression ; il s'agit d'un lab jetable.

## Portée actuelle

Ce Codespace interactif lance **séparément** 6.1.0 ou 6.23.42 sur Derby. Les volumes sont indépendants : il ne réalise pas les migrations entre versions. La cible **7.161.26** a bien été validée dans GitHub Actions avec une migration de Derby et un correctif JFConnect OSS ; en revanche, son démarrage autonome dans Codespaces n'a pas encore été validé et la commande refuse volontairement cette version. Ne pas confondre une fonctionnalité préparée dans le dépôt avec une validation de fonctionnement du Codespace lui-même.

Ce lab n'héberge pas Oracle 19c, ne simule pas RHEL et ne doit pas contenir de secrets de production. L'interface web n'est accessible que tant que la composition et le Codespace sont en fonctionnement.
