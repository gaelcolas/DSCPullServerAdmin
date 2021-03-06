if (
    $env:ProjectName -and $ENV:ProjectName.Count -eq 1 -and
    $env:BuildSystem -eq 'AppVeyor'
) {

    if (!$Env:APPVEYOR_PULL_REQUEST_NUMBER -and 
        $Env:BuildSystem -eq 'AppVeyor' -and 
        $Env:BranchName -eq 'master' -and 
        $Env:NuGetApiKey -and
        $Env:GitHubKey -and
        $Env:CommitMessage -match '!Deploy'
    ) {
        $manifest = Import-PowerShellDataFile -Path ".\$Env:ProjectName\$Env:ProjectName.psd1"
        $manifest.RequiredModules | ForEach-Object {
            if ([string]::IsNullOrEmpty($_)) {
                return
            }
            $ReqModuleName = ([Microsoft.PowerShell.Commands.ModuleSpecification]$_).Name
            $InstallModuleParams = @{Name = $ReqModuleName}
            if ($ReqModuleVersion = ([Microsoft.PowerShell.Commands.ModuleSpecification]$_).RequiredVersion) {
                $InstallModuleParams.Add('RequiredVersion', $ReqModuleVersion)
            }
            Install-Module @InstallModuleParams -Force
        }

        Deploy Module {
            By PSGalleryModule {
                FromSource $(Get-Item ".\BuildOutput\$Env:ProjectName")
                To PSGallery
                WithOptions @{
                    ApiKey = $Env:NuGetApiKey
                }
            }
        }

        #TODO: Replace with PSDeploy Script
        Write-Host "Creating GitHub release" -ForegroundColor Green
        $updatedManifest = Import-PowerShellDataFile .\BuildOutput\$Env:ProjectName\$Env:ProjectName.psd1

        $releaseData = @{
            tag_name = '{0}' -f $updatedManifest.ModuleVersion
            target_commitish = $ENV:APPVEYOR_REPO_COMMIT
            name = '{0}' -f $updatedManifest.ModuleVersion
            body = $updatedManifest.PrivateData.PSData.ReleaseNotes
            draft = $false
            prerelease = $false
        }

        $releaseParams = @{
            Uri = "https://api.github.com/repos/$ENV:APPVEYOR_REPO_NAME/releases?access_token=$Env:GitHubKey"
            Method = 'POST'
            ContentType = 'application/json'
            Body = (ConvertTo-Json $releaseData -Compress)
            UseBasicParsing = $true
        }
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $newRelease = Invoke-RestMethod @releaseParams

        Compress-Archive -DestinationPath ".\BuildOutput\DSCPullServerAdmin_$($updatedManifest.ModuleVersion).zip" -Path .\BuildOutput\$Env:ProjectName\*.*

        $uploadParams = @{
            Uri = ($newRelease.upload_url -replace '\{\?name.*\}', '?name=DSCPullServerAdmin_') +
                $updatedManifest.ModuleVersion +
                '.zip&access_token=' +
                $Env:GitHubKey
            Method = 'POST'
            ContentType = 'application/zip'
            InFile = ".\BuildOutput\DSCPullServerAdmin_$($updatedManifest.ModuleVersion).zip"
        }

        $null = Invoke-RestMethod @uploadParams
    }

    Deploy AppveyorDeployment {
        By AppVeyorModule {
            FromSource .\BuildOutput\$Env:ProjectName\$Env:ProjectName.psd1
            To AppVeyor
            WithOptions @{
                Version = $Env:APPVEYOR_BUILD_VERSION
                PackageName = $Env:ProjectName
                Description = 'Get data from your DSC Pull Server database'
                Author = "Ben Gelens"
                Owners = "Ben Gelens"
            }
            Tagged Appveyor
        }
    }
} else {
    Write-Host "Not In AppVeyor. Skipped"
}
