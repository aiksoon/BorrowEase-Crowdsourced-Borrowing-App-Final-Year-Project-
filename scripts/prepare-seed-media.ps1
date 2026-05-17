$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$sourceDir = Join-Path $root 'pictures'
$targetDir = Join-Path $root 'backend\uploads\seed'

if (-not (Test-Path $sourceDir)) {
  throw "Source pictures folder not found: $sourceDir"
}

New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

$files = @(
  @{ Source = 'Tools - Power Drill.jfif'; Target = 'tools-power-drill.jfif' },
  @{ Source = 'Tools - High-Pressure Washer.jfif'; Target = 'tools-high-pressure-washer.jfif' },
  @{ Source = 'Sports - Camping Tent.jfif'; Target = 'sports-camping-tent.jfif' },
  @{ Source = 'Sports - Bicycle.webp'; Target = 'sports-bicycle.webp' },
  @{ Source = 'Music - Marshall Speaker.jfif'; Target = 'music-marshall-speaker.jfif' },
  @{ Source = 'Music - Digital Piano.jfif'; Target = 'music-digital-piano.jfif' },
  @{ Source = 'Furniture - Foldable Table.webp'; Target = 'furniture-foldable-table.webp' },
  @{ Source = 'Furniture - Bean Bag.webp'; Target = 'furniture-bean-bag.webp' },
  @{ Source = 'Fashion - Cheongsam.jfif'; Target = 'fashion-cheongsam.jfif' },
  @{ Source = 'Fashion - Baju Kurung.jfif'; Target = 'fashion-baju-kurung.jfif' },
  @{ Source = 'Electronics - Rigal RD805A Wifi Projector.png'; Target = 'electronics-rigal-rd805a-wifi-projector.png' },
  @{ Source = 'Electronics - Laptop Intel.webp'; Target = 'electronics-laptop-intel.webp' },
  @{ Source = 'Books - The Official Cambridge Guide to IELTS.jfif'; Target = 'books-cambridge-guide-to-ielts.jfif' },
  @{ Source = 'Books - Bauhaus Architecture.jfif'; Target = 'books-bauhaus-architecture.jfif' },
  @{ Source = 'Automotive - Jump Starter.jfif'; Target = 'automotive-jump-starter.jfif' },
  @{ Source = 'Automotive - Child Car Seat.jfif'; Target = 'automotive-child-car-seat.jfif' }
)

foreach ($f in $files) {
  $src = Join-Path $sourceDir $f.Source
  $dst = Join-Path $targetDir $f.Target

  if (-not (Test-Path $src)) {
    throw "Missing source image: $src"
  }

  Copy-Item -Path $src -Destination $dst -Force
}

Write-Host "Seed media prepared in: $targetDir"
