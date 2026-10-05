# 6주차 요청 발생기

슬라이더로 요청량을 바꾸고 Kubernetes API의 Pod 수를 관찰합니다. 이 저장소는 **요청을 보내는 앱**이며 Docker Compose로 실행합니다. 요청을 받는 API와 대시보드는 별도 [week6_practice](https://github.com/Mok2Lee/week6_practice) 저장소입니다.

## 1. 수신 프로젝트 먼저 실행

[학생 실습 안내](https://github.com/Mok2Lee/week6_practice/blob/main/docs/student-lab.md)의 준비·배포 단계를 먼저 진행합니다. 학교와 집에서 같은 제공 이미지·캐시를 사용합니다. 이 앱을 실행하기 위해 Windows에 Python이나 Flask를 설치하지 않습니다.

| 위치 | 내용 |
| --- | --- |
| `C:\lab\week6` | Kubernetes 수신 프로젝트 |
| `C:\lab\week6_sender` | 이 저장소의 `app.py`, `static`, `compose.yaml` |
| `C:\lab\offline\week6_images.tar` | 요청 발생기 이미지를 포함한 제공 파일 |

두 프로젝트는 같은 상위 폴더 아래 **나란히** 둡니다. 제공 이미지를 `docker load`로 불러오고, <http://localhost:8080>에서 수신 대시보드가 열리는지 확인합니다.

VS Code의 PowerShell은 **2개**를 사용합니다.

| 터미널 | 현재 폴더 | 역할 |
| --- | --- | --- |
| **A — 실습 관리** | `C:\lab\week6` | Kubernetes 관리와 발생기 실행·종료 |
| **B — 대시보드 연결** | `C:\lab\week6` | `kubectl port-forward service/web 8080:80` 실행 상태 유지 |

## 2. 요청 발생기 실행

새 터미널을 만들지 않습니다. **터미널 A**에서 옆 폴더의 Compose 파일을 지정합니다.

```powershell
cd C:\lab\week6
docker compose -f ../week6_sender/compose.yaml up -d --no-build --pull never
docker compose -f ../week6_sender/compose.yaml ps
```

**확인:** `week6_sender01`이 실행됩니다. 위 명령은 제공된 이미지를 사용하며 빌드나 이미지 다운로드를 하지 않습니다.

<http://localhost:8090>에서 **프로젝트 검색** 또는 **소개글 분량 검사**를 선택하고 **요청 시작**을 누릅니다. 대시보드와 발생기를 함께 보면서 요청량을 바꿉니다.

| 요청량 설정 | 관찰 시간 | 목표가 Pod당 50건/분일 때 이론적 Pod 수 |
| --- | --- | --- |
| 40건/분 | 90초 이상 | 1개 |
| 120건/분 | 90초 이상 | 3개 |
| 220건/분 | 90초 이상 | 5개 |
| 요청 중지 | 최근 요청 수가 줄고 축소될 때까지 | 최소 1개 |

각 단계에서 **실제 성공 요청 수·실패 수·Ready Pod 수·응답 Pod 이름**을 확인합니다. 표는 실제 성공 요청량이 설정값에 도달했을 때의 예상값입니다. 최근 60초 집계와 Pod 준비 때문에 값이 계속 바뀌면 안정될 때까지 더 기다립니다.

## 3. 과제: 요청량과 HPA 기준 비교

1. 기본 기준 **50건/분**으로 40 → 120 → 220건/분을 보내고 실제 요청량과 Pod 수를 기록합니다.
2. 수신 프로젝트 `C:\lab\week6\k8s\hpa.yaml`에서 목표를 **50 → 75건/분**으로 바꾸고 적용합니다.
3. 발생기의 **220건/분**을 유지하며 변경 전후 Pod 수를 비교합니다. 75건 기준의 이론적 Pod 수는 3개입니다.
4. **요청 중지**를 누른 뒤 최소 1개로 줄어드는 과정을 확인합니다.

수정·적용 명령과 제출 항목은 [과제 안내](https://github.com/Mok2Lee/week6_practice/blob/main/docs/assignment.md)를 따릅니다. 발생기 코드는 수정하거나 제출하지 않습니다.

## 종료

먼저 발생기 화면의 **요청 중지**를 누릅니다. **터미널 A / C:\lab\week6**에서 실행합니다.

```powershell
docker compose -f ../week6_sender/compose.yaml down
```

수신 자원 정리와 Minikube 종료는 학생 실습 안내의 마지막 단계를 따릅니다.

## 연결 확인

| 증상 | 확인할 내용 |
| --- | --- |
| Compose 파일을 찾지 못함 | A의 현재 폴더가 `C:\lab\week6`인지 확인 |
| `week6_sender01` 이미지가 없음 | 제공 `week6_images.tar`를 `docker load`로 불러왔는지 확인 |
| 요청 발생기는 열리지만 요청 실패 | 8080 대시보드·API 상태와 터미널 B의 연결 유지 확인 |

발생기 주소는 **8090**, 수신 대시보드는 **8080**입니다. 발생기 내부에서는 `http://host.docker.internal:8080`으로 요청합니다. 슬라이더 최대값은 250건/분이며, 이미 보내는 중인 요청 1건은 중지 후 완료될 수 있습니다.
