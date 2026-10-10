# Android 디버그 APK 빌드

[저장·Android 인수 기준](save-and-android-v0.1.md) 4장의 첫 산출물(설치 가능한 디버그 APK)을 만드는 방법이다. 배포·스토어·운영 서명은 범위 밖이다.

## 사용한 환경 (2026-10-11, Claude / 사용자 Windows PC)

| 항목 | 버전·위치 |
| --- | --- |
| Godot | 4.7.2.stable.official.ed1daf0bf (콘솔 실행 파일) |
| Export templates | `Godot_v4.7.2-stable_export_templates.tpz`(공식 GitHub Releases, 1,281,349,702 bytes)에서 Android 파일만 `%APPDATA%\Godot\export_templates\4.7.2.stable\`에 설치 (`android_debug.apk`, `android_release.apk`, `android_source.zip`, `version.txt`) |
| JDK | Eclipse Temurin 17.0.20.1 (zip, 설치 없이 압축 해제) |
| Android SDK | command-line tools 16111833, platform-tools 37.0.1, build-tools 35.0.0·36.1.0, platforms android-35·36 |
| 디버그 키 | 표준 Android 디버그 키 (`CN=Android Debug`, alias `androiddebugkey`, 비밀번호 `android`) |

JDK·SDK·디버그 키의 경로는 **각 PC의 Godot 편집기 설정**에 둔다. 저장소에는 넣지 않는다.

```
export/android/java_sdk_path = "<JDK 17 폴더>"
export/android/android_sdk_path = "<Android SDK 폴더>"
export/android/debug_keystore = "<debug.keystore 경로>"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
```

새 command-line tools의 `sdkmanager`는 패키지 이름을 `build-tools/36.1.0`, `platforms/android-36`처럼 `/`로 받는다. 예전 형식인 `;`는 찾지 못한다. 라이선스는 설치하면서 수락한다.

## 프로젝트 쪽 설정

- `game/export_presets.cfg`: 프리셋 이름 `Android`, 패키지 ID `dev.gyeolprototype.app`(임시 개발용), arm64-v8a, Gradle 빌드 없이 템플릿 APK를 쓴다. 몰입 모드 켬, 버전 0.1.0 (code 1).
- `project.godot`: Android 내보내기에 필요한 `rendering/textures/vram_compression/import_etc2_astc=true`.
- 세로 화면(`window/handheld/orientation=1`), Compatibility 렌더러는 기존 그대로다.

## 만들기

```powershell
.\tools\build-android.ps1            # build/android/gyeol-prototype-debug.apk
.\tools\build-android.ps1 -Install   # USB 디버깅이 켜진 기기에 adb로 설치
```

내부적으로 `--headless --editor --import`를 먼저 하고, 그다음 `--headless --path game --export-debug "Android" ../build/android/gyeol-prototype-debug.apk`를 실행한다. `build/`는 `.gitignore` 대상이다. APK는 이 PC의 `C:\Users\my\Desktop\output\naruto-story\build\android\`에 생긴다.

## 확인한 것과 안 한 것

- 확인: APK 생성·서명(apksigner verify), 패키지·SDK 정보(aapt2 dump badging). 자세한 값은 [협업 현황](project-status.md)의 Android 기록에 있다.
- **아직 안 함**: 실제 휴대폰 설치·실행, 멀티터치, 안전 영역, 성능·발열, 앱 백그라운드 전환 시 저장. 기준 문서 5장의 항목은 기기에서 따로 기록한다.
