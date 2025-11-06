# PowerShell-Skript zum Hinzufügen von Koordinaten zu einer KML-Datei
# Textbasierter Ansatz - umgeht XML-Parsing-Probleme

# Konfiguration
$inputFile = "flohmarkt_v1.0.kml"
$outputFile = "flohmarkt_with_coordinates.kml"

# Funktion für einfache URL-Kodierung
function UrlEncode($text) {
    $text = $text -replace ' ', '%20'
    $text = $text -replace 'ä', 'ae' -replace 'ö', 'oe' -replace 'ü', 'ue' -replace 'ß', 'ss'
    $text = $text -replace 'Ä', 'Ae' -replace 'Ö', 'Oe' -replace 'Ü', 'Ue'
    return $text
}

# Hauptskript
try {
    # KML-Datei als Text laden
    Write-Host "Lade KML-Datei als Text: $inputFile"
    $content = Get-Content -Path $inputFile -Encoding UTF8 -Raw
    
    # Finde alle Placemark-Blöcke
    $placemarkMatches = [regex]::Matches($content, '<Placemark>(.*?)</Placemark>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    if ($placemarkMatches.Count -eq 0) {
        # Alternative Pattern für Placemarks
        $placemarkMatches = [regex]::Matches($content, '<Placemark[\s\S]*?</Placemark>')
    }
    
    $total = $placemarkMatches.Count
    Write-Host "Gefunden: $total Placemarks"
    
    if ($total -eq 0) {
        Write-Host "Keine Placemarks gefunden. Überprüfen Sie die KML-Datei." -ForegroundColor Red
        exit
    }
    
    $counter = 0
    $successCount = 0
    
    # Durchlaufe alle Placemarks
    foreach ($match in $placemarkMatches) {
        $counter++
        $placemarkText = $match.Value
        
        # Extrahiere Name und Adresse
        $nameMatch = [regex]::Match($placemarkText, '<name>(.*?)</name>')
        $addressMatch = [regex]::Match($placemarkText, '<address>(.*?)</address>')
        
        $name = if ($nameMatch.Success) { $nameMatch.Groups[1].Value } else { "Unbekannt" }
        $address = if ($addressMatch.Success) { $addressMatch.Groups[1].Value } else { $null }
        
        Write-Host "Verarbeite Standort $counter von $total : $name"
        
        if ($address -and $address.Trim() -ne "") {
            try {
                # URL-Kodierung
                $query = UrlEncode $address
                
                # Geocoding mit Nominatim
                $url = "https://nominatim.openstreetmap.org/search?q=$query&format=json&limit=1"
                $response = Invoke-RestMethod -Uri $url -UserAgent "KML-Geocoding-Script/1.0" -TimeoutSec 10
                
                if ($response -and $response.Count -gt 0) {
                    $lon = $response[0].lon
                    $lat = $response[0].lat
                    
                    # Füge Koordinaten zum Placemark hinzu
                    $pointElement = "<Point><coordinates>$lon,$lat,0</coordinates></Point>"
                    
                    # Ersetze den Placemark-Text mit den hinzugefügten Koordinaten
                    $newPlacemarkText = $placemarkText -replace '</Placemark>', "$pointElement</Placemark>"
                    $content = $content.Replace($placemarkText, $newPlacemarkText)
                    
                    Write-Host "  Erfolg: $lon, $lat"
                    $successCount++
                } else {
                    Write-Host "  Keine Koordinaten gefunden"
                }
            }
            catch {
                Write-Host "  Fehler: $($_.Exception.Message)"
            }
            
            # Warte 1.1 Sekunden zwischen Requests
            Start-Sleep -Milliseconds 1100
        } else {
            Write-Host "  Keine Adresse gefunden"
        }
    }
    
    # Speichere die bearbeitete Datei
    Write-Host "Speichere neue KML-Datei: $outputFile"
    $content | Out-File -FilePath $outputFile -Encoding UTF8
    
    Write-Host "Fertig! Neue Datei wurde erstellt: $outputFile" -ForegroundColor Green
    Write-Host "Erfolgreich geocodiert: $successCount von $total Standorten"
}
catch {
    Write-Host "Fehler: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stellen Sie sicher, dass die KML-Datei im gleichen Verzeichnis liegt und gültig ist."
}