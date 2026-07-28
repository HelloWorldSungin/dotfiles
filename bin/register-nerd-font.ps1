# Register Nerd Font for MobaXterm without Windows Administrator privileges
# Usage in Windows PowerShell:
# powershell -ExecutionPolicy Bypass -File bin/register-nerd-font.ps1

$FontFile = Get-ChildItem "$env:USERPROFILE\Downloads\*NerdFont*.ttf" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $FontFile) {
    $FontFile = Get-ChildItem "$env:USERPROFILE\Downloads\*.ttf" -ErrorAction SilentlyContinue | Select-Object -First 1
}

if ($FontFile) {
    Write-Host "Found font file: $($FontFile.Name)" -ForegroundColor Cyan
    $FontsFolder = "$env:LOCALAPPDATA\Microsoft\Windows\Fonts"
    if (-not (Test-Path $FontsFolder)) {
        New-Item -ItemType Directory -Path $FontsFolder -Force | Out-Null
    }
    $Destination = "$FontsFolder\$($FontFile.Name)"
    Copy-Item $FontFile.FullName -Destination $Destination -Force
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts" -Name "$($FontFile.BaseName) (TrueType)" -Value $Destination
    Add-Type -MemberDefinition '[DllImport("gdi32.dll")] public static extern int AddFontResource(string path);' -Name 'GDI' -Namespace 'Win32'
    [Win32.GDI]::AddFontResource($Destination) | Out-Null
    Write-Host "✅ Font successfully registered for MobaXterm!" -ForegroundColor Green
    Write-Host "Restart MobaXterm and select $($FontFile.BaseName) under Settings -> Configuration -> Terminal." -ForegroundColor Yellow
} else {
    Write-Host "❌ Could not find any .ttf font file in Downloads folder ($env:USERPROFILE\Downloads)." -ForegroundColor Red
    Write-Host "Please download a Nerd Font (e.g. JetBrainsMono Nerd Font) into your Downloads folder first." -ForegroundColor Yellow
}
