$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$specs = @(
  @{text='NEW'; font='Impact'; size=98; bold=$false},
  @{text='DISKON'; font='Segoe UI'; size=54; bold=$true},
  @{text='GRATIS'; font='Segoe UI'; size=32; bold=$true},
  @{text='ONGKIR'; font='Segoe UI'; size=54; bold=$true},
  @{text='REWARD'; font='Segoe UI'; size=47; bold=$true}
)
$result = @{}
foreach ($spec in $specs) {
  $font = [System.Drawing.FontFamily]::new($spec.font)
  $path = [System.Drawing.Drawing2D.GraphicsPath]::new()
  $style = if ($spec.bold) { 1 } else { 0 }
  $path.AddString($spec.text, $font, $style, $spec.size, [System.Drawing.PointF]::new(0,0), [System.Drawing.StringFormat]::GenericTypographic)
  $bounds = $path.GetBounds()
  $points = @($path.PathPoints | ForEach-Object { ,@([double]$_.X, [double]$_.Y) })
  $result[$spec.text] = @{points=$points; types=@($path.PathTypes); bounds=@($bounds.X,$bounds.Y,$bounds.Width,$bounds.Height)}
  $path.Dispose()
  $font.Dispose()
}
$result | ConvertTo-Json -Depth 8 -Compress | Set-Content -Encoding utf8 (Join-Path $PSScriptRoot 'text-outlines.json')
