# PocketScan — 무료 iPhone 문서 스캐너

iOS 17 이상에서 실행되는 SwiftUI 문서 스캐너입니다. Apple VisionKit으로 문서를 촬영·모서리 보정하고, 여러 페이지를 PDF로 내보낼 수 있습니다. 사진 가져오기, 색상 필터, 회전, 페이지 순서 변경 및 로컬 저장을 지원합니다.

## Windows + iPhone만으로 설치하기

1. GitHub 저장소의 **Actions → Build iPhone IPA (free, unsigned)**를 실행합니다. `main` 브랜치에 파일을 올리면 빌드가 자동 실행될 수도 있습니다.
2. 성공한 작업 페이지의 **Artifacts → PocketScan-unsigned-IPA**를 다운로드하고 압축을 해제합니다.
3. Windows용 [Sideloadly](https://sideloadly.io/)에서 생성된 `.ipa`를 iPhone에 설치합니다.
4. 무료 Apple 계정으로 설치한 앱은 일반적으로 7일마다 재서명해야 합니다. 중요한 문서는 PDF로 백업하세요.

> macOS 빌드를 GitHub Actions에서 실행하며, 앱스토어 등록이나 유료 Apple 개발자 계정은 필요하지 않습니다. 개인 설치 목적으로 제공되는 소스 프로젝트입니다. 실제 iPhone 설치와 빌드 호환성은 기기 환경에 따라 확인이 필요합니다. OCR은 포함되지 않습니다.
