#!/usr/bin/env python3
# Feather CN QA: 括号状态机 + UTF-8 + 关键符号引用检查
import sys, re, os

FILES = [
    'Feather/Backend/Observable/SegmentedDownloader.swift',
    'Feather/Backend/Observable/BrowserManager.swift',
    'Feather/Backend/Observable/CertExpiryMonitor.swift',
    'Feather/Backend/Observable/SigningQueue.swift',
    'Feather/Backend/Server/LANImportServer.swift',
    'Feather/Views/Browser/BrowserView.swift',
    'Feather/Views/Download/DownloadsListView.swift',
    'Feather/Views/Download/DownloadHeaderView.swift',
    'Feather/Views/Library/BatchSignView.swift',
    'Feather/Views/Settings/LANImportView.swift',
    'Feather/Views/Settings/StorageCleanerView.swift',
    'Feather/Views/Settings/Certificates/CertificatesView.swift',
    'Feather/Views/Settings/SettingsView.swift',
    'Feather/Views/Library/LibraryView.swift',
    'Feather/Views/Sources/SourcesView.swift',
    'Feather/Views/TabView/TabEnum.swift',
    'Feather/Backend/Observable/DownloadManager.swift',
    'Feather/FeatherApp.swift',
]

def bracket_check(path):
    t = open(path, encoding='utf-8').read()
    # state machine: strip strings & comments
    i, n = 0, len(t)
    depth_paren = depth_brace = depth_brack = 0
    line = 1
    errors = []
    interp_depth = 0
    while i < n:
        c = t[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        # line comment
        if t.startswith('//', i):
            j = t.find('\n', i)
            i = j if j != -1 else n
            continue
        # block comment
        if t.startswith('/*', i):
            j = t.find('*/', i + 2)
            line += t.count('\n', i, j if j != -1 else n)
            i = (j + 2) if j != -1 else n
            continue
        # string (handle triple-quoted multiline strings)
        if t.startswith('"""', i):
            j = t.find('"""', i + 3)
            line += t.count('\n', i, j if j != -1 else n)
            i = (j + 3) if j != -1 else n
            continue
        if c == '"':
            i += 1
            while i < n:
                ch = t[i]
                if ch == '\n':
                    errors.append(f'{path}:{line} unterminated string')
                    break
                if ch == '\\':
                    i += 2
                    continue
                # interpolation \( -> track nested parens
                if ch == '\\' and i + 1 < n and t[i+1] == '(':
                    interp_depth += 1
                    i += 2
                    idp = 1
                    while i < n and idp > 0:
                        if t[i] == '\n':
                            line += 1
                        if t[i] == '(':
                            idp += 1
                        elif t[i] == ')':
                            idp -= 1
                        i += 1
                    interp_depth -= 1
                    continue
                if ch == '"':
                    i += 1
                    break
                i += 1
            continue
        if c == '(':
            depth_paren += 1
        elif c == ')':
            depth_paren -= 1
            if depth_paren < 0:
                errors.append(f'{path}:{line} unmatched )')
                depth_paren = 0
        elif c == '{':
            depth_brace += 1
        elif c == '}':
            depth_brace -= 1
            if depth_brace < 0:
                errors.append(f'{path}:{line} unmatched }}')
                depth_brace = 0
        elif c == '[':
            depth_brack += 1
        elif c == ']':
            depth_brack -= 1
            if depth_brack < 0:
                errors.append(f'{path}:{line} unmatched ]')
                depth_brack = 0
        i += 1
    if depth_paren or depth_brace or depth_brack:
        errors.append(f'{path}: EOF imbalance paren={depth_paren} brace={depth_brace} brack={depth_brack}')
    return errors

def utf8_check(path):
    try:
        open(path, encoding='utf-8').read()
        return []
    except Exception as e:
        return [f'{path}: UTF-8 {e}']

fails = 0
for f in FILES:
    errs = bracket_check(f) + utf8_check(f)
    if errs:
        fails += 1
        for e in errs:
            print('FAIL', e)

# 引用完整性
REFS = [
    ('Feather/Views/Browser/BrowserView.swift', ['BrowserTab', 'BrowserManager', 'BrowserURLHelper', 'DownloadsListView', 'UIActivityViewController.show']),
    ('Feather/Backend/Observable/DownloadManager.swift', ['SegmentedDownloadSession', 'handlePachageFile']),
    ('Feather/Views/Library/BatchSignView.swift', ['FRAppIconView', 'SigningQueue', 'NBSection']),
    ('Feather/Views/Settings/LANImportView.swift', ['LANImportServer', 'qrCodeGenerator']),
    ('Feather/Backend/Observable/CertExpiryMonitor.swift', ['getAllCertificates', 'UNUserNotificationCenter']),
    ('Feather/Views/TabView/TabEnum.swift', ['BrowserView', 'browser']),
]
for path, syms in REFS:
    t = open(path, encoding='utf-8').read()
    for s in syms:
        if s not in t:
            print('FAIL missing reference', s, 'in', path)
            fails += 1

# 存在性：被引用的符号必须在工程中定义
import subprocess
for sym in ['FRAppIconView', 'NBSection', 'NBToolbarButton']:
    r = subprocess.run(['rg', '-l', '-F', sym, 'Feather/', 'NimbleKit/'], capture_output=True, text=True)
    if r.returncode != 0 or not r.stdout.strip():
        print('FAIL symbol not found anywhere:', sym)
        fails += 1

# emoji 残留（新文件）
import unicodedata
for f in FILES:
    t = open(f, encoding='utf-8').read()
    for ch in t:
        cp = ord(ch)
        if cp >= 0x1F300 and cp <= 0x1FAFF or cp in (0x2764,):
            print('FAIL emoji', hex(cp), 'in', f)
            fails += 1
            break

print('QA 完成:', '❌ %d 组失败' % fails if fails else '✅ 全绿')
