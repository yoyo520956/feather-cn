#!/usr/bin/env python3
# 汉化补丁：修复 270 键中的机翻硬伤 + 补 10 缺键 + 预埋新功能全部翻译键
import json, sys

PATH = 'Feather/Resources/Localizable.xcstrings'
d = json.load(open(PATH, encoding='utf-8'))
S = d['strings']

# ---------- 1. 修复现有硬伤 ----------
FIX = {
	'Dismiss': '关闭',
	'None': '不压缩',
	'Ready': '准备就绪',
	'idevice': 'IDevice（高级）',
	'Copy Download URLs': '复制下载链接',
	'Choose from Photos': '从相册选择',
	'New': '新建规则',
	'Info': '信息',
	'Information': '信息',
	'Learn more about how to setup a repository…': '了解如何添加软件源…',
	'Enter a URL to start validation.': '输入链接以开始验证。',
	'Adds the localized description of the app.': '添加应用的本地化描述。',
	'Your pairing file is invalid and is incompatible with your device, please import a valid pairing file.': '配对文件无效或与设备不匹配，请导入有效的配对文件。',
	'Restart Heartbeat': '重启心跳检测',
	'Only use localhost address': '仅使用本地地址',
	'OK': '好',
	'No Apps': '暂无应用',
	'No Certificate': '暂无证书',
	'No Certificates': '暂无证书',
	'No Entitlements listed.': '暂无授权项。',
	'No Privacy Permissions listed.': '未列出隐私权限。',
	'Get Info': '查看信息',
	'Re-sign': '重新签名',
	'Check Revokage': '检查吊销状态',
	'Removal': '移除',
	'%lld Apps': '%lld 个应用',
	'%lld Sources': '%lld 个软件源',
	'%lld Days': '%lld 天',
	'%lld required system dylibs not shown.': '已隐藏 %lld 个系统 dylib',
	'No Repositories': '暂无仓库',
	'No sources to copy': '没有可复制的软件源',
	'Enter Source URL': '输入软件源链接',
	'Repository already added.': '此软件源已添加。',
	'The only supported repositories are AltStore repositories.': '仅支持 AltStore 格式的软件源。',
	'Get started by adding your first repository.': '添加你的第一个软件源开始使用',
	'Open an [issue](https://github.com/khcrysalis/Feather/issues) on GitHub if you want your source to be featured.': '想让你的软件源上榜？去 GitHub 提一个 [issue](https://github.com/khcrysalis/Feather/issues)',
	'Failed to download, check your internet connection and try again.': '下载失败，请检查网络连接后重试。',
	'You cannot update ‘%@‘ with itself, please use an alternative tool to update it.': '无法用“%@”更新它自己，请改用其他方式更新。',
	'Bad Password': '密码错误',
	'Please check the password and try again.': '请检查密码后重试。',
	'Enter the password associated with the private key. Leave it blank if theres no password required.': '输入私钥对应的密码，没有密码则留空。',
	'Enabling any protection will append a random string to the bundleidentifiers of the apps you sign, this is to ensure your Apple ID does not get flagged by Apple. However, when using a signing service you can ignore this.': '启用保护后，签名时包标识符会附加一串随机字符，避免你的 Apple ID 被苹果标记。使用签名服务时可以忽略此项。',
	'Server (Recommended):\nUses a locally hosted server and itms-services:// to install applications.\n\nIDevice (advanced):\nUses a VPN and a pairing file. Writes to AFC and manually calls installd, while monitoring install progress by using a callback\nAdvantage: It is very reliable, does not need SSL certificates or a externally hosted server. Rather, works similarly to a computer.': '服务器（推荐）：\n使用本机服务器和 itms-services:// 协议安装应用。\n\nIDevice（高级）：\n使用 VPN 和配对文件，写入 AFC 并手动调用 installd，通过回调监控安装进度。\n优点：非常可靠，无需 SSL 证书或外部服务器，效果类似电脑侧载。',
	'idevice warning': '此安装方式仅适用于高级用户！\n\n需要 VPN 和来自电脑的配对文件。\n\n建议返回使用服务器方式安装。',
}

# ---------- 2. 缺失键（补 en + zh-Hans） ----------
NEW = {
	'Check for Updates': '检查更新',
	'Disable Liquid Glass': '关闭液态玻璃',
	'Do you want to download and install this file?': '要下载并安装此文件吗？',
	'Download Update': '下载更新',
	'Install Current Version': '安装当前版本',
	'Less': '收起',
	'Merge Entitlements': '合并授权',
	"This option merges entitlements with the embedded entitlements from the app you're signing.": '此选项会将新授权与正在签名的应用内嵌授权合并。',
	'Update': '更新',
	'Update Available': '有可用更新',
	# —— 浏览器 ——
	'Browser': '浏览器',
	'Search or enter address': '搜索或输入网址',
	'Bookmarks': '书签',
	'History': '历史记录',
	'Add Bookmark': '添加书签',
	'Remove Bookmark': '移除书签',
	'New Tab': '新建标签页',
	'Close Tab': '关闭标签页',
	'Clear History': '清除历史记录',
	'No Bookmarks': '暂无书签',
	'Open in Browser': '在浏览器中打开',
	'Open Browser': '打开浏览器',
	'Download': '下载',
	'Downloads': '下载',
	'Downloaded Files': '已下载文件',
	# —— 多线程下载 ——
	'Speed: %@': '速度：%@',
	'Paused': '已暂停',
	'Failed': '失败',
	'Waiting': '等待中',
	'Downloading': '下载中',
	'Multi-threaded Download': '多线程下载',
	'Threads': '线程数',
	'%lld segments': '%lld 个分段',
	'Download Complete': '下载完成',
	'Download Failed': '下载失败',
	# —— 证书到期提醒 ——
	'Certificate Expiring Soon': '证书即将过期',
	'Expires in %lld days': '%lld 天后过期',
	'Expires today': '今天过期',
	'Certificate Expired': '证书已过期',
	'Renew your certificate to avoid apps failing to open.': '请及时更换证书，避免已安装的应用无法打开。',
	"Don't remind me": '不再提醒',
	# —— 批量签名 ——
	'Batch Sign': '批量签名',
	'Select Apps': '选择应用',
	'Queue': '队列',
	'Signing %lld of %lld': '正在签名 %lld / %lld',
	'Add to Queue': '加入队列',
	'Clear Queue': '清空队列',
	'Sign Selected': '签名所选',
	'Batch signing completed': '批量签名完成',
	'Batch signing finished with %lld failure(s)': '批量签名完成，%lld 个失败',
	# —— 局域网导入 ——
	'LAN Import': '局域网导入',
	'Start Server': '启动服务',
	'Stop Server': '停止服务',
	'Scan to upload from your computer': '用电脑扫码即可上传 IPA',
	'Server running at %@': '服务运行于 %@',
	'Imported %lld files': '已导入 %lld 个文件',
	'Upload': '上传',
	'No files uploaded yet': '还没有上传任何文件',
	# —— 空间清理 ——
	'Storage Cleaner': '空间清理',
	'Clean All': '全部清理',
	'Cache': '缓存',
	'Temporary Files': '临时文件',
	'Clean': '清理',
	'Are you sure you want to clean?': '确定要清理吗？',
	'Freed %lld': '已释放 %lld',
	'Remove Downloaded File': '删除下载文件',
}

def zh_unit(v):
	return {'stringUnit': {'state': 'translated', 'value': v}}

changed_fix, changed_new = 0, 0
for k, v in FIX.items():
	if k in S:
		locs = S[k].setdefault('localizations', {})
		locs['zh-Hans'] = zh_unit(v)
		changed_fix += 1
	else:
		print(f'!! FIX 键不存在: {k!r}', file=sys.stderr)

for k, v in NEW.items():
	if k not in S:
		S[k] = {
			'comment': 'Added by cn localization patch',
			'extractionState': 'manual',
			'localizations': {
				'en': zh_unit(k),
				'zh-Hans': zh_unit(v),
			},
		}
		changed_new += 1
	else:
		locs = S[k].setdefault('localizations', {})
		if 'zh-Hans' not in locs:
			locs['zh-Hans'] = zh_unit(v)
			changed_new += 1

json.dump(d, open(PATH, 'w', encoding='utf-8'), ensure_ascii=False, indent=2)
print(f'修复 {changed_fix} 条，新增 {changed_new} 条，总键数 {len(S)}')
