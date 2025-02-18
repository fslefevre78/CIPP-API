﻿using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
if ($Request.query.Permissions -eq "true") {
    Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Started permissions check" -Sev "Debug"
    $Results = try {
        $ExpectedPermissions = @(
            "Application.Read.All", "Application.ReadWrite.All", "AuditLog.Read.All", "Channel.Create", "Channel.Delete.All", "Channel.ReadBasic.All", "ChannelMember.Read.All", "ChannelMember.ReadWrite.All", "ChannelMessage.Delete", "ChannelMessage.Edit", "ChannelMessage.Read.All", "ChannelMessage.Send", "ChannelSettings.Read.All", "ChannelSettings.ReadWrite.All", "ConsentRequest.Read.All", "Device.Command", "Device.Read", "Device.Read.All", "DeviceManagementApps.ReadWrite.All", "DeviceManagementConfiguration.ReadWrite.All", "DeviceManagementManagedDevices.ReadWrite.All", "DeviceManagementRBAC.ReadWrite.All", "DeviceManagementServiceConfig.ReadWrite.All", "Directory.AccessAsUser.All", "Domain.Read.All", "Group.ReadWrite.All", "GroupMember.ReadWrite.All", "Mail.Send", "Mail.Send.Shared", "Member.Read.Hidden", "Organization.ReadWrite.All", "Policy.Read.All", "Policy.ReadWrite.AuthenticationFlows", "Policy.ReadWrite.AuthenticationMethod", "Policy.ReadWrite.Authorization", "Policy.ReadWrite.ConsentRequest", "Policy.ReadWrite.DeviceConfiguration", "PrivilegedAccess.Read.AzureResources", "PrivilegedAccess.ReadWrite.AzureResources", "Reports.Read.All", "RoleManagement.ReadWrite.Directory", "SecurityActions.ReadWrite.All", "SecurityEvents.ReadWrite.All", "ServiceHealth.Read.All", "ServiceMessage.Read.All", "Sites.ReadWrite.All", "Team.Create", "Team.ReadBasic.All", "TeamMember.ReadWrite.All", "TeamMember.ReadWriteNonOwnerRole.All", "TeamsActivity.Read", "TeamsActivity.Send", "TeamsApp.Read", "TeamsApp.Read.All", "TeamsApp.ReadWrite", "TeamsApp.ReadWrite.All", "TeamsAppInstallation.ReadForChat", "TeamsAppInstallation.ReadForTeam", "TeamsAppInstallation.ReadForUser", "TeamsAppInstallation.ReadWriteForChat", "TeamsAppInstallation.ReadWriteForTeam", "TeamsAppInstallation.ReadWriteForUser", "TeamsAppInstallation.ReadWriteSelfForChat", "TeamsAppInstallation.ReadWriteSelfForTeam", "TeamsAppInstallation.ReadWriteSelfForUser", "TeamSettings.Read.All", "TeamSettings.ReadWrite.All", "TeamsTab.Create", "TeamsTab.Read.All", "TeamsTab.ReadWrite.All", "TeamsTab.ReadWriteForChat", "TeamsTab.ReadWriteForTeam", "TeamsTab.ReadWriteForUser", "ThreatAssessment.ReadWrite.All", "UnifiedGroupMember.Read.AsGuest", "User.ManageIdentities.All", "User.Read", "User.ReadWrite.All", "UserAuthenticationMethod.Read.All", "UserAuthenticationMethod.ReadWrite", "UserAuthenticationMethod.ReadWrite.All"
        )
        $GraphPermissions = ((Get-GraphToken -returnRefresh $true).scope).split(' ') -replace "https://graph.microsoft.com/", "" | Where-Object { $_ -notin @("email", "openid", "profile", ".default") }
        $MissingPermissions = $ExpectedPermissions | Where-Object { $_ -notin $GraphPermissions } 
        if ($MissingPermissions) {
            @{ MissingPermissions = @($MissingPermissions) }
        }
        else {
            "Your Secure Application Model has all required permissions"
        }
    }
    catch {
        Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Permissions check failed: $($_) " -Sev "Error"
        "We could not connect to the API to retrieve the permissions. There might be a problem with the secure application model configuration. The returned error is: $($_.Exception.Response.StatusCode.value__ ) - $($_.Exception.Message)"
    }
}

if ($Request.query.Tenants -eq "true") {
    $Tenants = ($Request.body.tenantid).split(',')
    if (!$Tenants) { $results = "Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page." }
    $results = foreach ($tenant in $Tenants) {
        try {
            $token = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users/delta?$select=displayName' -tenantid $tenant
            @{
                TenantName = "$($Tenant)"
                Status     = "Succesfully connected" 
            }
            Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check executed succesfully" -Sev "Info"

        }
        catch {
            @{
                TenantName = "$($tenant)"
                Status     = "Failed to connect to $($_.Exception.Message)" 
            }
            Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check failed: $($_) " -Sev "Error"

        }

        try {
            $upn = "notRequired@required.com"
            $tokenvalue = ConvertTo-SecureString (Get-GraphToken -AppID 'a0c73c16-a7e3-4564-9a95-2bdf47383716' -RefreshToken $ENV:ExchangeRefreshToken -Scope 'https://outlook.office365.com/.default' -Tenantid $tenant).Authorization -AsPlainText -Force
            $credential = New-Object System.Management.Automation.PSCredential($upn, $tokenValue)
            $session = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri "https://ps.outlook.com/powershell-liveid?DelegatedOrg=$($tenant)&BasicAuthToOAuthConversion=true" -Credential $credential -Authentication Basic -AllowRedirection -ErrorAction Continue
            $session = Import-PSSession $session -ea Silentlycontinue -AllowClobber -CommandName "Get-OrganizationConfig"
            $org = Get-OrganizationConfig
            $null = Get-PSSession | Remove-PSSession
            @{ 
                TenantName = "$($Tenant)"
                Status     = "Succesfully connected to Exchange" 
            }
        }
        catch {
            $Message = ($_ | ConvertFrom-Json).error_description 
            if ($Message -eq $null) { $Message = $($_.Exception.Message) }
            @{
                TenantName = "$($Tenant)"
                Status     = "Failed to connect to Exchange: $($Message)" 
            }
            Log-Request -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Tenant access check for Exchange failed: $($Message) " -Sev "Error"
        }
    }
    if (!$Tenants) { $results = "Could not load the tenants list from cache. Please run permissions check first, or visit the tenants page." }
}

$body = [pscustomobject]@{"Results" = $Results }

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
