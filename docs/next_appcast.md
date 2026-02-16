
# appcast.xml item template

## list of changes

- notes...

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
            <li>notes...</li>
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