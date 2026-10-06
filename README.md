# 6주차 요청 발생기

이 프로젝트는 **Docker Compose로 실행하는 요청 발생기**입니다. 슬라이더로 요청량을 바꾸고, 별도 [week6_kubernetes](https://github.com/Mok2Lee/week6_kubernetes)의 API Pod 수를 관찰합니다.

## 프로젝트와 터미널

| 터미널 | 작업 폴더 | 역할 |
| --- | --- | --- |
| **A — 요청 발생기** | `C:\week6_practice` | 이 프로젝트의 Compose 실행 |
| **B — Kubernetes** | `C:\week6_kubernetes` | 이미지 빌드·Kubernetes 배포·HPA 확인 |

전체 순서는 [학생 실습 안내](https://github.com/Mok2Lee/week6_kubernetes/blob/main/docs/student-lab.md)를 따릅니다.

## 0. 학교 PC 인증서 준비 — Minikube 노드 생성 전

학교 네트워크에서 Minikube 구성요소를 받을 때 `x509: certificate signed by unknown authority`가 발생할 수 있습니다. **Minikube를 시작하기 전에** 이 저장소의 [Fix-SchoolMinikube.ps1](Fix-SchoolMinikube.ps1)로 학교 CA를 준비합니다. Docker Desktop을 실행하고, 터미널 B에서 아래 명령을 실행합니다.

```powershell
cd C:\week6_practice
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Fix-SchoolMinikube.ps1 -PrepareOnly
```

**확인:** `CA preparation completed`가 표시됩니다. 이 단계는 Minikube 노드가 없어도 실행됩니다. Windows에 이미 등록된 학교 CA의 공개 인증서를 사용자 폴더의 `.minikube\certs`에 저장하며, `minikube start`가 노드에 등록합니다. `-PrepareOnly`는 인증서 준비까지만 수행합니다. `-ExecutionPolicy Bypass`는 이번 PowerShell 실행에만 적용됩니다.

현재 기본값은 이 학교에서 확인한 Plantynet CA 지문 `47A677A1828522E2EF3C28876D7E7482BB164A9D`입니다. **같은 CA가 Windows에 등록된 PC**가 대상입니다. CA가 다르면 교수자가 확인한 지문을 `-CaThumbprint`로 지정하고, CA가 없으면 오류를 교수자에게 전달합니다. 이 스크립트의 적용 범위는 Minikube 노드의 인증서 신뢰 설정입니다.

인증서 준비가 성공한 뒤, **터미널 B**를 Kubernetes 프로젝트로 돌아가 노드를 만듭니다.

```powershell
cd C:\week6_kubernetes
minikube profile week6
minikube start -p week6 --driver=docker --container-runtime=containerd `
  --ports=8080:30080 --kubernetes-version=v1.35.0 --cpus=2 --memory=3072 --preload=false
kubectl --context=week6 get nodes
```

**확인:** `week6` 노드가 **Ready**입니다. `minikube profile week6`는 기본 프로필을 선택해 `no server found for cluster "minikube"` 오류를 예방합니다. `--preload=false`는 별도로 발견한 사전 다운로드 캐시 오류를 피하는 옵션이며, 인증서 등록을 대신하지 않습니다. 이후 이미지 빌드·전달·배포는 학생 실습 안내를 따릅니다. 저장소 위치가 다르면 `cd` 경로를 실제 폴더에 맞춥니다.

## 1. 실행 — 터미널 A

Docker Desktop을 실행한 뒤 PowerShell에서 입력합니다.

```powershell
cd C:\week6_practice
docker compose up
```

이미지를 빌드한 뒤 실행합니다. <http://localhost:8090>을 열고, **A는 실행 상태로 둡니다.** Kubernetes 프로젝트는 B에서 준비합니다.

## 2. 요청량 변경

<http://localhost:8080>에서 Kubernetes 대시보드가 열리는지 확인합니다. 발생기에서 **프로젝트 검색** 또는 **소개글 분량 검사**를 선택하고 **요청 시작**을 누릅니다.

| 요청량 설정 | 목표가 Pod당 50건/분일 때 이론적 Pod 수 |
| --- | --- |
| 40건/분 | 1개 |
| 120건/분 | 3개 |
| 220건/분 | 5개 |

각 단계에서 **90초 이상** 관찰하고, 실제 성공 요청량과 Ready Pod 수가 안정될 때까지 기다립니다. 발생기의 **성공·실패 수**와 대시보드의 **최근 60초 요청 수·Pod당 평균·목표·Ready 수**를 비교합니다.

## 3. 과제

**수신 프로젝트** `C:\week6_kubernetes\k8s\hpa.yaml`에서 HPA 목표를 **50 → 75건/분**으로 바꾸고 **터미널 B**에서 적용합니다. 발생기의 **220건/분**은 유지하고 Pod 수를 비교합니다.

제출 항목은 [과제 안내](https://github.com/Mok2Lee/week6_kubernetes/blob/main/docs/assignment.md)를 따릅니다. 발생기 코드는 수정하거나 제출하지 않습니다.

## 종료 — 터미널 A

화면의 **요청 중지**를 누릅니다. A에서 **Ctrl+C**로 실행을 멈춘 뒤 입력합니다.

```powershell
docker compose down
```

발생기는 **8090**, Kubernetes 대시보드는 **8080**입니다. 발생기 내부에서는 `http://host.docker.internal:8080`으로 요청을 보냅니다.
