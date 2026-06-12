$file = 'lib\screens\home_screen.dart'
$content = [io.file]::ReadAllText($file, [text.encoding]::UTF8)
$newContent = $content -replace '\.withOpacity\(([0-9.]+)\)', '.withValues(alpha: $1)'
[io.file]::WriteAllText($file, $newContent, [text.encoding]::UTF8)
Write-Host "Fixed withOpacity calls in $file"
