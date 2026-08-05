param(
    [int]$Port = 8765,
    [switch]$Cellular
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName UIAutomationClient

function Get-ScreenJpeg {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $source = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $sourceGraphics = [System.Drawing.Graphics]::FromImage($source)
    try {
        $sourceGraphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
        $targetWidth = [Math]::Min(1280, $bounds.Width)
        $targetHeight = [Math]::Max(1, [int][Math]::Round($bounds.Height * ($targetWidth / [double]$bounds.Width)))
        $target = New-Object System.Drawing.Bitmap($targetWidth, $targetHeight)
        $targetGraphics = [System.Drawing.Graphics]::FromImage($target)
        try {
            $targetGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
            $targetGraphics.DrawImage($source, 0, 0, $targetWidth, $targetHeight)
            $stream = New-Object System.IO.MemoryStream
            try {
                $target.Save($stream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
                return $stream.ToArray()
            }
            finally { $stream.Dispose() }
        }
        finally {
            $targetGraphics.Dispose()
            $target.Dispose()
        }
    }
    finally {
        $sourceGraphics.Dispose()
        $source.Dispose()
    }
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $elevatedArguments = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $MyInvocation.MyCommand.Path),
        '-Port', $Port
    )
    if ($Cellular) { $elevatedArguments += '-Cellular' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevatedArguments
    exit
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class RemoteInput {
    [StructLayout(LayoutKind.Sequential)]
    private struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT {
        public uint type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT {
        public int dx, dy;
        public uint mouseData, dwFlags, time;
        public UIntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT {
        public ushort wVk, wScan;
        public uint dwFlags, time;
        public UIntPtr dwExtraInfo;
    }

    [DllImport("user32.dll")] private static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] private static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] private static extern void mouse_event(uint flags, uint dx, uint dy, int data, UIntPtr extraInfo);
    [DllImport("user32.dll")] private static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extraInfo);
    [DllImport("user32.dll")] private static extern uint SendInput(uint count, INPUT[] inputs, int size);

    public static void Move(int dx, int dy) {
        POINT p; GetCursorPos(out p);
        SetCursorPos(p.X + dx, p.Y + dy);
    }

    public static void MouseDown(string button) { mouse_event(button == "right" ? 0x0008u : 0x0002u, 0, 0, 0, UIntPtr.Zero); }
    public static void MouseUp(string button) { mouse_event(button == "right" ? 0x0010u : 0x0004u, 0, 0, 0, UIntPtr.Zero); }
    public static void Click(string button) { MouseDown(button); MouseUp(button); }
    public static void Scroll(int amount) { mouse_event(0x0800, 0, 0, amount, UIntPtr.Zero); }

    public static void Key(int vk) {
        keybd_event((byte)vk, 0, 0, UIntPtr.Zero);
        keybd_event((byte)vk, 0, 2, UIntPtr.Zero);
    }

    public static void Hotkey(int modifier, int key) {
        keybd_event((byte)modifier, 0, 0, UIntPtr.Zero);
        keybd_event((byte)key, 0, 0, UIntPtr.Zero);
        keybd_event((byte)key, 0, 2, UIntPtr.Zero);
        keybd_event((byte)modifier, 0, 2, UIntPtr.Zero);
    }

    public static void Text(string text) {
        foreach (char c in text) {
            INPUT[] inputs = new INPUT[2];
            inputs[0].type = 1;
            inputs[0].U.ki.wScan = c;
            inputs[0].U.ki.dwFlags = 0x0004;
            inputs[1].type = 1;
            inputs[1].U.ki.wScan = c;
            inputs[1].U.ki.dwFlags = 0x0004 | 0x0002;
            SendInput(2, inputs, Marshal.SizeOf(typeof(INPUT)));
        }
    }
}
'@

$pin = Get-Random -Minimum 100000 -Maximum 999999
$html = Get-Content -Raw (Join-Path $root 'index.html')
$listener = New-Object System.Net.HttpListener
$secretPath = if ($Cellular) { ([Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')) } else { '' }
$pagePath = if ($Cellular) { "/$secretPath/" } else { '/' }
$apiPath = if ($Cellular) { "/$secretPath/api/action" } else { '/api/action' }
$screenPath = if ($Cellular) { "/$secretPath/screen.jpg" } else { '/screen.jpg' }
$focusPath = if ($Cellular) { "/$secretPath/focus" } else { '/focus' }
$listenHost = if ($Cellular) { '127.0.0.1' } else { '+' }
$listener.Prefixes.Add("http://${listenHost}:$Port/")
$listener.Start()

$tunnelProcess = $null
$tunnelLog = $null
if ($Cellular) {
    $toolDir = Join-Path $root 'tools'
    $cloudflared = Join-Path $toolDir 'cloudflared.exe'
    if (-not (Test-Path $cloudflared)) {
        New-Item -ItemType Directory -Force $toolDir | Out-Null
        Write-Host 'Downloading the secure tunnel helper (first run only)...' -ForegroundColor Cyan
        Invoke-WebRequest `
            -Uri 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' `
            -OutFile $cloudflared `
            -UseBasicParsing
    }

    $tunnelLog = Join-Path $env:TEMP ("bed-desk-tunnel-" + [Guid]::NewGuid().ToString('N') + '.log')
    $tunnelProcess = Start-Process -FilePath $cloudflared `
        -ArgumentList @('tunnel', '--url', "http://127.0.0.1:$Port", '--no-autoupdate') `
        -RedirectStandardOutput $tunnelLog `
        -RedirectStandardError ($tunnelLog + '.err') `
        -WindowStyle Hidden `
        -PassThru

    $publicBase = $null
    for ($attempt = 0; $attempt -lt 60 -and -not $publicBase; $attempt++) {
        Start-Sleep -Milliseconds 500
        $combinedLog = ''
        if (Test-Path $tunnelLog) { $combinedLog += Get-Content -Raw $tunnelLog }
        if (Test-Path ($tunnelLog + '.err')) { $combinedLog += Get-Content -Raw ($tunnelLog + '.err') }
        if ($combinedLog -match 'https://[a-z0-9-]+\.trycloudflare\.com') { $publicBase = $Matches[0] }
        if ($tunnelProcess.HasExited) { break }
    }
    if (-not $publicBase) {
        if ($tunnelProcess -and -not $tunnelProcess.HasExited) { $tunnelProcess.Kill() }
        $listener.Stop()
        throw 'The cellular tunnel could not start. Check the internet connection and try again.'
    }
    $connectionUrl = "$publicBase/$secretPath/"
    $phoneUrl = 'https://sheep4mil-ui.github.io/bed-desk/'
    $pairAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    $pairBytes = New-Object byte[] 8
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($pairBytes)
    $pairCode = -join ($pairBytes | ForEach-Object { $pairAlphabet[$_ % $pairAlphabet.Length] })
    $hostFragment = '#host=' + $pairCode +
        '&server=' + [Uri]::EscapeDataString($connectionUrl) +
        '&pin=' + $pin
    Start-Process ($phoneUrl + $hostFragment)
}
else {
    $localIp = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Sort-Object { if ($_.InterfaceAlias -match 'Wi-Fi|Ethernet') { 0 } else { 1 } } |
        Select-Object -First 1 -ExpandProperty IPAddress
    if (-not $localIp) { $localIp = 'localhost' }
    $phoneUrl = "http://${localIp}:$Port"
}

Clear-Host
Write-Host ''
Write-Host $(if ($Cellular) { '  BED DESK CELLULAR IS RUNNING' } else { '  BED DESK IS RUNNING' }) -ForegroundColor Green
Write-Host ''
Write-Host "  On your phone, open:" -ForegroundColor Cyan
Write-Host "  $phoneUrl" -ForegroundColor Cyan
if ($Cellular) {
    Write-Host ''
    Write-Host '  Enter this code:' -ForegroundColor Cyan
    Write-Host "  $($pairCode.Substring(0,4)) $($pairCode.Substring(4,4))" -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  Keep the Bed Desk setup tab open on this PC.' -ForegroundColor DarkGray
}
else { Write-Host "  PIN:                  $pin" -ForegroundColor Yellow }
Write-Host ''
Write-Host '  Keep this window open. Press Ctrl+C here to stop.' -ForegroundColor DarkGray
if (-not $Cellular) { Write-Host '  Both devices must be on the same Wi-Fi.' -ForegroundColor DarkGray }
else { Write-Host '  Cellular mode is temporary; the address expires when this closes.' -ForegroundColor DarkGray }
Write-Host ''

$keys = @{
    enter=0x0D; backspace=0x08; tab=0x09; escape=0x1B; space=0x20
    left=0x25; up=0x26; right=0x27; down=0x28; delete=0x2E
    home=0x24; end=0x23; pageup=0x21; pagedown=0x22
    f5=0x74
}

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response
        $response.Headers['Cache-Control'] = 'no-store'
        if ($request.Headers['Origin'] -eq 'https://sheep4mil-ui.github.io') {
            $response.Headers['Access-Control-Allow-Origin'] = 'https://sheep4mil-ui.github.io'
            $response.Headers['Vary'] = 'Origin'
        }

        try {
            if ($request.HttpMethod -eq 'OPTIONS' -and ($request.Url.AbsolutePath -eq $apiPath -or $request.Url.AbsolutePath -eq $screenPath -or $request.Url.AbsolutePath -eq $focusPath)) {
                $response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
                $response.Headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Remote-Pin'
                $response.Headers['Access-Control-Max-Age'] = '600'
                $response.StatusCode = 204
                continue
            }

            if ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq $pagePath) {
                $bytes = [Text.Encoding]::UTF8.GetBytes($html)
                $response.ContentType = 'text/html; charset=utf-8'
                $response.Headers['X-Content-Type-Options'] = 'nosniff'
                $response.Headers['Referrer-Policy'] = 'no-referrer'
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
                continue
            }

            if ($request.Url.AbsolutePath -ne $apiPath -and $request.Url.AbsolutePath -ne $screenPath -and $request.Url.AbsolutePath -ne $focusPath) {
                $response.StatusCode = 404
                continue
            }

            if ($request.Headers['X-Remote-Pin'] -ne [string]$pin) {
                Start-Sleep -Milliseconds 250
                $response.StatusCode = 401
                continue
            }

            if ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq $screenPath) {
                $screenBytes = Get-ScreenJpeg
                $response.ContentType = 'image/jpeg'
                $response.Headers['X-Content-Type-Options'] = 'nosniff'
                $response.ContentLength64 = $screenBytes.Length
                $response.OutputStream.Write($screenBytes, 0, $screenBytes.Length)
                continue
            }

            if ($request.HttpMethod -eq 'GET' -and $request.Url.AbsolutePath -eq $focusPath) {
                $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
                $isText = $false
                if ($focused) {
                    $controlType = $focused.Current.ControlType
                    $isText = $controlType -eq [System.Windows.Automation.ControlType]::Edit -or
                        $controlType -eq [System.Windows.Automation.ControlType]::Document -or
                        $controlType -eq [System.Windows.Automation.ControlType]::ComboBox
                }
                $focusBytes = [Text.Encoding]::UTF8.GetBytes($(if ($isText) { '{"text":true}' } else { '{"text":false}' }))
                $response.ContentType = 'application/json; charset=utf-8'
                $response.ContentLength64 = $focusBytes.Length
                $response.OutputStream.Write($focusBytes, 0, $focusBytes.Length)
                continue
            }

            if ($request.HttpMethod -ne 'POST' -or $request.Url.AbsolutePath -ne $apiPath) {
                $response.StatusCode = 405
                continue
            }

            $reader = New-Object IO.StreamReader($request.InputStream, $request.ContentEncoding)
            $body = $reader.ReadToEnd() | ConvertFrom-Json
            switch ($body.type) {
                'move' {
                    $dx = [Math]::Max(-160, [Math]::Min(160, [int]$body.dx))
                    $dy = [Math]::Max(-160, [Math]::Min(160, [int]$body.dy))
                    [RemoteInput]::Move($dx, $dy)
                }
                'click' { [RemoteInput]::Click([string]$body.button) }
                'down' { [RemoteInput]::MouseDown([string]$body.button) }
                'up' { [RemoteInput]::MouseUp([string]$body.button) }
                'scroll' { [RemoteInput]::Scroll([Math]::Max(-720, [Math]::Min(720, [int]$body.amount))) }
                'text' {
                    $text = [string]$body.text
                    if ($text.Length -gt 2000) { $text = $text.Substring(0, 2000) }
                    [RemoteInput]::Text($text)
                }
                'key' {
                    $name = ([string]$body.key).ToLowerInvariant()
                    if ($keys.ContainsKey($name)) { [RemoteInput]::Key($keys[$name]) }
                }
                'hotkey' {
                    $name = ([string]$body.key).ToLowerInvariant()
                    $hotkeys = @{ copy=0x43; paste=0x56; cut=0x58; undo=0x5A; redo=0x59; selectall=0x41; save=0x53 }
                    if ($hotkeys.ContainsKey($name)) { [RemoteInput]::Hotkey(0x11, $hotkeys[$name]) }
                }
                'stop' {
                    $response.StatusCode = 204
                    $response.Close()
                    $listener.Stop()
                    continue
                }
            }
            $response.StatusCode = 204
        }
        catch {
            $response.StatusCode = 400
        }
        finally {
            if ($response.OutputStream) { $response.OutputStream.Close() }
        }
    }
}
finally {
    if ($listener.IsListening) { $listener.Stop() }
    $listener.Close()
    if ($tunnelProcess -and -not $tunnelProcess.HasExited) { $tunnelProcess.Kill() }
    if ($tunnelLog) {
        Remove-Item -LiteralPath $tunnelLog -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath ($tunnelLog + '.err') -Force -ErrorAction SilentlyContinue
    }
}
