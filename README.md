# Complexe Scolaire SAINT JEAN PAUL II — Système de suivi de Scolarité

Application Android (Kotlin / Jetpack Compose) pour Parents, Enseignants et Personnel de cantine, avec une interface web d'administration pour la Direction, sur Supabase.

République Togolaise · Contact permanent Enseignant / Parent / Direction.

## Contenu du dépôt
- `app/` : application Android (code d'accès → espace Parent, Enseignant ou Cantine).
- `admin/index.html` (et `index.html` à la racine pour GitHub Pages) : interface Direction.
- `supabase/SCHEMA_SAINT_JEAN_PAUL_II.sql` : base de données complète (classes, matières par niveau, règle « un seul enseignant par classe au Primaire » incluses).
- `supabase/MISES_A_JOUR/` : scripts à exécuter uniquement sur une base DÉJÀ installée (03 : classes et matières par niveau ; 04 : enseignant unique au Primaire).
- `.github/workflows/android.yml` : compilation automatique de l'APK.

## Installation (ordre à suivre)
1. **Base de données** : Supabase > SQL Editor > New query > coller tout le fichier `supabase/SCHEMA_SAINT_JEAN_PAUL_II.sql` > Run.
   ⚠ Ce script remplace les tables de l'ancienne version « CONNECT TEST » (données de test supprimées). Le compte Direction existant est conservé.
2. **Compte Direction** : Supabase > Authentication > Users > créer l'e-mail + mot de passe de la Direction. Ouvrir l'interface admin, se connecter, puis « Initialiser ce compte Direction » (le premier compte devient la Direction).
3. **Projet Supabase** : l'URL et la clé « Publishable » sont déjà renseignées (projet de l'ancienne version). Pour utiliser un nouveau projet Supabase, changer ces deux valeurs dans `app/build.gradle.kts` (`SUPABASE_URL`, `SUPABASE_ANON_KEY`) et dans `admin/index.html` + `index.html` (constante `CONFIG`). Ne jamais mettre de clé `service_role` dans le dépôt.
4. **APK** : pousser le dépôt sur GitHub (branche `main`) : l'onglet Actions compile l'APK (artefact `SaintJeanPaulII-debug-apk`).
5. **Nettoyage cantine du dimanche** : le script active `pg_cron` (Supabase > Database > Extensions) pour effacer menus + photos chaque dimanche à 00h GMT. Même sans pg_cron, l'effacement est appliqué automatiquement à la première utilisation de la cantine après dimanche 00h GMT.

## Fonctionnement
- **Classes** : Primaire (CI1, CI2, CP1, CP2, CE1, CE2, CM1, CM2) et Collège (6ième, 5ième, 4ième, 3ième).
- **Admin** : deux grands onglets, Primaire (logo + rose) et Collège (logo seul). Chaque niveau a ses parents, élèves, enseignants, notes, frais et messages. Les onglets Cantine et Administration sont permanents.
- **Parent d'abord** : il n'existe plus d'ajout direct d'élève. On enregistre un parent (Père, Mère, Tante, Oncle, Tuteur) avec ses enfants ; la base refuse tout élève sans parent. Codes : parent 4 caractères, enseignant 5, cantine 6 (générés automatiquement).
- **Cantine** : les personnes de la cantine saisissent le plat du jour et ajoutent 2 photos (au total pour toute la cantine) ; les autres peuvent les voir. Les parents consultent les repas de leur enfant par date. Menus + photos effacés chaque dimanche à 00h GMT.
- **Frais de scolarité** : montant total par classe (modifiable), jusqu'à 15 tranches par élève, recherche par nom, rapport avancé (filtres classe/statut/seuils, tris, export CSV/PDF). Les parents voient payé et reste à payer.
- **Messages Direction** : tous les parents d'un niveau, d'une classe, un parent précis (recherche de l'élève), tous les enseignants, un enseignant, toute la cantine. La Direction lit et supprime tous les messages Parent ↔ Enseignant.
- **Messagerie** Parent ↔ Enseignant : 5 messages par jour et par compte, remise à zéro à 00h GMT.


## Enseignants : Primaire et Collège
- **Primaire** : une classe = un seul enseignant, qui assure toutes les matières du Primaire (affectées automatiquement). Dans l'application Parent, « Voir les enseignants de mon enfant » affiche le nom de l'enseignant avec ses matières en dessous.
- **Collège** : plusieurs enseignants par classe, chacun avec ses matières ; l'application Parent affiche chaque enseignant avec ses matières.
- Couleur principale de l'interface : bleu marine foncé `#0B1F44`.
