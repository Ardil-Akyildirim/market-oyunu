$port = 8080
$root = Join-Path $PSScriptRoot "build\web"
if (-not (Test-Path $root)) {
    Write-Host "Hata: build/web klasoru bulunamadi!" -ForegroundColor Red
    pause
    exit
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://127.0.0.1:$port/")
try {
    $listener.Start()
} catch {
    Start-Process "http://127.0.0.1:$port/"
    exit
}

Write-Host "======================================================"
Write-Host "  Market Oyunu (2D) Yerel Sunucusu Calisiyor..."
Write-Host "  Adres: http://127.0.0.1:$port/"
Write-Host "======================================================"
Write-Host "Oyundan cikmak icin bu siyah pencereyi kapatabilirsiniz.`n"

Start-Process "http://127.0.0.1:$port/"

$mimeTypes = @{
    ".html" = "text/html; charset=utf-8"
    ".js"   = "application/javascript; charset=utf-8"
    ".css"  = "text/css; charset=utf-8"
    ".json" = "application/json; charset=utf-8"
    ".png"  = "image/png"
    ".jpg"  = "image/jpeg"
    ".wasm" = "application/wasm"
    ".ttf"  = "font/ttf"
    ".ico"  = "image/x-icon"
    ".svg"  = "image/svg+xml"
}

while ($listener.IsListening) {
    try {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $urlPath = $request.Url.LocalPath.TrimStart('/')
        if ([string]::IsNullOrEmpty($urlPath) -or $urlPath -eq "/") { $urlPath = "index.html" }
        $filePath = Join-Path $root ($urlPath -replace '/', '\')

        if (-not (Test-Path $filePath -PathType Leaf)) {
            $filePath = Join-Path $root "index.html"
        }

        $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
        $contentType = if ($mimeTypes.ContainsKey($ext)) { $mimeTypes[$ext] } else { "application/octet-stream" }
        $response.ContentType = $contentType
        $response.AddHeader("Access-Control-Allow-Origin", "*")
        $response.AddHeader("Cache-Control", "no-cache, no-store, must-revalidate")
        $response.AddHeader("Pragma", "no-cache")
        $response.AddHeader("Expires", "0")

        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
        $response.OutputStream.Close()
    } catch {
    }
}
