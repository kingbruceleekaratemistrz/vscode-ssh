<#
.SYNOPSIS
    Konfiguracja połączenina programu Visual Studio Code poprzez ssh.
.NOTES
    Skrypt wymaga praw Administratora
.LINK
    username regex: https://www.unix.com/man-page/linux/8/useradd/
#>
#Requires -RunAsAdministrator

param (
    [string]$server,
    [string]$user,
    [string]$keyFile
)

function Export-key ([string]$keyPath, [string]$user, [string]$server) {
    $key = Get-Content $keyPath
    $cmd = "umask 077; mkdir -p .ssh; grep -Fq '$key' .ssh/authorized_keys || cat >> .ssh/authorized_keys"
    try {
        if (-not $user) {
            $user = Read-Host "Specify username for ssh connection (leave blank for: $env:UserName)"
            if (-not $user) { $user = $env:UserName }
        }

        $key | ssh $server -l $user $cmd
    }
    catch {
        Write-Error "Something went wrong with key export."
    }
}

function Install-choco {
    Set-ExecutionPolicy Bypass -Scope Process -Force
    
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-WebRequest https://community.chocolatey.org/install.ps1 -UseBasicParsing | Invoke-Expression
    RefreshEnv.cmd

    choco.exe -v
}

function Set-vscode-path {
    $userKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $true)
    $userPath = $userKey.GetValue('PATH', [string]::Empty, 'DoNotExpandEnvironmentNames').ToString()

    $machineKey = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\ControlSet001\Control\Session Manager\Environment\', $true)
    $machinePath = $machineKey.GetValue('PATH', [string]::Empty, 'DoNotExpandEnvironmentNames').ToString()

    $backupPATHs = @(
        "User PATH: $userPath"
        "Machine PATH: $machinePath"
    )
    $backupFile = "C:\PATH_backups.txt"
    $backupPATHs | Set-Content -Path $backupFile -Encoding UTF8 -Force

    if (-not $userPath -like "*C:\Program Files\Microsoft VS Code*") {
        Write-Verbose "Adding VSCode location to User Path."

        $newUserPATH = $userPath+[System.IO.Path]::PathSeparator+"C:\Program Files\Microsoft VS Code\bin"

        $userKey.SetValue('PATH', $newUserPATH, 'ExpandString')
    }

    if (-not $machinePath -like "*C:\Program Files\Microsoft VS Code*") {
        Write-Verbose "Adding VSCode location to Machine Path."

        $newMachinePATH = $machinePath+[System.IO.Path]::PathSeparator+"C:\Program Files\Microsoft VS Code\bin"
        
        $machineKey.SetValue('PATH', $newMachinePATH, 'ExpandString')
    }
}

function Install-vscode {
    choco.exe install vscode -y
    
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 
    Set-vscode-path

    code --version
    code --install-extension ms-vscode-remote.remote-ssh
}

# START

if (-not $server) {
    Write-Output "help!"
    exit
}

if ($user -and ($server -match "@") -and ($user -ne $server.Split("@")[0])) {
    Write-Error "Two diffrent usernames provided."
    exit
}

if ($server -match "@") {
    $user = $server.Split("@")[0]
    $server = $server.Split("@")[1]
}

if (-not ($server -as [System.Net.IPAddress] -as [Bool])) {
        try {
            $addressFromDns = Resolve-DnsName -Name $server -ErrorAction Stop
            $server = $addressFromDns.IPAddress
        }
        catch {
            Write-Error "Given server address is neither valid IPv4 address nor valid dns name."
            exit
        }
    }

if ($keyFile) {
    if (-not (Test-Path $keyFile)) {
        Write-Error "$keyFile does not exists."
        exit
    }
}
else {
    $confirmation = Read-Host "Do you want to generate new pair of keys? ([Y]es/[N]o)"
    while ($confirmation -ne "Y" -and $confirmation -ne "y" -and $confirmation -ne "N" -and $confirmation -ne "n") {
        $confirmation = Read-Host "Do you want to generate new pair of keys? ([Y]es/[N]o)"
    }

    if ($confirmation -eq "Y" -or $confirmation -eq "y") {
        $keyPath = Read-Host "Enter file in which to save the key ($HOME/.ssh/id_rsa):"
        if (-not $keyPath) { $keyPath = "$HOME/.ssh/id_rsa" }
        Write-Verbose "Generating pair of RSA 2048 keys..."
        ssh-keygen.exe -t RSA -b 2048 -C '""' -f "$keyPath" -N '""'
        $keyFile = "$keyPath.pub"
    }
}

if ($keyFile) {
    Export-key $keyFile $user $server
}

Install-choco

Install-vscode


# Eof