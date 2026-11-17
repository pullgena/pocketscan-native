# PocketScan — 무료 iPhone 문서 스캐너

iOS 17 이상을 대상으로 하는 SwiftUI 문서 스캐너입니다. **v1.1부터 자동 촬영을 제거**하고 아이폰 기본 카메라의 **수동 셔터 버튼**으로만 사진을 촬영합니다. 사진을 불러오거나 여러 페이지를 PDF로 묶는 기능, 필터, 회전, 페이지 순서 변경, 기기 내부 저장을 제공합니다.

## Windows + iPhone만으로 설치하기

1. GitHub 저장소의 **Actions → Build iPhone IPA (free, unsigned)**를 실행합니다. `main` 브랜치에 파일을 올리면 빌드가 자동 실행될 수도 있습니다.
2. 성공한 작업 페이지의 **Artifacts → PocketScan-unsigned-IPA**를 다운로드하고 압축을 해제합니다.
3. Windows용 [Sideloadly](https://sideloadly.io/)에서 생성된 `.ipa`를 iPhone에 설치합니다.
4. 무료 Apple 계정으로 설치한 앱은 일반적으로 7일마다 재서명해야 합니다. 중요한 문서는 PDF로 백업하세요.

> macOS 빌드를 GitHub Actions에서 실행하며, 앱스토어 등록이나 유료 Apple 개발자 계정은 필요하지 않습니다. 개인 설치 목적으로 제공되는 소스 프로젝트입니다. 실제 iPhone 설치와 빌드 호환성은 기기 환경에 따라 확인이 필요합니다. OCR은 포함되지 않습니다.

## 앱 내 GitHub 업데이트 확인 (v1.1)

홈 화면의 **GitHub 업데이트 → 업데이트 확인**을 선택하면, 공개 GitHub 저장소에서 **Build iPhone IPA 워크플로의 최신 성공 빌드**를 조회합니다. 설치한 앱에 내장된 Git 커밋 SHA와 비교하여 새 빌드가 있는지 알려줍니다. '빌드 열기'로 GitHub의 Actions 페이지에 이동할 수 있습니다. GitHub API 접근에 인터넷 연결이 필요합니다.

**중요:** 이 기능은 업데이트 *알림/확인* 전용입니다. iOS 보안 정책상 무료 서명 앱이 GitHub에서 새 IPA를 자동으로 내려받아 스스로 설치할 수는 없습니다. Windows에서 IPA를 내려받아 Sideloadly로 다시 서명/설치해야 합니다. 기존 문서를 유지하려면 같은 bundle identifier로 기존 설치 위에 업데이트하고, 업데이트 전에 PDF로 내보내 백업하는 것을 권장합니다.

기존 앱의 문서 자동 윤곽 보정은 수동 셔터 카메라 전환에 따라 제공되지 않습니다. 수동 촬영으로만 동작합니다.
