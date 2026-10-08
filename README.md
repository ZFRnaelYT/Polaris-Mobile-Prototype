# Polaris Mobile Prototype

Prototype d’interface mobile et de moteur de tâches Lua pour Roblox, conçu comme démonstrateur technique et modèle de structure.

Ce projet n’est pas présenté comme un outil de triche, d’auto-farm, de téléportation, de combat automatisé ou d’achat illégal de contenu. Le fichier est fourni à titre de démonstration de conception d’interface et de logique d’orchestration de tâches.

## À propos

Le script offre :
- une interface GUI mobile dans Roblox
- un moteur de tâches simple basé sur “ready / step / suspend”
- un système d’activation/désactivation de tâches
- des états de démo et d’expérimentation
- un mode d’intégration avec un adaptateur de jeu

## Limites importantes

Ce projet est une base de démonstration.
Il ne doit pas être utilisé comme :
- cheat
- auto-farm
- automatisation de combat
- téléportation
- achat de Robux ou de contenu non autorisé
- téléchargement ou exécution hors contexte Roblox valide

Le mode “expérimental” mentionné dans le code est uniquement un exemple de logique de branchement. Il doit être adapté par le développeur du jeu et validé selon les règles d’usage du jeu ciblé.

## Installation

1. Ouvrir Roblox Studio
2. Créer un Script Local dans StarterPlayer > StarterPlayerScripts
3. Coller le contenu de `polaris_mobile.lua`
4. Enregistrer
5. Tester en mode Play

## Utilisation

Le script est conçu pour être utilisé comme :
- démonstrateur UI
- point de départ pour un système de tâches
- architecture de moteur de tâches à adapter à un jeu réel

Pour brancher un jeu réel, il faut remplacer la logique “DEMO” par un adaptateur documenté et conforme à l’API de votre projet.

## Structure

- `newEngine(adapter, clock, publish)`
  - moteur de tâches
  - gestion des états
  - activation/désactivation
  - pause / arrêt / reprise

- `newLiveAdapter(...)`
  - adapter de démonstration pour appels distants
  - gestion d’état de requête
  - tentative d’achat / achat simulateur
  - diagnostics basiques

## Avertissement

Cette ressource est fournie “as is”, sans garantie.
L’auteur n’encourage ni n’assume la mise en œuvre d’outils de triche ou d’automatisation non autorisée.
Le code est public uniquement à des fins d’apprentissage, de prototypage et d’exploration technique.

## Licence

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
