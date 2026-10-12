# Dorade : tenues et secondary motion du tissu (Godot 4)

Système de **mouvement secondaire des vêtements** en temps réel pour Godot 4.4+, avec six tenues
dans le style FMA. Ce sont uniquement des vêtements, sans corps :

| Tenue | Origine | Tissus simulés |
|---|---|---|
| Roy Mustang | GLB fourni, amélioré | manteau militaire fendu, holster, aiguillette, pantalon bouffant |
| Edward Elric | GLB fourni, amélioré | manteau rouge ouvert (cape) |
| Riza Hawkeye | générée | basque de veste, holster |
| Olivier Mira Armstrong | générée | capote de Briggs jusqu'aux chevilles, sabre |
| Scar | générée | veste ouverte, écharpe nouée (deux pans) |
| Winry Rockbell | générée | haut de combinaison replié, manches nouées, pans de bandana |

```
godot --path . # lance la démo jouable (demo/demo.tscn)
godot --headless -s res://tests/cloth_tests.gd # tests physiques automatiques
```

## Choix technique

Les modèles sont des GLB skinnés (pas de mesh de simulation dédié) et le moteur est Godot 4. La
solution retenue est **hybride, à base d'os secondaires simulés** :

| Brique | Rôle |
|---|---|
| `SecondaryClothSimulator` (`SkeletonModifier3D`) | Solveur Verlet sur des chaînes d'os : inertie, gravité, traînée d'air, vent, liens entre chaînes voisines, collisions capsules, limites d'angle et de courbure. Il s'exécute **après** l'animation, donc il réagit aux mouvements réels du personnage. |
| `ClothProfile` | Comportement d'un textile (léger, classique, épais, manteau long / cape). |
| `ClothWindZone` | Vent avec rafales et turbulence advectée : ondulations progressives et irrégulières. |
| `fabric.gdshader` + `FabricLibrary` | Rendu textile : tissage en micro-relief, sheen doux, intérieur plus sombre (épaisseur), translucidité des tissus fins, ombre dans les plis. |
| `BonePoseCopier` | Fait suivre la tenue au squelette du personnage qui la porte (bones de même nom). |

Pourquoi pas `SoftBody3D` : il est coûteux, instable sur les animations rapides et ne gère pas les
GLB skinnés. Les os secondaires donnent un mouvement crédible pour moins d'1 ms par personnage.

### Ce que fait le solveur à chaque image

1. Il lit la pose animée des chaînes ; leurs racines sont épinglées au squelette.
2. Il intègre les particules en Verlet corrigé en temps, dans l'espace monde : marcher, courir,
   sauter, atterrir, tourner ou changer de direction crée **naturellement** de l'inertie. Une partie
   réglable du mouvement du bassin est transmise directement (`inertia_transfer`) pour rester
   stable lors des animations rapides.
3. Il applique les forces aérodynamiques sur la vitesse relative de l'air (déplacement du
   personnage + vent) : traînée en course, flottement, et **évasement** de la jupe du manteau quand
   l'air remonte le long du tissu (chute, atterrissage).
4. Il rappelle chaque segment vers sa forme animée, de façon locale et en cascade.
5. Contraintes : liens latéraux souples entre chaînes voisines (le manteau reste fermé, les plis se
   propagent, les fentes sont respectées), segments inextensibles, angle maximal, **courbure
   maximale par articulation** (des courbes douces, sans « marches » dans le mesh).
6. Collisions avec des capsules attachées aux os (hanches, torse, cuisses, tibias, avant-bras),
   **ajustées automatiquement** sur la pose de repos pour ne jamais se battre contre la forme
   modélisée. La collision l'emporte sur la limite d'angle.
7. Il réécrit uniquement les **rotations** des os. Les longueurs ne changent jamais, donc le mesh ne
   peut pas s'étirer.

L'immobilité est gérée par un amortissement qui monte **progressivement** (`settle_time`), puis le
groupe se met en veille : coût CPU nul et aucun micro-tremblement. Le vent ou un mouvement le
réveille. Au chargement, une calibration compense la gravité pour que le tissu au repos tombe
exactement sur la forme modélisée.

## Types de tissus

| Profil | Raideur | Traînée air | Vent | Courbure max | Usage |
|---|---|---|---|---|---|
| `ClothProfile.light()` | faible | forte | 1.8 | 50° | foulards, cordons (aiguillette de Mustang) |
| `ClothProfile.classic()` | moyenne | moyenne | 1.0 | 35° | pantalon bouffant de Mustang |
| `ClothProfile.thick()` | forte | faible | 0.35 | 22° | cuir épais (holster) |
| `ClothProfile.long_coat()` | faible en bas | forte | 1.0 | 30° | manteaux longs et capes (traîne visible) |

Toutes les valeurs sont exportées : un profil peut être sauvegardé en `.tres` et réglé dans l'inspecteur.

## Les tenues

`assets/outfits/source/` contient les GLB d'origine. `tools/build_outfit.py` (Blender 4.2+/5.x,
ou `pip install bpy`) produit `assets/outfits/tenue_*.glb` :

- **Effet paillette supprimé** :
  - sur Mustang, un *sheen* blanc à 100 % sur un tissu presque noir rendait le bleu gris et
    scintillant ;
  - sur Edward, la normal map du manteau était entièrement noire (normales invalides), d'où le
    manteau rouge qui paraissait noir et plastique.
- Matériaux par textile (laine, coton, cuir verni, métal) ; bleu d'Amestris corrigé.
- Géométrie nettoyée : lissage des pics du manteau et du pantalon de Mustang, subdivision des pièces
  trop basse résolution, épaisseur sur les galons et épaulettes, UV ajoutées pour le tissage.
- **Squelette complet** (bassin, colonne, bras, jambes) et skinning procédural de toutes les pièces.
  Avant, seul le manteau de Mustang était skinné et Edward n'avait aucun squelette.
- Chaînes de tissu :
  - Mustang : 12 chaînes × 4 os autour du manteau (fentes latérales respectées), holster,
    aiguillette et évasement du pantalon ;
  - Edward : 9 chaînes × 4 os sur le manteau ouvert devant.

```
python3 tools/build_outfit.py mustang assets/outfits/source/tenue_militaire_amestris_mustang.glb assets/outfits/tenue_mustang.glb
python3 tools/build_outfit.py edward assets/outfits/source/tenue_edward_elric.glb assets/outfits/tenue_edward.glb
```

### Tenues générées

`tools/generate_fma_outfits.py` modélise de façon procédurale les tenues de Riza, Olivier, Scar et
Winry, sur les proportions du squelette de Mustang (compatibles avec le même corps). Les sections
sont lissées, les plis sont modelés, chaque pièce a une épaisseur, et les UV sont ajoutées. Les GLB
intermédiaires sont dans `assets/outfits/source/tenue_*_generee.glb`, puis passent par le même rig :

```
python3 tools/generate_fma_outfits.py olivier assets/outfits/source/tenue_olivier_generee.glb
python3 tools/build_outfit.py olivier assets/outfits/source/tenue_olivier_generee.glb assets/outfits/tenue_olivier.glb
```

## Utilisation dans le jeu

Instancier une scène de `outfits/` (`tenue_mustang.tscn`, `tenue_edward.tscn`, `tenue_riza.tscn`,
`tenue_olivier.tscn`, `tenue_scar.tscn`, `tenue_winry.tscn` : nœud `ClothOutfit`), puis au choix :
- animer directement son `Skeleton3D` (AnimationPlayer / AnimationTree) ;
- ou le placer sur le personnage et renseigner `pose_source` avec le squelette du personnage
  (mêmes noms d'os, ou `bone_map` dans `BonePoseCopier`).

Une IK ou une animation procédurale s'insère avant le tissu avec `outfit.add_pose_modifier(mod)`.
Ajouter un `ClothWindZone` dans la scène pour le vent (`radius = 0` pour un vent global). Après une
téléportation ou une coupe de caméra, appeler `simulator.reset_cloth()` (les grands sauts de
position sont aussi détectés automatiquement).

Pour un autre modèle : nommer les os de tissu `<prefixe><id>_<index>` (`cape_00_0`, `cape_00_1`…),
puis passer `preset = "custom"` avec ses `ClothChainGroup` et `ClothCollider`.

### Rendu

`FabricLibrary` remplace les matériaux importés selon leur nom (`cuir` → leather, `gant`/`galon` →
cotton, `manteau` → canvas, etc. ; métaux inchangés). `material_overrides` permet de forcer un
preset. Pour les ombres dans les plis, activer le SSAO dans l'`Environment` (fait dans la démo).

## Démo

`ZQSD`/`WASD` : bouger · `Shift` : courir · `Espace` : sauter · clic + souris : caméra ·
`C` : vue de côté/face · `Tab` : changer de tenue · `V` : vent · `B` : force du vent ·
`F1` : afficher les chaînes et les capsules · `F2` : couper le tissu (comparaison avant/après).

La démo utilise une locomotion procédurale (`demo/procedural_locomotion.gd`) parce que les GLB n'ont
pas d'animations ; dans le jeu, ce sont vos animations qui la remplacent.

## Tests

`tests/cloth_tests.gd` simule, pour chaque tenue (ou seulement certaines :
`godot --headless -s res://tests/cloth_tests.gd -- olivier scar`) : repos, marche, course, arrêt brusque, saut et
atterrissage, demi-tour en 0,35 s, zigzag, vent et téléportation. Il vérifie :
- la réaction du tissu dans chaque cas ;
- le retour progressif à l'équilibre ;
- l'absence de tremblement (une accélération qui change de sens à chaque image) ;
- la mise en veille ;
- l'absence d'étirement et de NaN ;
- le respect des limites ;
- la non-pénétration du corps ;
- le budget temps.

Résultats en GDScript sur CPU, à 60 fps :

| Tenue | Particules | Coût | Traîne en course | Balancement à l'arrêt | Pénétration du corps |
|---|---|---|---|---|---|
| Mustang | 55 | ~0,8 ms | 28 cm | 40 cm | 0 mm |
| Edward | 36 | ~0,5 ms | 30 cm | 48 cm | ≤ 2 mm |

Le coût tombe à ~0 quand le personnage est immobile (veille).
