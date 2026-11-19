# BHK Diagnostic Automobile

## Démarrage du backend

Depuis `backend`, appliquez les migrations, créez un compte administrateur et
lancez Django :

```powershell
python manage.py migrate
python manage.py createsuperuser
python manage.py runserver 0.0.0.0:8000
```

Installez d’abord Django avec `pip install -r requirements.txt`.
Le compte administrateur se connecte avec son nom d’utilisateur comme CIN.
Les comptes experts sont créés depuis l’écran **Experts** après connexion
administrateur. Chaque expert commence sans permission métier ; l’administrateur
active individuellement ses accès.

## Adresse de l’API Flutter

Par défaut, l’application Flutter cible ce PC via (`127.0.0.1:8000/api/`).
Pour une autre plateforme, indiquez l’URL complète de l’API au lancement :

```powershell
flutter run --dart-define=API_BASE_URL=https://votre-serveur.example/api/
```

En local, remplacez l’adresse par celle de votre ordinateur (par exemple
`http://192.168.1.20:8000/api/` sur un appareil physique). Le trafic HTTP est
activé uniquement dans la configuration Android de développement. Utilisez
HTTPS pour tout déploiement et configurez `DJANGO_SECRET_KEY`,
`DJANGO_DEBUG=False` et `DJANGO_ALLOWED_HOSTS` selon votre environnement.
Pour l’application web, renseignez aussi les origines exactes autorisées dans
`DJANGO_CORS_ALLOWED_ORIGINS` (séparées par des virgules).

## Fonctionnalités disponibles

- Authentification CIN/mot de passe et permissions vérifiées par l’API.
- Création et désactivation de comptes experts, et réglage individuel de leurs
  permissions.
- Inspections avec référence `BHK-AAAA-NNNNNN`, propriétaire, date, fiche
  véhicule, schéma interactif de carrosserie, contrôles mécaniques, état des
  consommables et ajout de photos.
- Consultation de l’historique autorisé et clôture d’une inspection.
- Paramètres centralisés réservés à l’administration : choix français/arabe
  appliqué à toute l’interface avec mise en page RTL en arabe, informations et
  logo de l’entreprise, personnalisation du PDF et libellés de conclusion. Le
  logo accepté est au format PNG ou JPEG et limité à 1,5 Mo ; la version
  affichée correspond à la version déclarée dans `pubspec.yaml`.

Les modules financiers, ventes, facturation, sauvegardes et journaux d’activité
ne sont pas encore implémentés.
