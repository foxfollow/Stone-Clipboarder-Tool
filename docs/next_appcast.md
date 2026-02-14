
# appcast.xml item template

## list of changes

- 🛡️ Separated database storage: clipboard history and settings (excluded apps, hotkeys) now use independent databases — corruption in one won't affect the other
- 🛡️ Crash protection: the app no longer crashes on database initialization failure; corrupted databases are automatically recovered
- 🛡️ All database operations now safely roll back on errors instead of leaving dirty state
- 📝 New "Error Logging" setting (disabled by default) — saves errors to a log file for debugging
- ⚠️ **Note**: Excluded apps and hotkey configurations will be reset on this update due to the database restructuring

## appcast.xml item example

```xml
<item>
    <title>Version VERSION_NUMBER</title>
    <link>https://REPO_OWNER.github.io/REPO_NAME/</link>
    <sparkle:version>VERSION_NUMBER</sparkle:version>
    <sparkle:shortVersionString
    >VERSION_NUMBER</sparkle:shortVersionString>
    <description
    ><![CDATA[
        <h2>StoneClipboarderTool VERSION_NUMBER</h2>
        <ul>
            <li>🛡️ Separated database storage for clipboard history and settings — corruption in one won't affect the other</li>
            <li>🛡️ Crash protection: automatic recovery from database corruption instead of crashes</li>
            <li>🛡️ All database operations now safely roll back on errors</li>
            <li>📝 New optional error logging setting for debugging</li>
            <li>⚠️ Excluded apps and hotkey configurations will be reset due to database restructuring</li>
        </ul>
    ]]></description>
    <pubDate>RELEASE_DATE</pubDate>
    <enclosure
        url="https://github.com/REPO_OWNER/REPO_NAME/releases/download/vVERSION_NUMBER/StoneClipboarderTool.zip"
        sparkle:version="VERSION_NUMBER"
        sparkle:shortVersionString="VERSION_NUMBER"
        sparkle:edSignature="SIGNATURE_PLACEHOLDER"
        length="FILE_SIZE"
        type="application/octet-stream"
    />
</item>
```