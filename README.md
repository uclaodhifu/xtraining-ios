# X Training（iOS / iPadOS）

原生 SwiftUI 版健身手记。

- `.github/workflows/ipa.yml`：每次推送到 main，云端编译检查，产出未签名 ipa。
- `.github/workflows/testflight.yml`：填好 Secrets（TEAM_ID、ASC_KEY_ID、ASC_ISSUER_ID、ASC_KEY_P8）后，手动运行上传 TestFlight。
