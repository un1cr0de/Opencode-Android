# One-click installer driver for Windows. Started by install-opencode.cmd.
# Downloads what is needed, pushes it to the phone over adb, then runs
# files/install-device.sh as root ON THE PHONE.
# Plain ASCII on purpose: Windows PowerShell 5.1 misreads UTF-8 without a BOM.
# Symbols are built from char codes and only used in Windows Terminal.

$ErrorActionPreference = 'Continue'   # native tools write to stderr; exit codes are checked by hand
$ProgressPreference    = 'SilentlyContinue'

$Files  = $PSScriptRoot
$Root   = Split-Path -Parent $PSScriptRoot
$Cache  = Join-Path $Root 'downloads'
$Stage  = Join-Path $Cache 'stage'
$Log    = Join-Path $Root 'install.log'
$Remote = '/data/local/tmp'

$TermuxApk   = 'https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3%2Bgithub-debug_arm64-v8a.apk'
$AlpineDir   = 'https://dl-cdn.alpinelinux.org/alpine/latest-stable/releases/aarch64/'
$OpencodeUrl = 'https://github.com/anomalyco/opencode/releases/latest/download/opencode-linux-arm64-musl.tar.gz'
$ToolsUrl    = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'

# ---- look ------------------------------------------------------------------
$uni = [bool]$env:WT_SESSION
if ($uni) {
    $OK = [string][char]0x2713; $BAD = [string][char]0x2717; $DOT = [string][char]0x00B7
    $FULL = [string][char]0x2588; $EMPTY = [string][char]0x2591
} else {
    $OK = '+'; $BAD = 'x'; $DOT = '.'; $FULL = '#'; $EMPTY = '-'
}
$W = 79
try { $W = $Host.UI.RawUI.WindowSize.Width - 1 } catch { }
if ($W -lt 40) { $W = 79 }
try { $Host.UI.RawUI.WindowTitle = 'opencode installer' } catch { }

$script:step = 'Setup'

# One status row: "  <symbol>  Label     detail". Redraws the same line (carriage
# return) until a row is finished with -Nl.
function Row($sym, $symColor, $label, $detail, $detailColor, [switch]$Nl) {
    if (-not $detailColor) { $detailColor = 'DarkGray' }
    $label = $label.PadRight(9)
    $max = $W - 15
    if ($detail.Length -gt $max) { $detail = $detail.Substring(0, [Math]::Max(0, $max - 1)) }
    Write-Host -NoNewline "`r  "
    Write-Host -NoNewline $sym -ForegroundColor $symColor
    Write-Host -NoNewline "  $label " -ForegroundColor White
    Write-Host -NoNewline $detail -ForegroundColor $detailColor
    Write-Host -NoNewline (' ' * [Math]::Max(0, $W - 15 - $detail.Length))
    if ($Nl) { Write-Host '' }
}
function Live($label, $detail, $color) { $script:step = $label; Row $DOT 'DarkGray' $label $detail $color }
function Done($label, $detail)         { Row $OK 'Green' $label $detail 'DarkGray' -Nl }
function Ask($text) { Write-Host -NoNewline "  $text " -ForegroundColor Yellow; return (Read-Host) }

function Bar($n, $total) {
    $k = [int][Math]::Min(20, [Math]::Floor(20 * $n / $total))
    return ($FULL * $k) + ($EMPTY * (20 - $k))
}

function Get-File($url, $out, $label) {
    if (Test-Path $out) { return }
    $part = "$out.part"
    $total = 0
    try {
        $hdr = (& curl.exe -sIL $url) | Where-Object { $_ -match '(?i)^content-length:\s*\d+' } | Select-Object -Last 1
        if ($hdr -match '(\d+)') { $total = [int64]$Matches[1] }
    } catch { }
    $argv = @('-sSL', '-f', '-C', '-', '--retry', '3', '-o', "`"$part`"", "`"$url`"")
    $p = Start-Process -FilePath curl.exe -ArgumentList $argv -NoNewWindow -PassThru
    $null = $p.Handle
    while (-not $p.HasExited) {
        $n = 0
        if (Test-Path $part) { $n = (Get-Item $part).Length }
        if ($total -gt 0) {
            Live $label ("{0} {1} / {2} MB" -f (Bar $n $total), [Math]::Round($n / 1MB, 1), [Math]::Round($total / 1MB, 1))
        } else {
            Live $label ("{0} MB" -f [Math]::Round($n / 1MB, 1))
        }
        Start-Sleep -Milliseconds 250
    }
    $p.WaitForExit()
    if ($p.ExitCode -ne 0) { throw "download failed ($url)`nCheck your internet connection, then run this again." }
    Move-Item -Force $part $out
}

function Find-Adb {
    $c = Get-Command adb -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    $local = Join-Path $Root 'platform-tools\adb.exe'
    if (-not (Test-Path $local)) {
        $zip = Join-Path $Cache 'platform-tools.zip'
        Get-File $ToolsUrl $zip 'Phone'
        Expand-Archive -Path $zip -DestinationPath $Root -Force
    }
    if (-not (Test-Path $local)) { throw "could not set up adb.`nInstall Google's platform-tools yourself, then run this again." }
    return $local
}

function Write-Banner {
    Write-Host ''
    Write-Host -NoNewline '  opencode' -ForegroundColor White
    Write-Host '  for Android' -ForegroundColor DarkGray
    Write-Host ''
}

# ---- run -------------------------------------------------------------------
$code = 0
try {
    Write-Banner
    New-Item -ItemType Directory -Force -Path $Cache | Out-Null
    Set-Content -Path $Log -Value ("opencode installer log - " + (Get-Date)) -Encoding ASCII

    if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) { throw 'curl.exe is missing (Windows 10 or newer is required).' }
    if (-not (Get-Command tar.exe  -ErrorAction SilentlyContinue)) { throw 'tar.exe is missing (Windows 10 or newer is required).' }
    foreach ($f in 'install-device.sh','oc','opencode-termux.sh','opencode.json','magisk-service.sh','termux.properties','verify.sh','uninstall-device.sh') {
        if (-not (Test-Path (Join-Path $Files $f))) { throw "files\$f is missing.`nExtract the whole zip first. Do not run this from inside the zip." }
    }

    # 1. phone --------------------------------------------------------------
    Live 'Phone' 'looking for adb...'
    $Adb = Find-Adb
    Live 'Phone' 'looking for your phone...'
    $raw  = & $Adb devices 2>&1 | ForEach-Object { "$_" }
    $devs = @($raw | Where-Object { $_ -match '^\S+\s+(device|unauthorized|offline)\s*$' })
    $ready = @($devs | Where-Object { $_ -match '^\S+\s+device\s*$' } | ForEach-Object { ($_ -split '\s+')[0] })
    if ($devs.Count -eq 0) {
        throw "no phone found`nPlug it in with a USB cable that carries data.`nSettings > Developer options > turn on USB debugging.`nThen run this again."
    }
    if ($ready.Count -eq 0) {
        throw "the phone has not allowed this computer yet`nUnlock the phone and tap Allow on the 'Allow USB debugging?' popup.`nThen run this again."
    }
    if ($ready.Count -gt 1) {
        Write-Host ''
        for ($i = 0; $i -lt $ready.Count; $i++) { Write-Host "    [$($i+1)] $($ready[$i])" -ForegroundColor DarkGray }
        $pick = Ask 'More than one phone. Type the number to use:'
        $n = 0
        if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $ready.Count) { throw 'invalid choice' }
        $Serial = $ready[$n - 1]
    } else { $Serial = $ready[0] }

    $abi = ((& $Adb -s $Serial shell getprop ro.product.cpu.abi) | Out-String).Trim()
    if ($abi -ne 'arm64-v8a') { throw "this phone is '$abi'`nOnly arm64-v8a phones are supported." }
    $model = ((& $Adb -s $Serial shell getprop ro.product.model) | Out-String).Trim()

    Live 'Phone' 'checking root - tap GRANT on the phone if asked' 'Yellow'
    $idout = (& $Adb -s $Serial shell "su -c id" 2>&1 | Out-String)
    if ($idout -notmatch 'uid=0') {
        throw "no root for adb`nUnlock the phone, run this again, and tap GRANT on the Magisk popup.`nNo popup? Magisk app > Superuser > Shell > Allow.`nAlso Magisk settings > Superuser access = 'Apps and ADB'."
    }
    Done 'Phone' "$model  $DOT  arm64  $DOT  root"

    # 2. termux -------------------------------------------------------------
    Live 'Termux' 'checking...'
    $pk = (& $Adb -s $Serial shell pm list packages com.termux | Out-String)
    if ($pk -notmatch '(?m)^package:com\.termux\s*$') {
        $apk = Join-Path $Cache 'termux.apk'
        Get-File $TermuxApk $apk 'Termux'
        Live 'Termux' 'installing...'
        & $Adb -s $Serial install -r $apk | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Termux would not install`nIf Play Protect blocked it, run:  adb shell settings put global verifier_verify_adb_installs 0`nThen run this again." }
        & $Adb -s $Serial shell monkey -p com.termux -c android.intent.category.LAUNCHER 1 | Out-Null
        Live 'Termux' 'wait for the $ prompt on the phone, then press Enter' 'Yellow'
        $null = Read-Host
        Done 'Termux' 'installed'
    } else { Done 'Termux' 'ready' }

    # 3. alpine -------------------------------------------------------------
    $alpine = Join-Path $Cache 'alpine.tar.gz'
    if (Test-Path $alpine) {
        Done 'Alpine' 'cached'
    } else {
        Live 'Alpine' 'checking the latest version...'
        $page = (& curl.exe -sL -f --retry 3 $AlpineDir) -join "`n"
        $vers = @([regex]::Matches($page, 'alpine-minirootfs-(\d+\.\d+\.\d+)-aarch64\.tar\.gz"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object { [version]$_ } -Unique)
        if ($vers.Count -eq 0) { throw "could not read the Alpine download list`nDownload alpine-minirootfs-...-aarch64.tar.gz yourself from`n$AlpineDir`nsave it as downloads\alpine.tar.gz, then run this again." }
        $name = "alpine-minirootfs-$($vers[-1])-aarch64.tar.gz"
        Get-File ($AlpineDir + $name) $alpine 'Alpine'
        $shaTxt = (& curl.exe -sL -f ($AlpineDir + $name + '.sha256')) -join ' '
        if ($shaTxt -match '^\s*([0-9a-f]{64})') {
            $have = (Get-FileHash -Algorithm SHA256 $alpine).Hash.ToLower()
            if ($have -ne $Matches[1]) { Remove-Item -Force $alpine; throw 'Alpine download is corrupt (checksum mismatch). Run this again.' }
        }
        Done 'Alpine' "$($vers[-1])  $DOT  checksum ok"
    }

    # 4. opencode -----------------------------------------------------------
    $bin = Join-Path $Cache 'opencode-bin'
    if (Test-Path $bin) {
        Done 'opencode' 'cached'
    } else {
        $tgz = Join-Path $Cache 'opencode-linux-arm64-musl.tar.gz'
        Get-File $OpencodeUrl $tgz 'opencode'
        Live 'opencode' 'unpacking...'
        $ex = Join-Path $Cache 'opencode-extract'
        if (Test-Path $ex) { Remove-Item -Recurse -Force $ex }
        New-Item -ItemType Directory -Force -Path $ex | Out-Null
        & tar.exe -xzf $tgz -C $ex
        if ($LASTEXITCODE -ne 0) { Remove-Item -Force $tgz; throw 'could not unpack opencode (corrupt download?). Run this again.' }
        $found = Get-ChildItem -Path $ex -Recurse -File | Where-Object { $_.Name -eq 'opencode' } | Select-Object -First 1
        if (-not $found -or $found.Length -lt 50MB) { throw 'the opencode download did not contain the expected program.' }
        Copy-Item -Force $found.FullName $bin
        Remove-Item -Recurse -Force $ex
        Done 'opencode' ("{0} MB" -f [Math]::Round($found.Length / 1MB))
    }

    # 5. copy ---------------------------------------------------------------
    Live 'Copy' 'preparing files...'
    if (Test-Path $Stage) { Remove-Item -Recurse -Force $Stage }
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null
    foreach ($f in 'install-device.sh','oc','opencode-termux.sh','opencode.json','magisk-service.sh','termux.properties','verify.sh','uninstall-device.sh') {
        # the phone's shell chokes on Windows line endings, so strip any CR
        $b = [IO.File]::ReadAllBytes((Join-Path $Files $f))
        [IO.File]::WriteAllBytes((Join-Path $Stage $f), [byte[]]@($b | Where-Object { $_ -ne 13 }))
    }
    Copy-Item -Force $alpine (Join-Path $Stage 'alpine.tar.gz')
    Copy-Item -Force $bin    (Join-Path $Stage 'opencode-bin')
    $items = @(Get-ChildItem -File $Stage)
    $i = 0
    foreach ($item in $items) {
        $i++
        Live 'Copy' ("{0} {1}/{2}  {3}" -f (Bar $i $items.Count), $i, $items.Count, $item.Name)
        & $Adb -s $Serial push $item.FullName "$Remote/$($item.Name)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "could not copy $($item.Name) to the phone" }
    }
    Done 'Copy' "$($items.Count) files to the phone"

    # 6. install (as root, on the phone) -------------------------------------
    Live 'Install' 'starting...'
    & $Adb -s $Serial shell "su -c 'sh $Remote/install-device.sh'" 2>&1 | ForEach-Object {
        $line = "$_"
        Add-Content -Path $Log -Value $line -Encoding ASCII
        if ($line -match '^==> (.+)$') { Live 'Install' $Matches[1] }
    }
    $text = (Get-Content -Path $Log) -join "`n"
    if ($text -notmatch '==> done') {
        $tail = (Get-Content -Path $Log | Select-Object -Last 8) -join "`n"
        throw "the installer on the phone did not finish`n$tail`nFull log: $Log`nFix what it says, then run this again. It is safe to repeat."
    }
    if ($text -match 'not bootstrapped|Termux not installed') {
        throw "Termux has not finished its first start`nOpen Termux on the phone, wait for the $ prompt, then run this again."
    }
    Done 'Install' 'done'

    # finish ----------------------------------------------------------------
    Write-Host ''
    $ans = Ask 'Restart the phone now? Needed once. [Y/n]'
    if ($ans -notmatch '^[nN]') { & $Adb -s $Serial reboot | Out-Null }
    Write-Host ''
    Write-Host -NoNewline '  Open Termux and type  ' -ForegroundColor Gray
    Write-Host 'opencode' -ForegroundColor Green
    Write-Host '  Then type /connect to choose a model.' -ForegroundColor DarkGray
}
catch {
    $lines = @(($_.Exception.Message -split "`n") | ForEach-Object { $_.TrimEnd("`r") })
    Row $BAD 'Red' $script:step $lines[0] 'Red' -Nl
    foreach ($l in ($lines | Select-Object -Skip 1)) { Write-Host "             $l" -ForegroundColor DarkGray }
    $code = 1
}
exit $code
