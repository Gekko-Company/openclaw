# OpenClaw: Build image and push to Harbor (harbor.gekko.company/openclaw)
# Usage:
#   .\deploy-harbor.ps1              # build and push only
#   .\deploy-harbor.ps1 -RunLocally # build, push, then run container locally (for testing)

param(
    [switch]$RunLocally = $false,
    [string]$ImageTag = "latest"
)

$HARBOR_REGISTRY = "harbor.gekko.company"
$HARBOR_PROJECT = "openclaw"
$IMAGE_NAME = "${HARBOR_REGISTRY}/${HARBOR_PROJECT}/openclaw:${ImageTag}"
$LOCAL_IMAGE = "openclaw:vps"
$DOCKERFILE = "Dockerfile.vps"

# Ensure we're in the script directory (repo root)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Resolve Dockerfile and ensure Docker can read it (OneDrive placeholders can appear as ~35B to Docker)
$DockerfilePath = Join-Path -Path $ScriptDir -ChildPath $DOCKERFILE
if (-not (Test-Path -LiteralPath $DockerfilePath)) {
    Write-Host "Dockerfile not found: $DockerfilePath" -ForegroundColor Red
    exit 1
}
$minDockerfileBytes = 200
$dockerfileSize = (Get-Item -LiteralPath $DockerfilePath).Length
if ($dockerfileSize -lt $minDockerfileBytes) {
    Write-Host "Dockerfile appears too small ($dockerfileSize bytes). If using OneDrive, set this folder to 'Always keep on this device' and retry." -ForegroundColor Red
    exit 1
}

# Copy Dockerfile to temp so Docker daemon reads full content (avoids OneDrive placeholder / path issues)
$TempDockerfile = Join-Path -Path $env:TEMP -ChildPath "Dockerfile.vps.openclaw"
Copy-Item -LiteralPath $DockerfilePath -Destination $TempDockerfile -Force

# Check if Docker is installed and running
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker is not installed or not found in PATH." -ForegroundColor Red
    exit 1
}

# Build the image (Dockerfile from temp so daemon gets full content; context remains repo root)
Write-Host "Building image with $DOCKERFILE..." -ForegroundColor Cyan
docker build -f $TempDockerfile -t $LOCAL_IMAGE .
$buildExit = $LASTEXITCODE
if (Test-Path -LiteralPath $TempDockerfile) { Remove-Item -LiteralPath $TempDockerfile -Force }
if ($buildExit -ne 0) {
    Write-Host "Image build failed!" -ForegroundColor Red
    exit 1
}

Write-Host "Build succeeded. Tagging for Harbor..." -ForegroundColor Green
docker tag "${LOCAL_IMAGE}" $IMAGE_NAME

# Login to Harbor (will prompt for username/password if not already logged in)
Write-Host "Logging in to $HARBOR_REGISTRY (if needed)..." -ForegroundColor Cyan
docker login $HARBOR_REGISTRY

if ($LASTEXITCODE -ne 0) {
    Write-Host "Docker login failed!" -ForegroundColor Red
    exit 1
}

# Push to Harbor
Write-Host "Pushing image to $IMAGE_NAME ..." -ForegroundColor Cyan
docker push $IMAGE_NAME

if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to push image!" -ForegroundColor Red
    exit 1
}

Write-Host "Image pushed successfully: $IMAGE_NAME" -ForegroundColor Green

# Optionally run container locally (e.g. for quick test)
if ($RunLocally) {
    Write-Host "Running container locally (port 18789)..." -ForegroundColor Cyan
    $ConfigDir = if ($env:OPENCLAW_CONFIG_DIR) { $env:OPENCLAW_CONFIG_DIR } else { "$env:USERPROFILE\.openclaw" }
    $WorkspaceDir = if ($env:OPENCLAW_WORKSPACE_DIR) { $env:OPENCLAW_WORKSPACE_DIR } else { "$env:USERPROFILE\.openclaw\workspace" }
    if (-not (Test-Path $ConfigDir)) { New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null }
    if (-not (Test-Path $WorkspaceDir)) { New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null }
    $Token = if ($env:OPENCLAW_GATEWAY_TOKEN) { $env:OPENCLAW_GATEWAY_TOKEN } else { "dev-token-change-me" }
    docker run -d `
        --name openclaw-gateway `
        -p 18789:18789 `
        -v "${ConfigDir}:/home/node/.openclaw" `
        -v "${WorkspaceDir}:/home/node/.openclaw/workspace" `
        -e "OPENCLAW_GATEWAY_TOKEN=$Token" `
        $IMAGE_NAME
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Container running. Control UI: http://localhost:18789/" -ForegroundColor Green
    } else {
        Write-Host "Failed to run container (e.g. name already in use: docker rm -f openclaw-gateway)" -ForegroundColor Yellow
    }
}
