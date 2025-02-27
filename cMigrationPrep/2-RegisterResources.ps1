#Register all the resources in each subscription, so that they match
# Log in to Azure (if not already logged in)
Connect-AzAccount

# Define source and destination subscriptions
$sourceSubscription = "00000000-0000-0000-0000-000000000000"
$destinationSubscription = "00000000-0000-0000-0000-000000000000"

# Step 1: Set context to the source subscription
Set-AzContext -Subscription $sourceSubscription

# Step 2: Get all registered resource providers in the source subscription
$registeredProviders = Get-AzResourceProvider -ListAvailable | Where-Object { $_.RegistrationState -eq "Registered" }

# Step 3: Set context to the destination subscription
Set-AzContext -Subscription $destinationSubscription

# Create a log file to record errors
$errorLog = "C:\temp\ResourceProviderRegistrationErrors.log"
if (Test-Path $errorLog) { Remove-Item $errorLog }

# Step 4: Register each provider in the destination subscription
foreach ($provider in $registeredProviders) {
    try {
        Write-Host "Registering provider:" $provider.ProviderNamespace
        Register-AzResourceProvider -ProviderNamespace $provider.ProviderNamespace
    } catch {
        # Log the error to the console and a file
        $errorMessage = "Failed to register provider: $($provider.ProviderNamespace). Error: $($_.Exception.Message)"
        Write-Host $errorMessage -ForegroundColor Red
        Add-Content -Path $errorLog -Value $errorMessage
    }
}

Write-Host "All resource providers have been processed. Check the log for any errors: $errorLog"
