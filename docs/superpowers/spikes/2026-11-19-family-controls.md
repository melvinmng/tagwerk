# Spike: Family Controls mit Personal Team (P3, #161)

Stand: 2026-11-19 · Xcode 27.2 · Signierung: Personal Team · Bau für `generic/platform=iOS` mit `-allowProvisioningUpdates`

## Vorgehen

Auf einem Wegwerf-Branch wurde in `app/project.yml` unter `targets.Tagwerk.entitlements.properties` der Eintrag `com.apple.developer.family-controls: true` ergänzt. Mit Team-ID und Bundle-ID aus der lokalen Konfiguration wurde `xcodegen` ausgeführt und das Schema `Tagwerk` gebaut. Branch und DerivedData wurden danach gelöscht.

## Ergebnis: negativ

Der Bau bricht bei der Signierung ab (IDs im Text ersetzt):

```
error: No Accounts: Add a new account in Accounts settings. (in target 'Tagwerk')
error: Provisioning profile "iOS Team Provisioning Profile: <BUNDLE>" doesn't include the Family Controls (Development) capability. (in target 'Tagwerk')
error: Provisioning profile "iOS Team Provisioning Profile: <BUNDLE>" doesn't include the com.apple.developer.family-controls entitlement. (in target 'Tagwerk')
** BUILD FAILED **
```

## Einschränkung

Die Meldung „No Accounts“ stammt aus der Kommandozeilen-Sitzung ohne Xcode-Konto im Schlüsselbund. Dadurch konnte Xcode das Profil nicht neu anfordern. Das vorhandene Profil des Personal Teams enthält die Fähigkeit jedenfalls nicht. Ob ein Profil-Update in einer angemeldeten Xcode-Sitzung sie hinzufügen würde, ist damit nicht ausgeschlossen, aber nicht belegt. Nach der Vorgabe des Plans gilt der Spike deshalb als negativ.

## Konsequenz

Task 12 (App-Sperre) entfällt. Es gibt keinen Eintrag zur App-Sperre in den Einstellungen und keinen Entitlement-Eintrag. Im PR-Text steht: „App-Sperre nicht gebaut: Family Controls mit Personal Team nicht signierbar.“ Wer sie später bauen will, probiert den Entitlement-Eintrag einmal aus der Xcode-Oberfläche mit angemeldetem Konto aus (Signing & Capabilities → Family Controls).
