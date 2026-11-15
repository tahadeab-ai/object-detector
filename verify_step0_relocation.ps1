# =============================================================================
# YOLO NCNN Detector: Step 0 Relocation & Path Space Validation
# =============================================================================
$ErrorActionPreference = "Stop"
$targetDir = "C:\dev\object-detector"

Write-Host "=== Phase 1 Step 0: Validating Monorepo Relocation & Toolchain Paths ==="

# 1. Directory Existence & Path Length (<= 30 characters)
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
    Write-Host "[CREATED] Target directory: $targetDir"
} else {
    Write-Host "[EXISTS] Target directory: $targetDir"
}

if ($targetDir.Length -gt 30) {
    throw "FATAL: Target path length ($($targetDir.Length)) exceeds 30 characters! Path: '$targetDir'"
}
Write-Host "[PASS] Workspace path length is $($targetDir.Length) <= 30 characters."

# 2. Assert Zero Spaces in Workspace and Essential SDK Toolchains
$pathsToValidate = @(
    @{ Name = "Workspace Root"; Path = $targetDir },
    @{ Name = "Android SDK"; Path = "C:\Users\O2\AppData\Local\Android\Sdk" },
    @{ Name = "Android NDK 28.2"; Path = "C:\Users\O2\AppData\Local\Android\Sdk\ndk\28.2.13676358" },
    @{ Name = "Android CMake 3.22"; Path = "C:\Users\O2\AppData\Local\Android\Sdk\cmake\3.22.1" },
    @{ Name = "Flutter SDK"; Path = "C:\src\flutter" }
)

foreach ($item in $pathsToValidate) {
    if (-not (Test-Path $item.Path)) {
        throw "FATAL: Path '$($item.Name)' does not exist at '$($item.Path)'!"
    }
    if ($item.Path -match '\s') {
        throw "FATAL: Path '$($item.Name)' at '$($item.Path)' contains whitespace characters!"
    }
    Write-Host "[PASS] $($item.Name) verified: 0 spaces, exists ($($item.Path))"
}

# 3. Verify Isolation from Parent Git Repositories
$parentGitCheck = @("C:\.git", "C:\dev\.git")
foreach ($p in $parentGitCheck) {
    if (Test-Path $p) {
        throw "FATAL: Unintended parent git repository detected at '$p'!"
    }
}
Write-Host "[PASS] Workspace is clean: no parent git repositories exist above $targetDir."

# 4. Verify Read / Write / Create / Delete Permissions
$testGuid = [Guid]::NewGuid().ToString('N')
$testFilePath = Join-Path $targetDir ".perm_test_$testGuid"
try {
    [IO.File]::WriteAllText($testFilePath, "permissions_verified_ok")
    if (-not (Test-Path $testFilePath)) {
        throw "Verification test file failed to write."
    }
    $readContent = [IO.File]::ReadAllText($testFilePath)
    if ($readContent -ne "permissions_verified_ok") {
        throw "Verification test file read content mismatch."
    }
    Remove-Item -Path $testFilePath -Force
    Write-Host "[PASS] File system permissions verified (Read/Write/Create/Delete)."
} catch {
    throw "FATAL: File system permissions check failed in ${targetDir}: $_"
}

Write-Host "=== [SUCCESS] ALL STEP 0 RELOCATION ASSERTIONS PASSED ==="
