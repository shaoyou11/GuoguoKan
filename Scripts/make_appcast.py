import os
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET

root = pathlib.Path(__file__).resolve().parents[1]
info = plistlib.loads((root / "Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
delivery = pathlib.Path(os.environ.get("GUOGUOKAN_OUTPUT_DIR", str(pathlib.Path.home() / "Library/Caches/GuoguoKan-delivery.noindex")))
archive = delivery / f"GuoguoKan-{version}-arm64.zip"
signer = pathlib.Path.home() / "Library/Caches/GuoguoKan-build/artifacts/sparkle/Sparkle/bin/sign_update"
secret = os.environ.get("SPARKLE_PRIVATE_KEY")
arguments = [str(signer)] + (["--ed-key-file", "-"] if secret else ["--account", "guoguokan-updates"])
signature = subprocess.run(arguments + ["-p", str(archive)], input=secret, text=True, capture_output=True, check=True).stdout.strip()
namespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", namespace)
rss = ET.Element("rss", version="2.0")
channel = ET.SubElement(rss, "channel")
ET.SubElement(channel, "title").text = "果果看更新"
item = ET.SubElement(channel, "item")
ET.SubElement(item, "title").text = f"果果看 {version}"
ET.SubElement(item, f"{{{namespace}}}version").text = info["CFBundleVersion"]
ET.SubElement(item, f"{{{namespace}}}shortVersionString").text = version
ET.SubElement(item, f"{{{namespace}}}minimumSystemVersion").text = "27.0"
ET.SubElement(item, "description").text = "修正欢迎页灰底和大卡片，采用清晰内容区与原生玻璃控件；构建产物改存本机缓存。此版本尚未完成 Developer ID 公证。"
ET.SubElement(item, "enclosure", {"url": f"https://github.com/shaoyou11/GuoguoKan/releases/download/v{version}/{archive.name}", "length": str(archive.stat().st_size), "type": "application/octet-stream", f"{{{namespace}}}edSignature": signature})
output = delivery / "appcast.xml"
ET.ElementTree(rss).write(output, encoding="utf-8", xml_declaration=True)
subprocess.run(arguments + [str(output)], input=secret, text=True, capture_output=True, check=True)
print("已生成并签名更新清单")
