# Fix Installation Error: INSTALL_FAILED_USER_RESTRICTED

## Quick Fix Steps

### On Your Android Device:

1. **Enable Developer Options** (if not already enabled):
   - Go to Settings → About Phone
   - Tap "Build Number" 7 times
   - Go back to Settings → Developer Options

2. **Enable USB Installation**:
   - Settings → Developer Options
   - Enable "USB Debugging"
   - Enable "Install via USB" (if available)
   - Enable "USB Debugging (Security settings)" (if available)

3. **Allow Installation from This Computer**:
   - When you see "Allow USB debugging?" prompt on device
   - Check "Always allow from this computer"
   - Tap "OK"

4. **Enable Unknown Sources** (if needed):
   - Settings → Security → Install unknown apps
   - Or Settings → Apps → Special access → Install unknown apps
   - Enable for your development tool/ADB

### Alternative: Install APK Manually

1. The APK is built successfully at:
   ```
   build\app\outputs\flutter-apk\app-debug.apk
   ```

2. Transfer APK to device:
   ```bash
   adb push build\app\outputs\flutter-apk\app-debug.apk /sdcard/Download/
   ```

3. On device, open File Manager → Downloads → Tap the APK → Install

### Or Try:

```bash
# Force install
adb install -r -d build\app\outputs\flutter-apk\app-debug.apk

# Or uninstall first, then install
adb uninstall com.example.working_emu
flutter run
```

## The Build is Successful!

The error is just a device permission issue. Your code compiled successfully! ✅

