<#
.SYNOPSIS
Set localized DisplayName and Tooltip for a Purview sensitivity label.

.NOTES
Requires an existing Security & Compliance / Purview PowerShell connection (Get-Label/Set-Label available).

.EXAMPLE
.\Set-MultilingualSensitivityLabels.ps1 -Identity "Confidential" -Locale "nl-NL" -DisplayName "Vertrouwelijk" -Tooltip "Gebruik dit label voor vertrouwelijke gegevens"
.\Set-MultilingualSensitivityLabels.ps1 -Identity "Confidential" -Locale "fr-FR" -DisplayName "Confidentiel" -Tooltip "Utilisez ce libellé pour les données confidentielles"
#>

[CmdletBinding()]
param(
	[Parameter(Position = 0)]
	[string]$Identity,
	[string]$Locale,
	[string]$DisplayName,
	[string]$Tooltip
)

function Need([string]$Prompt, [string]$Value) {
	while ([string]::IsNullOrWhiteSpace($Value)) { $Value = Read-Host $Prompt }
	$Value
}

$Identity = Need "Enter label name or GUID" $Identity
$Locale = Need "Enter locale (e.g. nl-NL, fr-FR)" $Locale
$DisplayName = Need "Enter display name for $Locale" $DisplayName
$Tooltip = Need "Enter tooltip for $Locale" $Tooltip

$label = Get-Label -Identity $Identity -ErrorAction Stop

# Normalize existing locale settings to mutable hashtables.
$localeSettings = @()
foreach ($raw in @($label.LocaleSettings)) {
	if (-not $raw) { continue }
	$obj = if ($raw -is [string]) { try { $raw | ConvertFrom-Json -ErrorAction Stop } catch { $null } } else { $raw }
	if (-not ($obj.LocaleKey -and $obj.Settings)) { continue }
	$settings = @(
		$obj.Settings |
		ForEach-Object { if ($_.Key -and -not [string]::IsNullOrWhiteSpace($_.Value)) { @{ Key = "$( $_.Key )"; Value = "$( $_.Value )" } } } |
		Where-Object { $_ }
	)
	if ($settings.Count) { $localeSettings += @{ LocaleKey = "$( $obj.LocaleKey )"; Settings = $settings } }
}

function Upsert([string]$BucketKey, [string]$LocaleKey, [string]$Value) {
	$entry = $script:localeSettings | Where-Object { $_.LocaleKey -ieq $BucketKey } | Select-Object -First 1
	if (-not $entry) { $entry = @{ LocaleKey = $BucketKey; Settings = @() }; $script:localeSettings += $entry }
	$entry.Settings = @($entry.Settings | Where-Object { $_.Key -ine $LocaleKey })
	if (-not [string]::IsNullOrWhiteSpace($Value)) { $entry.Settings += @{ Key = $LocaleKey; Value = $Value } }
}

Upsert "displayname" $Locale $DisplayName
Upsert "tooltip" $Locale $Tooltip

Write-Host "Updating label $($label.DisplayName) ($($label.Guid)) with locale $Locale..." -ForegroundColor Cyan
try {
	# Pass objects directly; the cmdlet serializes as needed.
	Set-Label -Identity $label.Guid -LocaleSettings $localeSettings -ErrorAction Stop | Out-Null
	Write-Host "Locale settings updated." -ForegroundColor Green
}
catch {
	Write-Error "Failed to set locale settings: $_"
	exit 1
}

Write-Host "Current locales:" -ForegroundColor Yellow
(Get-Label -Identity $label.Guid).LocaleSettings | ConvertTo-Json -Depth 5
