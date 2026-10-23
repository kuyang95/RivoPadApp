#!/usr/bin/env python3
"""Regenerate native source enums from docs/news_publishers.json in this repo or --peer repos."""
from pathlib import Path
import argparse,json,re

def regenerate(root):
 catalog=json.loads((root/'docs/news_publishers.json').read_text())['publishers']
 quote=lambda v:json.dumps(v,ensure_ascii=False)
 android=root/'app/src/main/java/net/rivo/visioncraft/launcher/LauncherNewsWidget.kt'
 ipad=root/'shortcuts_example/Launcher/RatioNewsWidget.swift'
 if android.exists():
  cases=[]
  for p in catalog:
   domains='listOf('+', '.join(quote(d)for d in p['domains'])+')'
   feeds='mapOf('+', '.join(quote(k)+' to '+quote(v)for k,v in p['feeds'].items())+')'
   cases.append('    '+p['id'].upper()+'('+', '.join([quote(p['id']),quote(p['label']),domains,feeds])+')')
  enum='''// Generated from docs/news_publishers.json by tools/generate_news_sources.py.
internal enum class LauncherNewsSource(val id: String, val label: String, private val domains: List<String>, private val feeds: Map<String, String>) {
'''+',\n'.join(cases)+''';
    fun accepts(value: String): Boolean = runCatching {
        val uri = Uri.parse(value); val host = uri.host?.lowercase(Locale.ROOT).orEmpty()
        uri.scheme == "https" && uri.userInfo == null && domains.any { host == it || host.endsWith(".$it") }
    }.getOrDefault(false)
    fun articleURL(value: String): String? {
        val clean = value.trim().replace("&amp;", "&")
        val uri = Uri.parse(clean)
        val candidate = if (uri.scheme == "http") uri.buildUpon().scheme("https").build().toString() else clean
        return candidate.takeIf(::accepts)
    }
    fun feed(category: LauncherNewsCategory): String? = feeds[category.feed]
    companion object {
        fun available(category: LauncherNewsCategory) = entries.filter { it.feed(category) != null }
    }
}
'''
  s=android.read_text();a=s.index('internal enum class LauncherNewsSource');b=s.index('internal data class LauncherNewsItem',a)
  if s[:a].endswith('// Generated from docs/news_publishers.json by tools/generate_news_sources.py.\n'):a=s.rfind('// Generated',0,a)
  android.write_text(s[:a]+enum+s[b:])
 elif ipad.exists():
  enum='''// Generated from docs/news_publishers.json by tools/generate_news_sources.py.
private nonisolated enum NewsSource: String, CaseIterable, Codable, Sendable {
    case '''+', '.join(p['id']for p in catalog)+'\n'
  for prop,body in [('title',lambda p:quote(p['label'])),('domains',lambda p:'['+', '.join(quote(d)for d in p['domains'])+']'),('feeds',lambda p:'['+', '.join(quote(k)+': '+quote(v)for k,v in p['feeds'].items())+']')]:
   vartype='String'if prop=='title'else'[String]'if prop=='domains'else'[String: String]'
   enum+=('    var 'if prop=='title'else'    private var ')+prop+': '+vartype+' { switch self {\n'
   enum+='\n'.join('        case .'+p['id']+': '+body(p)for p in catalog)+'\n    } }\n'
  enum+='''    func accepts(_ value: String) -> Bool {
        guard let url = URL(string: value), url.scheme == "https", url.user == nil, let host = url.host?.lowercased() else { return false }
        return domains.contains { host == $0 || host.hasSuffix(".\\($0)") }
    }
    func articleURL(_ value: String) -> String? {
        guard var url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "&amp;", with: "&")) else { return nil }
        if url.scheme == "http" { url.scheme = "https" }
        guard let candidate = url.string, accepts(candidate) else { return nil }
        return candidate
    }
    func feed(_ category: NewsCategory) -> URL? { feeds[category.rawValue].flatMap { URL(string: $0) } }
    static func available(_ category: NewsCategory) -> [NewsSource] { allCases.filter { $0.feed(category) != nil } }
}
'''
  s=ipad.read_text();a=s.index('private nonisolated enum NewsSource');b=s.index('private nonisolated struct NewsArticle',a)
  if s[:a].endswith('// Generated from docs/news_publishers.json by tools/generate_news_sources.py.\n'):a=s.rfind('// Generated',0,a)
  ipad.write_text(s[:a]+enum+s[b:])
 else:raise ValueError('No native news widget at '+str(root))
 print(root.name,len(catalog),'sources generated')
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);parser.add_argument('--peer',type=Path,action='append',default=[])
 args=parser.parse_args()
 for root in [args.root,*args.peer]:regenerate(root)
