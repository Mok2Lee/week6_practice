# 목적: Windows가 이미 신뢰하는 학교 CA 인증서를 Minikube 노드에서도 신뢰하도록 등록합니다.
# CA는 HTTPS 서버 인증서의 발급자를 확인하는 기준이 되는 인증 기관입니다.
# 이 학교 PC에서는 Plantynet 보안 프로그램의 CA가 필요했습니다.
# minikube start 전에 실행할 수 있습니다. 노드가 아직 없어도 인증서 준비는 완료됩니다.
# -PrepareOnly를 지정하면 Docker나 실행 중인 노드 없이 인증서 저장까지만 수행합니다.
# 전체 흐름: 입력 검사 -> 학교 CA 찾기 -> 시작용 CA 저장 -> 실행 중인 노드가 있으면 적용/확인.
# Windows/Docker가 수행하는 다운로드는 해당 환경의 신뢰 설정을 사용합니다.
# 이 스크립트는 Windows에 이미 등록된 학교 CA를 Minikube 노드에 전달할 준비를 합니다.

# 1. 실행할 때 지정할 수 있는 입력값입니다. 생략하면 아래 기본값을 사용합니다.
# 예: .\Fix-SchoolMinikube.ps1 -Profile week6 -CaThumbprint '확인한 인증서 지문'
param(
    # 인증서를 적용할 Minikube 프로필 이름입니다. Docker 노드 컨테이너 이름으로도 사용합니다.
    [string]$Profile = 'week6',
    # 이 PC에서 확인한 학교 CA의 SHA-1 지문입니다. 원하는 인증서를 정확히 찾는 식별자입니다.
    # 다른 학교/PC에서는 CA 지문이 다를 수 있으므로 실제 인증서를 확인해야 합니다.
    [string]$CaThumbprint = '47A677A1828522E2EF3C28876D7E7482BB164A9D',
    # Minikube를 처음 시작하기 전에는 이 옵션으로 CA 파일만 미리 준비할 수 있습니다.
    [switch]$PrepareOnly
)

# 2. PowerShell 명령에서 오류가 발생하면 진행을 중단합니다.
# docker 같은 외부 프로그램의 실패는 아래에서 $LASTEXITCODE로 별도 검사합니다.
$ErrorActionPreference = 'Stop'

# 프로필 이름이 영문/숫자로 시작하고, 이후 영문/숫자/밑줄/점/하이픈만 포함하는지 검사합니다.
# -notmatch는 정규식과 일치하지 않는다는 뜻이고, throw는 오류를 내며 실행을 중단합니다.
if ($Profile -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_.-]*$') {
    throw 'Invalid minikube profile name.'
}

# 인증서 지문이 16진수 문자 40개로 된 SHA-1 지문 형식인지 검사합니다.
if ($CaThumbprint -notmatch '^[a-fA-F0-9]{40}$') {
    throw 'Expected the thumbprint of the verified school root CA.'
}

# 3. Windows의 '신뢰할 수 있는 루트 인증 기관' 저장소에서 학교 CA를 찾습니다.
# Cert:\LocalMachine\Root: PC 전체에 적용되는 루트 인증서 저장소.
# Cert:\CurrentUser\Root: 현재 Windows 사용자에게 적용되는 루트 인증서 저장소.
# |는 왼쪽 결과를 오른쪽 명령에 전달합니다.
# Where-Object는 지문이 일치하는 인증서만 고르고, Select-Object는 첫 번째 결과를 선택합니다.
# Windows가 이미 신뢰하는 CA를 재사용하며 Windows 인증서 저장소에는 새 CA를 추가하지 않습니다.
$certificate = Get-ChildItem -Path 'Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root' |
    Where-Object Thumbprint -EQ $CaThumbprint | Select-Object -First 1

# 해당 지문의 인증서가 없으면 임의의 다른 인증서를 사용하는 대신 중단합니다.
if (-not $certificate) { throw 'The verified CA is not in the Windows root store.' }

# NotBefore는 유효 기간 시작, NotAfter는 만료 시각입니다. 현재 시각이 범위 안인지 확인합니다.
if ($certificate.NotBefore -gt (Get-Date) -or $certificate.NotAfter -lt (Get-Date)) {
    throw 'The school CA is outside its validity period.'
}

# 2.5.29.19는 인증서의 Basic Constraints 확장을 식별하는 OID입니다.
# 이 확장의 CertificateAuthority 값으로 다른 인증서를 발급할 수 있는 CA인지 확인합니다.
$constraints = $certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' }
if (-not $constraints -or -not $constraints.CertificateAuthority) {
    throw 'The selected certificate is not a CA certificate.'
}

# 4. 학교 CA의 공개 인증서를 이 스크립트와 같은 폴더에 저장합니다.
# $PSScriptRoot는 스크립트가 있는 폴더이고, Join-Path는 폴더와 파일명을 연결합니다.
$certificateFile = Join-Path $PSScriptRoot 'plantynet-school-ca.crt'

# Cert 형식으로 내보내면 공개 인증서 데이터만 복사됩니다. 개인 키는 내보내지 않습니다.
$bytes = $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)

# 바이너리 인증서 데이터를 Base64로 바꾸고 BEGIN/END 표시를 붙여 PEM 텍스트를 만듭니다.
# `n은 줄바꿈이며, InsertLineBreaks는 Base64 내용을 여러 줄로 나누는 옵션입니다.
# 여기서 사용하는 .crt 파일과 아래 .pem 파일은 확장자만 다르고 같은 PEM 내용을 담습니다.
$pem = "-----BEGIN CERTIFICATE-----`n" +
    [Convert]::ToBase64String($bytes, [Base64FormattingOptions]::InsertLineBreaks) +
    "`n-----END CERTIFICATE-----`n"

# PEM에 필요한 문자는 ASCII로 표현할 수 있습니다. 파일이 이미 있으면 내용을 덮어씁니다.
[IO.File]::WriteAllText($certificateFile, $pem, [Text.Encoding]::ASCII)

# 5. Minikube가 처음 시작하거나 재시작할 때 읽을 인증서 폴더를 찾습니다.
# $env:USERPROFILE은 Windows 사용자 폴더이며 기본 위치는 C:\Users\사용자\.minikube입니다.
$minikubeRoot = Join-Path $env:USERPROFILE '.minikube'

# MINIKUBE_HOME 환경 변수가 설정되어 있으면 그 사용자 지정 위치를 사용합니다.
# 지정한 경로의 마지막 폴더가 .minikube가 아니면 Minikube 방식에 맞게 .minikube를 붙입니다.
if ($env:MINIKUBE_HOME) {
    $minikubeRoot = $env:MINIKUBE_HOME
    if ((Split-Path $minikubeRoot -Leaf) -ne '.minikube') {
        $minikubeRoot = Join-Path $minikubeRoot '.minikube'
    }
}

# .minikube\certs에 저장한 CA는 이후 minikube start가 노드 내부로 복사해 등록합니다.
$certDirectory = Join-Path $minikubeRoot 'certs'

# -Force는 폴더가 이미 있어도 사용할 수 있게 하고, Out-Null은 폴더 생성 결과 출력을 숨깁니다.
New-Item -ItemType Directory -Path $certDirectory -Force | Out-Null
$persistentFile = Join-Path $certDirectory 'plantynet-school-ca.pem'

# -LiteralPath는 경로를 와일드카드 없이 그대로 취급합니다. -Force는 같은 이름의 파일을 덮어씁니다.
Copy-Item -LiteralPath $certificateFile -Destination $persistentFile -Force
Write-Output "Saved verified public CA: $persistentFile"

# 인증서가 저장된 다음에 실행할 수업용 시작 명령을 안내합니다. 여기서 직접 시작하지는 않습니다.
# --preload=false는 이 PC에서 발견한 사전 다운로드 캐시 오류를 피하는 옵션입니다.
# 노드 내부 이미지 다운로드에 필요한 CA는 위 certs 폴더에서 minikube start가 읽습니다.
Write-Output 'CA preparation completed. Run these commands to start the lecture cluster:'
Write-Output "minikube profile $Profile"
Write-Output "minikube start -p $Profile --driver=docker --container-runtime=containerd --ports=8080:30080 --kubernetes-version=v1.35.0 --cpus=2 --memory=3072 --preload=false"

# 준비만 요청했다면 정상적으로 종료합니다. 노드가 존재할 필요가 없습니다.
# return은 현재 스크립트를 종료하며, 인증서 검사/저장 단계에 오류가 없었으면 준비 성공입니다.
if ($PrepareOnly) { return }

# 6. 이미 실행 중인 노드가 있으면 아래 단계에서 즉시 CA를 적용합니다.
# Docker 명령이 설치되지 않았어도 시작 전 인증서 준비는 완료된 상태로 종료합니다.
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Output 'CA is prepared. Install/start Docker Desktop before starting Minikube.'
    return
}

# &는 뒤의 프로그램을 실행하는 연산자입니다.
# docker container ls는 실행 중인 컨테이너만 조회하고, --format은 이름만 출력합니다.
# @()는 결과가 0개/1개/여러 개여도 배열로 취급하도록 만듭니다.
# $LASTEXITCODE는 외부 프로그램의 종료 코드입니다. 일반적으로 0이면 성공입니다.
try {
    $runningContainers = @(& docker container ls --format '{{.Names}}')
    if ($LASTEXITCODE -ne 0) { throw 'Docker engine could not be queried.' }
} catch {
    Write-Warning 'CA is prepared. Docker is unavailable; start Docker Desktop before Minikube.'
    return
}

# -notcontains는 목록에 대상 이름이 없는지 검사합니다.
# 노드가 없거나 중지되어 있으면 정상 종료합니다. 이후 start할 때 준비한 CA가 자동 등록됩니다.
if ($runningContainers -notcontains $Profile) {
    Write-Output "Node '$Profile' is not running. Pre-start CA preparation succeeded."
    return
}

# 7. 지금 실행 중인 노드에도 CA를 적용합니다.
# docker cp는 PC의 파일을 컨테이너로 복사합니다. 목적지는 Linux의 추가 CA 등록 폴더입니다.
# ${Profile}처럼 중괄호를 쓰면 변수 이름과 뒤의 ':'를 명확히 구분할 수 있습니다.
& docker cp $certificateFile "${Profile}:/usr/local/share/ca-certificates/plantynet-school-ca.crt"
if ($LASTEXITCODE -ne 0) { throw 'Failed to copy the public CA into the node.' }

# docker exec는 실행 중인 컨테이너 안에서 명령을 실행합니다.
# update-ca-certificates는 추가한 CA를 Linux의 인증서 묶음과 인증서 조회 경로에 반영합니다.
& docker exec $Profile update-ca-certificates
if ($LASTEXITCODE -ne 0) { throw 'Failed to update the node trust store.' }

# containerd는 노드 안에서 이미지 다운로드와 컨테이너 실행을 담당하는 서비스입니다.
# 새 CA를 읽도록 서비스를 재시작합니다. Docker Desktop 전체를 재시작하는 명령은 아닙니다.
& docker exec $Profile systemctl restart containerd
if ($LASTEXITCODE -ne 0) { throw 'Failed to restart containerd.' }

# 8. 노드 내부에서 Kubernetes 이미지 저장소와 Docker Hub에 HTTPS로 접속해 검증합니다.
# curl 옵션 설명:
# --silent: 다운로드 진행 표시를 숨깁니다.
# --show-error: silent 상태에서도 실패 원인은 출력합니다.
# --output /dev/null: 응답 본문은 버리고 HTTP 상태 코드만 확인합니다.
# --write-out: 접속한 저장소 이름과 HTTP 상태 코드를 출력합니다.
# %{http_code}: curl이 실제 HTTP 상태 코드로 치환하는 값입니다.
# '\n': PowerShell이 그대로 전달하면 curl이 출력할 때 줄바꿈으로 처리합니다.
# --connect-timeout 5: 연결 수립에 최대 5초를 기다립니다.
# --max-time 20: 요청 전체를 최대 20초로 제한합니다.
# 인증서 검증을 끄는 옵션은 사용하지 않으므로 CA 신뢰가 해결되지 않으면 curl이 실패합니다.
& docker exec $Profile curl --silent --show-error --output /dev/null --write-out 'registry.k8s.io HTTP %{http_code}\n' --connect-timeout 5 --max-time 20 https://registry.k8s.io/v2/
if ($LASTEXITCODE -ne 0) { throw 'Node HTTPS validation still fails.' }

# Docker Hub에도 같은 방식으로 접속합니다. /v2/는 컨테이너 이미지 저장소 API의 기본 경로입니다.
# HTTP 401은 이 요청에 로그인이 필요하다는 응답이며, HTTPS 인증서 오류와는 다릅니다.
# 이 검사는 HTTP 성공 코드 여부가 아니라 TLS 검증과 서버 응답 수신 여부를 확인합니다.
& docker exec $Profile curl --silent --show-error --output /dev/null --write-out 'Docker Hub HTTP %{http_code}\n' --connect-timeout 5 --max-time 20 https://registry-1.docker.io/v2/
if ($LASTEXITCODE -ne 0) { throw 'Node Docker Hub HTTPS validation still fails.' }

# 두 저장소와의 HTTPS 통신이 성공하면 완료 메시지를 출력합니다.
# 이후 노드 Ready 여부는 kubectl --context=week6 get nodes로 확인할 수 있습니다.
Write-Output 'School CA installed. TLS certificate validation remains enabled.'
