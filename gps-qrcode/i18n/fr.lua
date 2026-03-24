-- if key ends with ASCII => no accentuated chars (ethos < 1.7 compatibility)
-- the key ending with UT8 has the same purpose for ethos >= 1.7
-- even in UTF8 not all characters are available, please do check your translation with the nightly26
return {
    progressTitle = "Progression",
    progressText = "Génération du code QR...",
    findYourModel = "Retrouvez votre modèle avec un code QR !",
    waitingForGPSSignal = "En attente du signal GPS...",
    generateQRCode = "Générer le code QR",
}
