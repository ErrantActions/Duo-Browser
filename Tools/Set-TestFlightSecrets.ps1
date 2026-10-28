param(
    [Parameter(Mandatory = $true)]
    [string]$CertificatePath,
    [Parameter(Mandatory = $true)]
    [string]$ApiKeyPath,
    [string]$ProfilePath = (Join-Path $env:LOCALAPPDATA 'DuoBrowser\Signing\Duo_Browser_App_Store.mobileprovision'),
    [string]$KeyId,
    [string]$IssuerId
)

$ErrorActionPreference = 'Stop'
$repository = 'ErrantActions/Duo-Browser'
$teamId = 'QM3794NUZS'
$bundleId = 'com.errantactions.duobrowser'
$openssl = Join-Path $env:ProgramFiles 'Git\usr\bin\openssl.exe'
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if ($ghCommand) {
    $gh = $ghCommand.Source
} else {
    $install = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs') -Directory -Filter 'GitHubCLI-*' |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $install) { throw 'Install and authenticate the official GitHub CLI first.' }
    $gh = Join-Path $install.FullName 'bin\gh.exe'
}
if (-not (Test-Path -LiteralPath $openssl -PathType Leaf)) {
    throw 'Install Git for Windows with its OpenSSL tool before continuing.'
}
foreach ($path in @($CertificatePath, $ApiKeyPath, $ProfilePath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required signing file does not exist: $path"
    }
}

function Invoke-PrivateProcess {
    param(
        [string]$Executable,
        [string]$Arguments,
        [AllowNull()][string]$InputValue
    )
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = $Arguments
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    try {
        if (-not $process.Start()) { throw 'The signing setup process could not start.' }
        $output = $process.StandardOutput.ReadToEndAsync()
        $errors = $process.StandardError.ReadToEndAsync()
        if ($null -ne $InputValue) { $process.StandardInput.Write($InputValue) }
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(120000)) {
            $process.Kill()
            throw 'The signing setup command timed out.'
        }
        if ($process.ExitCode -ne 0) {
            # Do not echo native output: a future CLI version could include submitted secrets.
            throw "Signing setup command failed (exit $($process.ExitCode)). Check file paths, password, and GitHub access."
        }
        $null = $errors.GetAwaiter().GetResult()
        return $output.GetAwaiter().GetResult()
    } finally {
        $process.Dispose()
    }
}

function Set-Secret {
    param([string]$Name, [string]$Value)
    $null = Invoke-PrivateProcess $gh "secret set $Name --repo $repository --env app-store" $Value
    Write-Host "Configured encrypted GitHub secret: $Name"
}

$password = $null
$previousPassword = [Environment]::GetEnvironmentVariable('DUO_P12_PASSWORD', 'Process')
try {
    $null = Invoke-PrivateProcess $gh 'auth status --hostname github.com' $null
    $environment = Invoke-PrivateProcess $gh "api repos/$repository/environments/app-store" $null |
        ConvertFrom-Json
    if (-not $environment.deployment_branch_policy.custom_branch_policies) {
        throw 'Configure the app-store environment with a selected main-branch deployment policy first.'
    }
    $policies = Invoke-PrivateProcess $gh "api repos/$repository/environments/app-store/deployment-branch-policies" $null |
        ConvertFrom-Json
    if ($policies.total_count -ne 1 -or $policies.branch_policies[0].name -ne 'main' -or
        $policies.branch_policies[0].type -ne 'branch') {
        throw 'The app-store environment must allow only the main branch.'
    }

    $resolvedProfile = (Get-Item -LiteralPath $ProfilePath).FullName
    $profileXML = Invoke-PrivateProcess $openssl "cms -verify -inform DER -in `"$resolvedProfile`" -noverify" $null
    $profile = [xml]$profileXML
    $app = $profile.SelectSingleNode("/plist/dict/key[text()='Entitlements']/following-sibling::dict[1]/key[text()='application-identifier']/following-sibling::string[1]")
    $expiry = $profile.SelectSingleNode("/plist/dict/key[text()='ExpirationDate']/following-sibling::date[1]")
    $devices = $profile.SelectSingleNode("/plist/dict/key[text()='ProvisionedDevices']")
    $enterprise = $profile.SelectSingleNode("/plist/dict/key[text()='ProvisionsAllDevices']/following-sibling::*[1]")
    $debug = $profile.SelectSingleNode("/plist/dict/key[text()='Entitlements']/following-sibling::dict[1]/key[text()='get-task-allow']/following-sibling::*[1]")
    if ($null -eq $app -or $app.InnerText -ne "$teamId.$bundleId" -or $null -eq $expiry -or
        [DateTimeOffset]::Parse($expiry.InnerText) -le [DateTimeOffset]::UtcNow -or
        $null -ne $devices -or $enterprise.Name -eq 'true' -or $debug.Name -eq 'true') {
        throw 'The profile is expired, is not App Store distribution, or does not match Duo Browser.'
    }

    if ([string]::IsNullOrWhiteSpace($KeyId)) {
        $match = [regex]::Match((Split-Path -Leaf $ApiKeyPath), '^AuthKey_([A-Z0-9]+)\.p8$')
        if ($match.Success) { $KeyId = $match.Groups[1].Value }
        else { $KeyId = Read-Host 'Existing App Store Connect team API Key ID' }
    }
    if ([string]::IsNullOrWhiteSpace($IssuerId)) {
        $IssuerId = Read-Host 'Existing App Store Connect team API Issuer ID'
    }
    if ($KeyId -notmatch '^[A-Z0-9]+$' -or
        $IssuerId -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$') {
        throw 'Invalid team API key identifier or issuer identifier.'
    }

    $secure = Read-Host 'Existing distribution P12 password (not sent to chat)' -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        $secure.Dispose()
    }
    if ([string]::IsNullOrWhiteSpace($password)) { throw 'A P12 password is required.' }
    $env:DUO_P12_PASSWORD = $password
    $resolvedCertificate = (Get-Item -LiteralPath $CertificatePath).FullName
    $null = Invoke-PrivateProcess $openssl "pkcs12 -in `"$resolvedCertificate`" -passin env:DUO_P12_PASSWORD -noout" $null
    Remove-Item Env:DUO_P12_PASSWORD

    $null = Invoke-PrivateProcess $gh "variable set APP_BUNDLE_ID --body $bundleId --repo $repository --env app-store" $null
    $null = Invoke-PrivateProcess $gh "variable set APPLE_TEAM_ID --body $teamId --repo $repository --env app-store" $null
    Set-Secret 'DISTRIBUTION_CERTIFICATE_BASE64' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($CertificatePath)))
    Set-Secret 'DISTRIBUTION_CERTIFICATE_PASSWORD' $password
    Set-Secret 'PROVISIONING_PROFILE_BASE64' ([Convert]::ToBase64String([IO.File]::ReadAllBytes($ProfilePath)))
    Set-Secret 'APP_STORE_CONNECT_KEY_ID' $KeyId
    Set-Secret 'APP_STORE_CONNECT_ISSUER_ID' $IssuerId
    Set-Secret 'APP_STORE_CONNECT_PRIVATE_KEY' ([IO.File]::ReadAllText($ApiKeyPath))
    Write-Host 'Duo Browser signing is configured. No Apple upload has been triggered.'
} finally {
    [Environment]::SetEnvironmentVariable('DUO_P12_PASSWORD', $previousPassword, 'Process')
    $password = $null
}
