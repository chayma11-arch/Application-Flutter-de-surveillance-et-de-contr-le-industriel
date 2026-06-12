# Rapport de l'application IoT Sensor Network

## 1. Présentation générale

Cette application mobile Flutter est conçue pour visualiser et gérer les données IoT issues de capteurs connectés via MQTT. Elle propose une interface utilisateur pour :
- Afficher les mesures en temps réel
- Consulter l'historique des capteurs
- Gérer les alertes et les notifications
- Exporter les données au format PDF
- Authentifier l'utilisateur via Firebase

## 2. Objectif de l'application

L'objectif est de fournir un tableau de bord mobile pour une installation IoT composée de plusieurs nœuds (nodes) et capteurs, avec :
- Lecture en direct des données sensorielles
- Stockage local de l'historique
- Gestion des alertes seuils
- Export des rapports
- Contrôle des actionneurs (LED, servo)

## 3. Architecture logique

### 3.1 Couche Vue (interface)

La couche Vue affiche :
- Données temps réel
- Graphiques et jauges
- Historique des mesures
- Alertes et messages utilisateur
- Navigation entre les écrans

Elle prend en charge les interactions suivantes :
- sélection du nœud
- activation/désactivation des commandes LED/servo
- export PDF
- nettoyage de l'historique
- connexion/déconnexion

### 3.2 Couche Contrôleur / Logique métier

La logique métier orchestre :
- la réception des données MQTT
- le traitement et la mise en forme des valeurs
- la détection d'alertes seuils
- l'actualisation de l'affichage
- la génération de PDF
- l'envoi de notifications locales

### 3.3 Couche Modèle / Persistance

Le modèle représente les données persistées :
- points d'historique sensoriels
- alertes enregistrées
- état et identifiant des nodes

Il assure la cohérence des données locales et gère :
- chargement historique
- ajout de nouveaux points
- suppression/vidage des historiques
- stockage sécurisé sur l'appareil

## 4. Services et traitement

### 4.1 Communication MQTT

La partie temps réel repose sur MQTT :
- broker MQTT distant
- abonnement à des topics capteurs
- publication de commandes aux nœuds
- réception de données Node1, Node2 et statut central

Ce mécanisme permet une communication asynchrone et rapide avec les dispositifs IoT.

### 4.2 Authentification externe

L'application utilise Firebase pour l'authentification utilisateur, ce qui permet :
- login
- inscription
- réinitialisation de mot de passe

### 4.3 Stockage local

Deux systèmes de stockage locaux sont utilisés :
- Hive pour l'historique des capteurs et nodes
- SharedPreferences pour l'historique des alertes

### 4.4 Export et reporting

L'application peut générer des rapports PDF des alertes et des historiques de capteurs. Le PDF contient :
- un en-tête du rapport
- un résumé des données
- des statistiques
- une liste des alertes ou des mesures
- un pied de page

### 4.5 Notifications

Les alertes sont accompagnées de notifications locales. Un mécanisme de temporisation évite les doublons trop fréquents.

## 5. Composants principaux

### 5.1 Front-end

- Vue et navigation
- Affichage direct des données
- Graphiques/indicateurs
- Onglets Dashboard / History / Alerts / Account
- Export PDF
- Interface d'authentification

### 5.2 Back-end applicatif

- Gestion MQTT
- Logique d'alerte
- Stockage Hive 
- Génération PDF
- Notifications locales
- Authentification Firebase

## 6. Technologies utilisées

- Flutter / Dart
- Firebase Auth
- MQTT (`mqtt_client`)
- Hive / Hive Flutter
- SharedPreferences
- pdf / printing / open_file
- fl_chart
- google_fonts
- syncfusion_flutter_gauges

## 7. Fonctionnalités clés

- Lecture des données IoT en temps réel
- Visualisation de l'historique sensoriel
- Gestion des alertes basées sur des seuils
- Export PDF des alertes et historiques
- Authentification utilisateur
- Commandes actionneurs (LED, servo)
- Stockage local des données

## 8. Limitations et constatations

- Aucun middleware Rust ou modèle ONNX n'est présent dans ce dépôt.
- Le broker MQTT est utilisé directement depuis l'application.
- Firebase est présent uniquement pour l'authentification.
- Pas de backend serveur Dart/Node séparé dans le code source.

## 9. Recommandations d'évolution

- Ajouter une couche de services API si vous souhaitez séparer davantage la logique métier de l'UI.
- Mettre en place un traitement plus avancé côté serveur pour l'analyse ou les prévisions.
- Enrichir le modèle de données pour gérer plus de types de capteurs.
- Ajouter des filtres de période et des exports PDF paramétrables.

## 10. Conclusion

L'application est structurée autour d'une architecture propre :
- interface utilisateur (Vue)
- services et logique (Contrôleur)
- modèle de données local (Modèle)

Elle se connecte à des services externes pour MQTT et Firebase, et stocke les données critiques localement pour un usage hors ligne et un accès rapide.

---

*Ce document est un rapport fonctionnel et technique de l'application IoT Sensor Network.*