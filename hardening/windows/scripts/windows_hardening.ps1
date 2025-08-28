param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Web", "Database", "Domain", "File")]
    [string]$ServerType,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("Low", "Medium", "High")]
    [string]$ComplianceLevel
)

$ErrorActionPreference = "Stop"
$LogFile = "C:\Logs\hardening_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

function Write-Log {
    param([string]$Message)
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$Timestamp - $Message" | Out-File -FilePath $LogFile -Append
    Write-Host $Message
}

function Set-SecurityPolicy {
    Write-Log "Configuring security policies..."
    
    $SecurityPolicy = @{
        "MinimumPasswordAge" = 1
        "MaximumPasswordAge" = 90
        "MinimumPasswordLength" = 12
        "PasswordComplexity" = 1
        "PasswordHistorySize" = 24
        "LockoutBadCount" = 5
        "ResetLockoutCount" = 15
        "LockoutDuration" = 30
    }
    
    foreach ($Policy in $SecurityPolicy.GetEnumerator()) {
        secedit /export /cfg C:\temp\secpol.cfg
        $SecPol = Get-Content C:\temp\secpol.cfg
        $SecPol = $SecPol -replace "$($Policy.Key)\s*=\s*\d+", "$($Policy.Key) = $($Policy.Value)"
        $SecPol | Out-File C:\temp\secpol.cfg
        secedit /configure /db C:\Windows\Security\Local.sdb /cfg C:\temp\secpol.cfg /areas SECURITYPOLICY
    }
    
    Write-Log "Security policies configured successfully"
}

function Disable-UnnecessaryServices {
    Write-Log "Disabling unnecessary services..."
    
    $ServicesToDisable = @(
        "TelnetServer",
        "TlntSvr",
        "TftpClient",
        "Tftp",
        "PrintSpooler",
        "Spooler",
        "RemoteRegistry",
        "RemoteRegistry",
        "SNMP",
        "SNMP",
        "W32Time",
        "W32Time"
    )
    
    foreach ($Service in $ServicesToDisable) {
        try {
            $ServiceObj = Get-Service -Name $Service -ErrorAction SilentlyContinue
            if ($ServiceObj) {
                Set-Service -Name $Service -StartupType Disabled
                Stop-Service -Name $Service -Force -ErrorAction SilentlyContinue
                Write-Log "Disabled service: $Service"
            }
        }
        catch {
            Write-Log "Warning: Could not disable service $Service - $($_.Exception.Message)"
        }
    }
}

function Configure-AuditPolicy {
    Write-Log "Configuring audit policy..."
    
    $AuditCommands = @(
        "auditpol /set /category:* /success:enable /failure:enable",
        "auditpol /set /subcategory:Logon /success:enable /failure:enable",
        "auditpol /set /subcategory:Logoff /success:enable /failure:disable",
        "auditpol /set /subcategory:Account Lockout /success:enable /failure:enable",
        "auditpol /set /subcategory:IPsec Main Mode /success:enable /failure:enable",
        "auditpol /set /subcategory:IPsec Quick Mode /success:enable /failure:enable",
        "auditpol /set /subcategory:IPsec Extended Mode /success:enable /failure:enable",
        "auditpol /set /subcategory:Special Logon /success:enable /failure:enable",
        "auditpol /set /subcategory:Other Logon/Logoff Events /success:enable /failure:enable",
        "auditpol /set /subcategory:Network Policy Server /success:enable /failure:enable"
    )
    
    foreach ($Command in $AuditCommands) {
        try {
            Invoke-Expression $Command
            Write-Log "Executed: $Command"
        }
        catch {
            Write-Log "Warning: Failed to execute $Command - $($_.Exception.Message)"
        }
    }
}

function Set-RegistrySecurity {
    Write-Log "Configuring registry security settings..."
    
    $RegistrySettings = @{
        "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\NoLMHash" = @{
            Value = 1
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\RestrictAnonymousSAM" = @{
            Value = 1
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\RestrictAnonymous" = @{
            Value = 1
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Kernel\ObCaseInsensitive" = @{
            Value = 1
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\ClearPageFileAtShutdown" = @{
            Value = 1
            Type = "DWORD"
        }
    }
    
    foreach ($Setting in $RegistrySettings.GetEnumerator()) {
        try {
            if (!(Test-Path $Setting.Key)) {
                New-Item -Path $Setting.Key -Force | Out-Null
            }
            Set-ItemProperty -Path $Setting.Key -Name $Setting.Value.Name -Value $Setting.Value.Value -Type $Setting.Value.Type
            Write-Log "Set registry: $($Setting.Key)"
        }
        catch {
            Write-Log "Warning: Could not set registry $($Setting.Key) - $($_.Exception.Message)"
        }
    }
}

function Configure-NetworkSecurity {
    Write-Log "Configuring network security settings..."
    
    $NetworkSettings = @{
        "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\EnableICMPRedirect" = @{
            Value = 0
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\EnableSecurityFilters" = @{
            Value = 1
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\DisableIPSourceRouting" = @{
            Value = 2
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\EnableDeadGWDetect" = @{
            Value = 0
            Type = "DWORD"
        }
    }
    
    foreach ($Setting in $NetworkSettings.GetEnumerator()) {
        try {
            if (!(Test-Path $Setting.Key)) {
                New-Item -Path $Setting.Key -Force | Out-Null
            }
            Set-ItemProperty -Path $Setting.Key -Name $Setting.Value.Name -Value $Setting.Value.Value -Type $Setting.Value.Type
            Write-Log "Set network setting: $($Setting.Key)"
        }
        catch {
            Write-Log "Warning: Could not set network setting $($Setting.Key) - $($_.Exception.Message)"
        }
    }
}

function Set-FirewallRules {
    Write-Log "Configuring Windows Firewall rules..."
    
    $FirewallRules = @{
        "Block-Inbound-RDP" = @{
            Direction = "Inbound"
            Action = "Block"
            Protocol = "TCP"
            LocalPort = "3389"
            Description = "Block RDP inbound connections"
        }
        "Allow-Inbound-HTTP" = @{
            Direction = "Inbound"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "80"
            Description = "Allow HTTP inbound connections"
        }
        "Allow-Inbound-HTTPS" = @{
            Direction = "Inbound"
            Action = "Allow"
            Protocol = "TCP"
            LocalPort = "443"
            Description = "Allow HTTPS inbound connections"
        }
    }
    
    foreach ($Rule in $FirewallRules.GetEnumerator()) {
        try {
            $RuleName = $Rule.Key
            $RuleConfig = $Rule.Value
            
            New-NetFirewallRule -DisplayName $RuleName `
                -Direction $RuleConfig.Direction `
                -Action $RuleConfig.Action `
                -Protocol $RuleConfig.Protocol `
                -LocalPort $RuleConfig.LocalPort `
                -Description $RuleConfig.Description
            
            Write-Log "Created firewall rule: $RuleName"
        }
        catch {
            Write-Log "Warning: Could not create firewall rule $($Rule.Key) - $($_.Exception.Message)"
        }
    }
}

function Optimize-Performance {
    Write-Log "Optimizing system performance..."
    
    $PerformanceSettings = @{
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\LargeSystemCache" = @{
            Value = 0
            Type = "DWORD"
        }
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\IoPageLockLimit" = @{
            Value = 983040
            Type = "DWORD"
        }
    }
    
    foreach ($Setting in $PerformanceSettings.GetEnumerator()) {
        try {
            if (!(Test-Path $Setting.Key)) {
                New-Item -Path $Setting.Key -Force | Out-Null
            }
            Set-ItemProperty -Path $Setting.Key -Name $Setting.Value.Name -Value $Setting.Value.Value -Type $Setting.Value.Type
            Write-Log "Set performance setting: $($Setting.Key)"
        }
        catch {
            Write-Log "Warning: Could not set performance setting $($Setting.Key) - $($_.Exception.Message)"
        }
    }
}

function Main {
    Write-Log "Starting Windows Server Hardening for $ServerType with $ComplianceLevel compliance level"
    
    try {
        Set-SecurityPolicy
        Disable-UnnecessaryServices
        Configure-AuditPolicy
        Set-RegistrySecurity
        Configure-NetworkSecurity
        Set-FirewallRules
        Optimize-Performance
        
        Write-Log "Windows Server Hardening completed successfully"
        Write-Log "Please restart the server to apply all changes"
    }
    catch {
        Write-Log "Error during hardening process: $($_.Exception.Message)"
        throw
    }
}

if (!(Test-Path "C:\Logs")) {
    New-Item -ItemType Directory -Path "C:\Logs" -Force
}

Main
