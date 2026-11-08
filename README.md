# Arcana Bestia

Jeu Roblox de collection de créatures : ouvre des boosters, découvre des bêtes
arcaniques et complète ton bestiaire. Fonctionne sur PC, Mac, mobile, tablette
et console (Xbox / PlayStation).

## Lancer le projet

```bash
rojo build -o "ArcanaBestia.rbxlx"   # construire le place
rojo serve                           # synchroniser avec Roblox Studio
```

Pour la sauvegarde en Studio : *Game Settings > Security > Enable Studio Access
to API Services*. Sans ça, le jeu fonctionne mais les profils ne sont pas sauvegardés.

## Contenu

- **Menu d'accueil** : caméra cinématique autour de l'arène, chargement du monde,
  Jouer / Collection / Paramètres / Aide & crédits.
- **Cité de Brumeval** (`src/server/World.server.luau` + `Village.server.luau`) :
  l'arène de l'autel au centre, entourée d'une ville médiévale fantastique
  fortifiée (~400×400 studs) : boulevard circulaire, avenues, rues pavées,
  ~200 maisons à colombages mitoyennes générées le long des rues, remparts
  crénelés avec chemin de ronde, tours et portes, montagnes en toile de fond,
  cycle jour/nuit, éclairage *Future*.
- **Boosters** : tirage pondéré côté serveur, animation de révélation selon la
  rareté, remboursement des doublons.
- **Économie & sauvegarde** (`DataService`) : gemmes, cadeau toutes les 20 h,
  profils persistés via DataStore (pas de revenu passif : les gemmes se gagnent en jouant).
- **Bestiaire** : grille filtrable par rareté, cartes non découvertes masquées,
  vue détaillée.

## Les quartiers

- **Grand-Place** (sud) : fontaine, Comptoir des Merveilles, **Elya** (boutique),
  taverne du Griffon Doré, boulangerie, étals.
- **Quartier des Artisans** (ouest) : forge de **Borin** (vente et fusion de
  doublons), puits, ateliers ; **Pip** y indique où se cache le coffre de gemmes.
- **Quartier des Mages** (nord) : tour de **Maître Orin** (épreuves), sanctuaire
  des cristaux de **Sélène** (booster mystique), obélisque.
- **Jardin du Prieuré** (sud-est) : le seul vrai coin de verdure, avec quelques
  petits jardins clos dans les rues.
- **Remparts** : escaliers d'accès au chemin de ronde.

## L'Arène des Champions

À l'est, au bout de l'avenue : colisée à arcades sur deux niveaux, piste de
sable, 7 rangées de gradins, loge d'honneur. **Varek** y lance les duels et
l'entraînement.

## Récompenses quotidiennes

Un calendrier de 7 jours (bouton QUOTIDIEN) : 100 → 500 ◆, un booster au
jour 4 et une carte Rare ou mieux au jour 7. Un jour manqué remet la série à 1.

## Contrôles

| | PC | Manette (Xbox / PlayStation) | Mobile |
|---|---|---|---|
| Courir | Maj (maintenir) | L3 | Bouton « Courir » |
| Booster | B | R1 | Autel ou boutique |
| Collection / livre | C | Triangle (Y) | Bouton à l'écran |
| Autel | E | Carré (X) | Toucher l'invite |
| Menu / retour | M | Rond (B) | MENU |
| Tutoriel | bouton ? | bouton ? | bouton ? |

## Structure

- `src/shared/Configs/CardsData.luau` — cartes, raretés, éléments, économie.
- `src/server/` — `World` (génération), `CardManager` (remotes), `DataService`.
- `src/client/` — `ClientManager` + modules `UI/` (UIKit, MainMenu, HUD, Reveal,
  Panels, CardView).
