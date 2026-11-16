# =============================================================================
# YOLO NCNN Detector: Step 2 Early ADB Hardware Verification Check
# Target Hardware: Samsung Galaxy Note 10 (SM-N970U, Snapdragon 855 / msmnile)
# =============================================================================
$ErrorActionPreference = "Stop"
$expectedSerial = "R58M95PJVZT"

Write-Host "=== Phase 1 Step 2: Early ADB Hardware Verification ==="

# 1. Check ADB Availability
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    throw "FATAL: 'adb' command not found in system PATH!"
}

# 2. Query Attached Devices
$devicesOutput = & adb devices -l
Write-Host "--- adb devices -l output ---"
Write-Host $devicesOutput

# 3. Verify Serial Presence and 'device' State
$lines = ($devicesOutput -split "`r?`n") | Where-Object { $_.Trim().Length -gt 0 }
$matchedLine = $lines | Where-Object { $_ -match $expectedSerial } | Select-Object -First 1

if (-not $matchedLine) {
    Write-Host "STATUS: WAITING_FOR_PHYSICAL_DEVICE"
    throw "FATAL: Physical device with serial '$expectedSerial' is not attached! (RESTORE-4: Emulators strictly forbidden)."
}
if ($matchedLine -match '\bunauthorized\b') {
    throw "FATAL: Device '$expectedSerial' is attached but UNAUTHORIZED. Please accept the USB debugging prompt on the phone screen."
}
if ($matchedLine -match '\boffline\b') {
    throw "FATAL: Device '$expectedSerial' is OFFLINE. Please disconnect and reconnect the USB cable."
}
if ($matchedLine -notmatch '\bdevice\b') {
    throw "FATAL: Device '$expectedSerial' is in an invalid state: '$matchedLine'"
}
Write-Host "[PASS] Physical device '$expectedSerial' detected in authorized 'device' state."

# 4. Query Hardware Fingerprint Properties
$model = (& adb -s $expectedSerial shell getprop ro.product.model).Trim()
$platform = (& adb -s $expectedSerial shell getprop ro.board.platform).Trim()
$abi = (& adb -s $expectedSerial shell getprop ro.product.cpu.abi).Trim()
$androidVer = (& adb -s $expectedSerial shell getprop ro.build.version.release).Trim()
$sdkVer = (& adb -s $expectedSerial shell getprop ro.build.version.sdk).Trim()

Write-Host "[PROPERTY] Model:             $model"
Write-Host "[PROPERTY] Platform:          $platform"
Write-Host "[PROPERTY] CPU ABI:           $abi"
Write-Host "[PROPERTY] Android Release:   $androidVer (SDK API $sdkVer)"

# Assertions
if ($model -ne "SM-N970U") {
    throw "FATAL: Model mismatch! Expected 'SM-N970U', got '$model'"
}
if ($platform -ne "msmnile") {
    throw "FATAL: Platform mismatch! Expected 'msmnile' (Snapdragon 855), got '$platform'"
}
if ($abi -ne "arm64-v8a") {
    throw "FATAL: ABI mismatch! Expected 'arm64-v8a', got '$abi'"
}
Write-Host "[PASS] Hardware properties match contract: SM-N970U, msmnile, arm64-v8a."

# 5. Query Battery & Thermal State
$batteryDump = (& adb -s $expectedSerial shell dumpsys battery)
$levelMatch = [regex]::Match($batteryDump, 'level:\s*(\d+)')
$tempMatch = [regex]::Match($batteryDump, 'temperature:\s*(\d+)')
$usbMatch = [regex]::Match($batteryDump, 'USB powered:\s*(true|false)')

if ($levelMatch.Success) {
    $batteryLevel = [int]$levelMatch.Groups[1].Value
    Write-Host "[BATTERY] Level: $batteryLevel%"
    if ($batteryLevel -lt 20) {
        Write-Warning "WARNING: Battery level ($batteryLevel%) is below recommended 20% for continuous benchmarking."
    } else {
        Write-Host "[PASS] Battery level >= 20% ($batteryLevel%)."
    }
}

if ($tempMatch.Success) {
    # Temperature is reported in tenths of a degree Celsius (e.g. 296 = 29.6 C)
    $tempCelsius = [double]$tempMatch.Groups[1].Value / 10.0
    Write-Host "[THERMAL] Temperature: $tempCelsius deg C"
    if ($tempCelsius -gt 40.0) {
        Write-Warning "WARNING: Device temperature ($tempCelsius C) exceeds 40.0 C throttle boundary."
    } else {
        Write-Host "[PASS] Thermal state within nominal bounds (<= 40.0 C)."
    }
}

Write-Host "=== [SUCCESS] ALL STEP 2 EARLY ADB ASSERTIONS PASSED ==="
