# Complexe Scolaire SAINT JEAN PAUL II

Application Android Parent / Enseignant / Cantine, interface Super Admin web et Supabase.

## Structure
- `app/` : application Android Kotlin / Jetpack Compose.
- `admin/index.html` : interface Super Admin Direction.
- `index.html` : copie de l'interface web, à publier sur GitHub Pages.
- `supabase/CONNECT_TEST_SCHEMA_COMPLET.sql` : schéma Supabase complet à exécuter dans SQL Editor.
- `.github/workflows/android.yml` : compilation automatique de l'APK Debug.

## Cycles et classes
- Primaire : CI1, CI2, CP1, CP2, CE1, CE2, CM1, CM2.
- Collège : 6ième, 5ième, 4ième, 3ième.

## Inscription
L'inscription d'un élève se fait à partir d'un parent déjà créé. Le parent reçoit un code automatique. Le lien avec chaque enfant précise le type de responsable : Père, Mère, Tante, Oncle ou Tuteur. Les enseignants et le personnel de cantine disposent aussi d'un code automatique.

## Frais de scolarité
La Direction définit le montant par classe et enregistre les paiements des élèves par tranches (jusqu'à 15). Le rapport admin affiche montant dû, montant payé, reste et taux de paiement, avec filtre de classe et seuil de paiement. Le parent voit le récapitulatif de chaque enfant.

## Cantine
Le personnel se connecte avec son code. Une seule publication quotidienne est permise pour toute l'équipe : nom du menu et deux liens publics de photos. Les autres membres peuvent consulter le menu. Les parents et l'admin voient les menus et les photos. Pour les photos, téléverser les images dans le bucket Storage public `sjp-canteen` puis renseigner leurs URL publiques dans l'espace cantine.

Le script tente d'activer Supabase Cron pour supprimer chaque dimanche à 00:00 UTC les lignes de menus antérieures et les objets photo du bucket `sjp-canteen`. Si le projet Supabase ne permet pas l'activation de `pg_cron`, activer l'extension depuis Database > Extensions puis programmer `select public.purge_old_canteen_meals();` avec l'expression cron `0 0 * * 0`.

## Supabase
Le projet Supabase et sa clé Publishable d'origine sont conservés. La clé `service_role` n'est jamais intégrée au dépôt.

- **Projet/base existante** : exécuter `supabase/SAINT_JEAN_PAUL_II_MIGRATION.sql`. Cette migration ajoute les modules et les classes sans réinitialiser les tables scolaires existantes. Faire une sauvegarde préalable.
- **Base entièrement neuve** : exécuter `supabase/CONNECT_TEST_SCHEMA_COMPLET.sql`. Attention : ce script complet reprend le comportement du projet source et commence par supprimer/recréer les tables du projet. Ne pas l'exécuter sur une base contenant des données à conserver.

Créer ensuite le compte e-mail + mot de passe de la Direction dans Supabase Auth. Se connecter depuis l'interface Super Admin et initialiser le compte Direction.

## Publication web
Publier `index.html` et `connect_test_logo.png` à la racine du dépôt GitHub, puis activer GitHub Pages.

## Compilation Android
Le workflow GitHub installe Java 17, Gradle 8.9 et Android SDK 35, puis exécute `gradle assembleDebug`. Après push sur la branche `main`, récupérer l'APK dans les artefacts de l'exécution GitHub Actions.

## Notes de déploiement
- Le script SQL est destiné à une nouvelle base : il contient les opérations de remise à zéro du schéma du projet de démonstration.
- L'espace cantine accepte les URL publiques des deux photos ; le téléversement des fichiers dans Storage doit être fait dans le bucket indiqué.
- Tester le script SQL sur un projet de préproduction avant toute utilisation avec des données réelles.
