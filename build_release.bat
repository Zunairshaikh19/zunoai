@echo off
cd /d D:\zunoai
call flutter build appbundle --release -PADMOB_APP_ID=ca-app-pub-6805277116031156~6634211513 --dart-define=ADMOB_REWARDED_ANDROID=ca-app-pub-6805277116031156/6442639823 --dart-define=ADMOB_INTERSTITIAL_ANDROID=ca-app-pub-6805277116031156/3142136174 --dart-define=ADMOB_NATIVE_ANDROID=ca-app-pub-6805277116031156/3704795840
echo.
echo Done. AAB: D:\zunoai\build\app\outputs\bundle\release\app-release.aab
pause
